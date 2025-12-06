import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../shared/models/proxy_node.dart';
import '../../../../shared/themes/app_theme.dart';
import '../../domain/nodes_provider.dart';
import '../../../dashboard/domain/connection_provider.dart';
import '../../../auth/domain/auth_provider.dart';

class NodesPage extends ConsumerWidget {
  const NodesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodesState = ref.watch(nodesProvider);
    final connectionState = ref.watch(connectionProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nodes',
                        style: GoogleFonts.outfit(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ).animate().fadeIn().slideX(begin: -0.1, end: 0),
                      const SizedBox(height: 4),
                      Text(
                        '${nodesState.nodes.length} available servers',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ).animate().fadeIn(delay: 100.ms).slideX(begin: -0.1, end: 0),
                    ],
                  ),
                  Row(
                    children: [
                      // Speed Test Button
                      Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.dividerColor.withOpacity(0.1),
                          ),
                        ),
                        child: IconButton(
                          onPressed: () {
                            if (nodesState.isTesting) {
                              ref.read(nodesProvider.notifier).stopTesting();
                            } else {
                              ref.read(nodesProvider.notifier).testAllLatencies();
                            }
                          },
                          icon: Icon(
                            nodesState.isTesting ? Icons.stop_rounded : Icons.speed_rounded,
                            color: nodesState.isTesting ? AppTheme.warningColor : theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                          tooltip: nodesState.isTesting ? 'Stop Test' : 'Test All',
                        ),
                      ).animate().fadeIn(delay: 200.ms).scale(),
                      
                      const SizedBox(width: 12),
                      
                      // Refresh Button
                      Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.dividerColor.withOpacity(0.1),
                          ),
                        ),
                        child: IconButton(
                          onPressed: () async {
                            final authState = ref.read(authProvider);
                            final subscribeUrl =
                                authState.user?.subscription.subscriptionUrl;
                            if (subscribeUrl != null && subscribeUrl.isNotEmpty) {
                              try {
                                await ref
                                    .read(nodesProvider.notifier)
                                    .refreshNodesFromUrl(subscribeUrl);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Nodes updated successfully')),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Update failed: $e')),
                                  );
                                }
                              }
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please login to get subscription')),
                              );
                            }
                          },
                          icon: Icon(
                            Icons.refresh_rounded,
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                          tooltip: 'Refresh Subscription',
                        ),
                      ).animate().fadeIn(delay: 300.ms).scale(),
                    ],
                  ),
                ],
              ),
            ),

            // Nodes list
            Expanded(
              child: nodesState.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : nodesState.nodes.isEmpty
                  ? _buildEmptyState(context)
                  : _buildNodesList(context, ref, nodesState, connectionState),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.dns_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No Nodes Available',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            'Please refresh subscription to get nodes',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade500),
          ),
        ],
      ),
    ).animate().fadeIn().scale();
  }

  Widget _buildNodesList(
    BuildContext context,
    WidgetRef ref,
    NodesState nodesState,
    VpnConnectionState connectionState,
  ) {
    // Group nodes by group name
    final groupedNodes = <String, List<ProxyNode>>{};
    for (final node in nodesState.nodes) {
      final group = node.group ?? 'Default Group';
      groupedNodes.putIfAbsent(group, () => []).add(node);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
      itemCount: groupedNodes.length,
      itemBuilder: (context, index) {
        final group = groupedNodes.keys.elementAt(index);
        final nodes = groupedNodes[group]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                group,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                  letterSpacing: 0.5,
                ),
              ),
            ).animate().fadeIn(delay: (index * 50).ms).slideX(),
            ...nodes.map(
              (node) => _NodeTile(
                node: node,
                isConnected: connectionState.connectedNode?.id == node.id,
                latency: nodesState.latencies[node.id],
                isTesting: nodesState.isTesting,
                hasTested: nodesState.latencies.containsKey(node.id),
                onTap: () {
                  ref.read(connectionProvider.notifier).switchNode(node);
                },
              ).animate().fadeIn(delay: (index * 50 + 100).ms).slideY(begin: 0.1, end: 0),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

class _NodeTile extends StatelessWidget {
  final ProxyNode node;
  final bool isConnected;
  final int? latency;
  final bool isTesting; // 是否正在批量测速
  final bool hasTested; // 该节点是否已测试完成
  final VoidCallback onTap;

  const _NodeTile({
    required this.node,
    required this.isConnected,
    this.latency,
    this.isTesting = false,
    this.hasTested = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isConnected 
            ? AppTheme.primaryColor.withOpacity(0.05) 
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConnected 
              ? AppTheme.primaryColor.withOpacity(0.2) 
              : theme.dividerColor.withOpacity(0.05),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isConnected
                        ? AppTheme.primaryColor.withOpacity(0.1)
                        : theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isConnected ? Icons.check_circle_rounded : Icons.dns_rounded,
                    color: isConnected ? AppTheme.primaryColor : theme.colorScheme.onSurfaceVariant,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              node.name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: isConnected ? FontWeight.w600 : FontWeight.w500,
                                color: theme.colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (node.multiplier != 1.0)
                            _Tag(label: '${node.multiplier}x', color: AppTheme.warningColor),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '${node.protocol.name.toUpperCase()} · ${node.server}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ...node.tags.take(3).map(
                            (tag) => Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: _Tag(label: _getTagLabel(tag), color: _getTagColor(tag)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Latency
                _buildLatencyWidget(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建延迟显示组件
  Widget _buildLatencyWidget(ThemeData theme) {
    // 已测试完成 - 显示延迟或超时
    if (hasTested) {
      if (latency != null && latency! > 0) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _getLatencyColor(latency!).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$latency ms',
            style: TextStyle(
              color: _getLatencyColor(latency!),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        );
      } else {
        // 超时或失败
        return Text(
          'Timeout',
          style: TextStyle(
            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        );
      }
    }

    // 正在测速但还没轮到这个节点 - 显示等待中的小图标
    if (isTesting) {
      return SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
        ),
      );
    }

    // 未测试 - 显示箭头
    return Icon(
      Icons.chevron_right_rounded,
      color: theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
    );
  }

  String _getTagLabel(NodeTag tag) {
    switch (tag) {
      case NodeTag.unlock:
        return 'Unlock';
      case NodeTag.gaming:
        return 'Game';
      case NodeTag.streaming:
        return 'Stream';
      case NodeTag.chatgpt:
        return 'GPT';
      case NodeTag.netflix:
        return 'NF';
      case NodeTag.disney:
        return 'D+';
      case NodeTag.custom:
        return node.customTag ?? 'Tag';
    }
  }

  Color _getTagColor(NodeTag tag) {
    switch (tag) {
      case NodeTag.unlock:
        return AppTheme.successColor;
      case NodeTag.gaming:
        return AppTheme.accentColor;
      case NodeTag.streaming:
        return AppTheme.secondaryColor;
      case NodeTag.chatgpt:
        return const Color(0xFF10A37F);
      case NodeTag.netflix:
        return const Color(0xFFE50914);
      case NodeTag.disney:
        return const Color(0xFF113CCF);
      case NodeTag.custom:
        return AppTheme.primaryColor;
    }
  }

  Color _getLatencyColor(int latency) {
    if (latency < 100) return AppTheme.connectedColor;
    if (latency < 300) return AppTheme.warningColor;
    return AppTheme.errorColor;
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;

  const _Tag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
