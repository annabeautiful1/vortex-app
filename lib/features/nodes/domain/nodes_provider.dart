import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/proxy_node.dart';
import '../../../core/proxy/proxy_core.dart';
import '../../../core/subscription/subscription_parser.dart';
import '../../../shared/services/storage_service.dart';
import '../../../shared/constants/app_constants.dart';
import '../../../core/utils/logger.dart';

class NodesState {
  final List<ProxyNode> nodes;
  final Map<String, int?> latencies;
  final bool isLoading;
  final String? error;
  final String? subscribeUrl;

  const NodesState({
    this.nodes = const [],
    this.latencies = const {},
    this.isLoading = false,
    this.error,
    this.subscribeUrl,
  });

  NodesState copyWith({
    List<ProxyNode>? nodes,
    Map<String, int?>? latencies,
    bool? isLoading,
    String? error,
    String? subscribeUrl,
  }) {
    return NodesState(
      nodes: nodes ?? this.nodes,
      latencies: latencies ?? this.latencies,
      isLoading: isLoading ?? this.isLoading,
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

  /// 测试所有节点延迟
  Future<void> testAllLatencies() async {
    state = state.copyWith(isLoading: true);

    final latencies = await ProxyCore.instance.testAllLatencies(state.nodes);

    state = state.copyWith(latencies: latencies, isLoading: false);
  }

  /// 测试单个节点延迟
  Future<void> testLatency(ProxyNode node) async {
    final latency = await ProxyCore.instance.testLatency(node);
    final newLatencies = Map<String, int?>.from(state.latencies);
    newLatencies[node.id] = latency;
    state = state.copyWith(latencies: newLatencies);
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
