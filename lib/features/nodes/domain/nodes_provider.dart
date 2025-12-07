import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/proxy_node.dart';
import '../../../core/vpn/vpn_service.dart';
import '../../../core/subscription/subscription_parser.dart';
import '../../../shared/services/storage_service.dart';
import '../../../shared/constants/app_constants.dart';
import '../../../core/utils/logger.dart';

class NodesState {
  final List<ProxyNode> nodes;
  final Map<String, int?> latencies;
  final bool isLoading;
  final bool isTesting; // 测速中状态（区别于加载节点）
  final String? error;
  final String? subscribeUrl;

  const NodesState({
    this.nodes = const [],
    this.latencies = const {},
    this.isLoading = false,
    this.isTesting = false,
    this.error,
    this.subscribeUrl,
  });

  NodesState copyWith({
    List<ProxyNode>? nodes,
    Map<String, int?>? latencies,
    bool? isLoading,
    bool? isTesting,
    String? error,
    String? subscribeUrl,
  }) {
    return NodesState(
      nodes: nodes ?? this.nodes,
      latencies: latencies ?? this.latencies,
      isLoading: isLoading ?? this.isLoading,
      isTesting: isTesting ?? this.isTesting,
      error: error,
      subscribeUrl: subscribeUrl ?? this.subscribeUrl,
    );
  }

  /// 获取按分组的节点
  Map<String, List<ProxyNode>> get nodesByGroup {
    final grouped = <String, List<ProxyNode>>{};
    for (final node in nodes) {
      final group = node.group ?? '默认';
      grouped.putIfAbsent(group, () => []).add(node);
    }
    return grouped;
  }

  /// 获取按协议的节点
  Map<ProtocolType, List<ProxyNode>> get nodesByProtocol {
    final grouped = <ProtocolType, List<ProxyNode>>{};
    for (final node in nodes) {
      grouped.putIfAbsent(node.protocol, () => []).add(node);
    }
    return grouped;
  }
}

class NodesNotifier extends StateNotifier<NodesState> {
  NodesNotifier() : super(const NodesState()) {
    _loadCachedNodes();
  }

  final SubscriptionParser _parser = SubscriptionParser();

  Future<void> _loadCachedNodes() async {
    final cached = StorageService.instance.getObject(
      AppConstants.serverListKey,
    );
    if (cached != null && cached is List) {
      final nodes = cached
          .map((e) => ProxyNode.fromJson(e as Map<String, dynamic>))
          .toList();
      state = state.copyWith(nodes: nodes);
    }
  }

