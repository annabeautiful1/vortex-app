import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/themes/app_theme.dart';
import '../../../auth/domain/auth_provider.dart';

class TrafficCard extends ConsumerWidget {
  const TrafficCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final subscription = authState.user?.subscription;

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
                    color: AppTheme.accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.data_usage, color: AppTheme.accentColor),
                ),
                const SizedBox(width: 12),
                Text(
                  '流量使用',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (subscription != null) ...[
              // Traffic progress
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '已用 ${_formatBytes(subscription.trafficUsed)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        '总计 ${_formatBytes(subscription.trafficTotal)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: subscription.trafficTotal > 0
                        ? subscription.trafficUsed / subscription.trafficTotal
                        : 0,
                    backgroundColor: Colors.grey.withValues(alpha: 0.2),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _getTrafficColor(
                        subscription.trafficUsed,
                        subscription.trafficTotal,
                      ),
                    ),
                    borderRadius: BorderRadius.circular(4),
                    minHeight: 8,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _InfoRow(label: '套餐', value: subscription.planName),
              const SizedBox(height: 12),
              _InfoRow(
                label: '到期',
                value: _formatDate(subscription.expireAt),
                valueColor: subscription.expireAt.isBefore(DateTime.now())
                    ? AppTheme.errorColor
                    : null,
              ),
              const SizedBox(height: 12),
              _InfoRow(
                label: '剩余',
                value: _formatBytes(subscription.trafficRemaining),
              ),
            ] else ...[
              const Center(child: Text('暂无套餐信息')),
            ],
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Color _getTrafficColor(int used, int total) {
    if (total == 0) return Colors.grey;
    final ratio = used / total;
    if (ratio < 0.5) return AppTheme.connectedColor;
    if (ratio < 0.8) return AppTheme.warningColor;
    return AppTheme.errorColor;
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({required this.label, required this.value, this.valueColor});

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
