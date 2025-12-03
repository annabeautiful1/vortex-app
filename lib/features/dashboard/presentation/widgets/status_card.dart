import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/themes/app_theme.dart';
import '../../domain/connection_provider.dart';

class StatusCard extends ConsumerWidget {
  const StatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(connectionProvider);
    final isConnected = connectionState.status == ConnectionStatus.connected;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.info_outline, color: AppTheme.primaryColor),
                ),
                const SizedBox(width: 12),
                Text(
                  '连接状态',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _StatusRow(
              label: '状态',
              value: isConnected ? '已连接' : '未连接',
              valueColor: isConnected ? AppTheme.connectedColor : Colors.grey,
            ),
            const SizedBox(height: 12),
            _StatusRow(
              label: '模式',
              value: connectionState.tunEnabled ? 'TUN 模式' : '系统代理',
            ),
            const SizedBox(height: 12),
            _StatusRow(
              label: '延迟',
              value: connectionState.latency != null
                  ? '${connectionState.latency} ms'
                  : '-',
              valueColor: _getLatencyColor(connectionState.latency),
            ),
            const SizedBox(height: 12),
            _StatusRow(
              label: '协议',
              value:
                  connectionState.connectedNode?.protocol.name.toUpperCase() ??
                  '-',
            ),
          ],
        ),
      ),
    );
  }

  Color _getLatencyColor(int? latency) {
    if (latency == null) return Colors.grey;
    if (latency < 100) return AppTheme.connectedColor;
    if (latency < 300) return AppTheme.warningColor;
    return AppTheme.errorColor;
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _StatusRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