  /// 从URL刷新节点列表
  Future<void> refreshNodesFromUrl(
    String subscribeUrl, {
    String? subType,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final nodes = await _parser.parseFromUrl(subscribeUrl, subType: subType);

      if (nodes.isEmpty) {
        throw Exception(ErrorMessages.noNodes);
      }

      // 保存到缓存
      await StorageService.instance.putObject(
        AppConstants.serverListKey,
        nodes.map((e) => e.toJson()).toList(),
      );

      state = state.copyWith(
        nodes: nodes,
        isLoading: false,
        subscribeUrl: subscribeUrl,
      );

      VortexLogger.i('Loaded ${nodes.length} nodes from subscription');
    } catch (e) {
      VortexLogger.e('Failed to refresh nodes', e);
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  /// 从本地内容解析节点
  Future<void> parseNodesFromContent(String content) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final nodes = _parser.parse(content);

      if (nodes.isEmpty) {
        throw Exception(ErrorMessages.noNodes);
      }

      // 保存到缓存
      await StorageService.instance.putObject(
        AppConstants.serverListKey,
        nodes.map((e) => e.toJson()).toList(),
      );

      state = state.copyWith(nodes: nodes, isLoading: false);

      VortexLogger.i('Parsed ${nodes.length} nodes from content');
    } catch (e) {
      VortexLogger.e('Failed to parse nodes', e);
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  /// 测试所有节点延迟（真实全链路延迟）
  ///
  /// 通过 Mihomo API 测试完整链路延迟：
  /// 用户设备 → 中转服务器(可选) → 落地服务器 → 测试URL
  ///
  /// 如果 VPN 未连接，会临时启动核心进行测试
  Future<void> testAllLatencies() async {
    if (state.isTesting) return; // 防止重复测试
    if (state.nodes.isEmpty) {
      VortexLogger.w('No nodes to test');
      return;
    }

    state = state.copyWith(isTesting: true);

    try {
      // 清空旧的延迟数据
      state = state.copyWith(latencies: {});

      // 确保 VpnService 有节点列表
      VpnService.instance.setNodes(state.nodes);

      // 使用 VpnService 的真实延迟测试
      // 如果核心未运行，会自动临时启动
      // 添加整体超时保护，避免无限等待
      await VpnService.instance
          .testAllNodesDelay(
            timeout: 10000,
            onProgress: (completed, total, nodeId, delay) {
              // 实时更新单个节点的延迟
              final newLatencies = Map<String, int?>.from(state.latencies);
              newLatencies[nodeId] = delay > 0 ? delay : null;
              state = state.copyWith(latencies: newLatencies);

              VortexLogger.d(
                'Delay test progress: $completed/$total, $nodeId: ${delay}ms',
              );
            },
          )
          .timeout(
            const Duration(minutes: 3),
            onTimeout: () {
              VortexLogger.w('Batch delay test overall timeout');
              return {};
            },
          );

      VortexLogger.i(
        'All latency tests completed: ${state.latencies.length} nodes',
      );
    } catch (e) {
      VortexLogger.e('Failed to test latencies', e);
    } finally {
      // 确保无论如何都会重置测试状态
      state = state.copyWith(isTesting: false);
      // 异步停止临时核心，不阻塞 UI
      _stopTempCoreAsync();
    }
  }

  /// 异步停止临时核心，不阻塞调用者
  void _stopTempCoreAsync() {
    Future(() async {
      try {
        await VpnService.instance.stopTempCoreIfRunning();
      } catch (e) {
        VortexLogger.e('Failed to stop temp core async', e);
      }
    });
  }

  /// 停止测速
  void stopTesting() {
    state = state.copyWith(isTesting: false);
    // 异步停止临时核心
    _stopTempCoreAsync();
  }

  /// 测试单个节点延迟（真实全链路延迟）
  Future<void> testLatency(ProxyNode node) async {
    // 确保 VpnService 有节点列表
    if (VpnService.instance.nodes.isEmpty) {
      VpnService.instance.setNodes(state.nodes);
    }

    final delay = await VpnService.instance.testNodeDelay(node, timeout: 10000);
    final newLatencies = Map<String, int?>.from(state.latencies);
    newLatencies[node.id] = delay > 0 ? delay : null;
    state = state.copyWith(latencies: newLatencies);

    // 停止临时核心（如果有）
    await VpnService.instance.stopTempCoreIfRunning();
  }

  /// 获取节点延迟
  int? getLatency(String nodeId) => state.latencies[nodeId];

  /// 按延迟排序节点
  List<ProxyNode> get sortedByLatency {
    final sorted = List<ProxyNode>.from(state.nodes);
    sorted.sort((a, b) {
      final latencyA = state.latencies[a.id];
      final latencyB = state.latencies[b.id];
      if (latencyA == null && latencyB == null) return 0;
      if (latencyA == null) return 1;
      if (latencyB == null) return -1;
      return latencyA.compareTo(latencyB);
    });
    return sorted;
  }

  /// 筛选节点
  List<ProxyNode> filterNodes({
    String? keyword,
    ProtocolType? protocol,
    String? group,
    List<NodeTag>? tags,
  }) {
    return state.nodes.where((node) {
      if (keyword != null && keyword.isNotEmpty) {
        final lowerKeyword = keyword.toLowerCase();
        if (!node.name.toLowerCase().contains(lowerKeyword) &&
            !node.server.toLowerCase().contains(lowerKeyword)) {
          return false;
        }
      }
      if (protocol != null && node.protocol != protocol) {
        return false;
      }
      if (group != null && node.group != group) {
        return false;
      }
      if (tags != null && tags.isNotEmpty) {
        for (final tag in tags) {
          if (!node.tags.contains(tag)) {
            return false;
          }
        }
      }
      return true;
    }).toList();
  }

  /// 清除节点缓存
  Future<void> clearCache() async {
    await StorageService.instance.deleteObject(AppConstants.serverListKey);
    state = const NodesState();
  }
}

final nodesProvider = StateNotifierProvider<NodesNotifier, NodesState>((ref) {
  return NodesNotifier();
});
