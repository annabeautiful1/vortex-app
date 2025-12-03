import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/models/proxy_node.dart';
import '../../../../shared/themes/app_theme.dart';
import '../../domain/nodes_provider.dart';
import '../../../dashboard/domain/connection_provider.dart';

class NodesPage extends ConsumerWidget {
  const NodesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodesState = ref.watch(nodesProvider);
    final connectionState = ref.watch(connectionProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '节点列表',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${nodesState.nodes.length} 个节点可用',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => ref.read(nodesProvider.notifier).testAllLatencies(),
                        icon: const Icon(Icons.speed),
                        tooltip: '测速全部',
                      ),
                      IconButton(
                        onPressed: () => ref.read(nodesProvider.notifier).refreshNodes(),
                        icon: const Icon(Icons.refresh),
                        tooltip: '刷新订阅',
                      ),
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
          Icon(
            Icons.dns_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无节点',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '请先更新订阅获取节点',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade500,
                ),
          ),
        ],
      ),
    );
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
      final group = node.group ?? '默认分组';
      groupedNodes.putIfAbsent(group, () => []).add(node);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: groupedNodes.length,
      itemBuilder: (context, index) {
        final group = groupedNodes.keys.elementAt(index);
        final nodes = groupedNodes[group]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                group,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
            ...nodes.map((node) => _NodeTile(
                  node: node,
                  isConnected: connectionState.connectedNode?.id == node.id,
                  latency: nodesState.latencies[node.id],
                  onTap: () {
                    ref.read(connectionProvider.notifier).switchNode(node);
                  },
                )),
            const SizedBox(height: 16),
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
  final VoidCallback onTap;

  const _NodeTile({
    required this.node,
    required this.isConnected,
    this.latency,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isConnected
          ? AppTheme.primaryColor.withOpacity(0.1)
          : null,
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isConnected
                ? AppTheme.connectedColor.withOpacity(0.1)
                : Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isConnected ? Icons.check_circle : Icons.dns,
            color: isConnected ? AppTheme.connectedColor : Colors.grey,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                node.name,
                style: TextStyle(
                  fontWeight: isConnected ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Tags
            if (node.multiplier != 1.0)
              _Tag(
                label: '${node.multiplier}x',
                color: AppTheme.warningColor,
              ),
            ...node.tags.map((tag) => _Tag(
                  label: _getTagLabel(tag),
                  color: _getTagColor(tag),
                )),
          ],
        ),
        subtitle: Text(
          '${node.protocol.name.toUpperCase()} · ${node.server}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: latency != null
            ? Text(
                '$latency ms',
                style: TextStyle(
                  color: _getLatencyColor(latency!),
                  fontWeight: FontWeight.w600,
                ),
              )
            : const Icon(Icons.chevron_right),
      ),
    );
  }

  String _getTagLabel(NodeTag tag) {
    switch (tag) {
      case NodeTag.unlock:
        return '解锁';
      case NodeTag.gaming:
        return '游戏';
      case NodeTag.streaming:
        return '流媒体';
      case NodeTag.chatgpt:
        return 'GPT';
      case NodeTag.netflix:
        return 'NF';
      case NodeTag.disney:
        return 'D+';
      case NodeTag.custom:
        return node.customTag ?? '标签';
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

  const _Tag({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
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
