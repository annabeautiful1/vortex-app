import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/themes/app_theme.dart';
import '../../../../core/platform/platform_channel_service.dart';
import '../../domain/connection_provider.dart';

/// 实时流量速度卡片 - 显示上传/下载速度
class RealtimeTrafficCard extends ConsumerWidget {
  const RealtimeTrafficCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(connectionProvider);
    final trafficAsync = ref.watch(trafficStatsProvider);
    final isConnected = connectionState.isConnected;

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
                  child: Icon(Icons.speed, color: AppTheme.primaryColor),
                ),
                const SizedBox(width: 12),
                Text(
                  '实时速度',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            trafficAsync.when(
              data: (stats) =>
                  _buildTrafficContent(context, stats, isConnected),
              loading: () => _buildTrafficContent(
                context,
                connectionState.trafficStats,
                isConnected,
              ),
              error: (e, _) => _buildTrafficContent(
                context,
                connectionState.trafficStats,
                isConnected,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrafficContent(
    BuildContext context,
    TrafficStats stats,
    bool isConnected,
  ) {
    return Column(
      children: [
        // 上传/下载速度
        Row(
          children: [
            Expanded(
              child: _SpeedIndicator(
                icon: Icons.arrow_upward,
                label: '上传',
                speed: stats.formattedUploadSpeed,
                color: AppTheme.uploadColor,
                isActive: isConnected,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _SpeedIndicator(
                icon: Icons.arrow_downward,
                label: '下载',
                speed: stats.formattedDownloadSpeed,
                color: AppTheme.downloadColor,
                isActive: isConnected,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 12),
        // 累计流量
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _TrafficTotal(label: '本次上传', value: stats.formattedUpload),
            _TrafficTotal(label: '本次下载', value: stats.formattedDownload),
          ],
        ),
      ],
    );
  }
}

class _SpeedIndicator extends StatelessWidget {
  final IconData icon;
  final String label;
  final String speed;
  final Color color;
  final bool isActive;

  const _SpeedIndicator({
    required this.icon,
    required this.label,
    required this.speed,
    required this.color,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    final displayColor = isActive ? color : Colors.grey;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: displayColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: displayColor, size: 20),
              const SizedBox(width: 4),
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: displayColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            speed,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: displayColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrafficTotal extends StatelessWidget {
  final String label;
  final String value;

  const _TrafficTotal({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
