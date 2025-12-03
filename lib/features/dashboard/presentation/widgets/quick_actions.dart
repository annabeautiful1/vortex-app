import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/themes/app_theme.dart';

class QuickActions extends StatelessWidget {
  const QuickActions({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '快捷操作',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _QuickActionButton(
              icon: Icons.dns,
              label: '节点列表',
              onTap: () => context.go('/nodes'),
            ),
            _QuickActionButton(
              icon: Icons.speed,
              label: '测速',
              onTap: () {
                // TODO: Speed test
              },
            ),
            _QuickActionButton(
              icon: Icons.refresh,
              label: '更新订阅',
              onTap: () {
                // TODO: Refresh subscription
              },
            ),
            _QuickActionButton(
              icon: Icons.support_agent,
              label: '在线客服',
              onTap: () => context.go('/support'),
            ),
            _QuickActionButton(
              icon: Icons.article_outlined,
              label: '查看日志',
              onTap: () {
                // TODO: View logs
              },
            ),
            _QuickActionButton(
              icon: Icons.info_outline,
              label: '公告',
              onTap: () {
                // TODO: Show announcements
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 100,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 28,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
