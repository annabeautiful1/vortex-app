import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/models/proxy_node.dart';
import '../../../core/proxy/proxy_core.dart';
import '../../../core/api/api_manager.dart';
import '../../../shared/services/storage_service.dart';
import '../../../shared/constants/app_constants.dart';
import '../../../core/utils/logger.dart';

part 'nodes_provider.g.dart';

class NodesState {
  final List<ProxyNode> nodes;
  final Map<String, int?> latencies;
  final bool isLoading;
  final String? error;

  const NodesState({
    this.nodes = const [],
    this.latencies = const {},
    this.isLoading = false,
    this.error,
  });

  NodesState copyWith({
    List<ProxyNode>? nodes,
    Map<String, int?>? latencies,
    bool? isLoading,
    String? error,
  }) {
    return NodesState(
      nodes: nodes ?? this.nodes,
      latencies: latencies ?? this.latencies,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

@riverpod
class Nodes extends _$Nodes {
  @override
  NodesState build() {
    _loadCachedNodes();
    return const NodesState();
  }

  Future<void> _loadCachedNodes() async {
    final cached = StorageService.instance.getObject(AppConstants.serverListKey);
    if (cached != null && cached is List) {
      final nodes = cached
          .map((e) => ProxyNode.fromJson(e as Map<String, dynamic>))
          .toList();
      state = state.copyWith(nodes: nodes);
    }
  }

  Future<void> refreshNodes() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final endpoint = ApiManager.instance.activeEndpoint;
      if (endpoint == null) {
        throw Exception(ErrorMessages.noValidApi);
      }

      final token = await StorageService.instance.getSecure(AppConstants.tokenKey);
      if (token == null) {
        throw Exception('未登录');
      }

      // Get subscription URL
      final userResponse = await ApiManager.instance.request(
        endpoint.panelType == AppConstants.panelV2Board
            ? '/api/v1/user/getSubscribe'
            : '/api/v1/user/subscription',
        token: token,
      );

      String subscribeUrl;
      if (endpoint.panelType == AppConstants.panelV2Board) {
        subscribeUrl = userResponse.data['data']['subscribe_url'];

        // Add subscription type parameter
        final subType = endpoint.subscriptionType ?? 'clashmeta';
        subscribeUrl = '$subscribeUrl&flag=$subType';
      } else {
        subscribeUrl = userResponse.data['data']['url'];

        // Add SSPanel subscription type
        final subType = endpoint.subscriptionType ?? '1';
        subscribeUrl = '$subscribeUrl?clash=$subType';
      }

      VortexLogger.subscription('fetch', subscribeUrl);

      // Fetch subscription content
      final subResponse = await ApiManager.instance.request(
        subscribeUrl,
        method: 'GET',
      );

      // Parse nodes from subscription
      final nodes = _parseSubscription(subResponse.data, endpoint.panelType);

      // Cache nodes
      await StorageService.instance.putObject(
        AppConstants.serverListKey,
        nodes.map((e) => e.toJson()).toList(),
      );

      state = state.copyWith(
        nodes: nodes,
        isLoading: false,
      );

      VortexLogger.i('Loaded ${nodes.length} nodes');
    } catch (e) {
      VortexLogger.e('Failed to refresh nodes', e);
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  List<ProxyNode> _parseSubscription(dynamic data, String panelType) {
    final nodes = <ProxyNode>[];

    // Parse Clash format subscription
    if (data is Map<String, dynamic>) {
      final proxies = data['proxies'] as List?;
      if (proxies != null) {
        for (final proxy in proxies) {
          final node = _parseProxy(proxy as Map<String, dynamic>);
          if (node != null) {
            nodes.add(node);
          }
        }
      }
    }

    return nodes;
  }

  ProxyNode? _parseProxy(Map<String, dynamic> proxy) {
    try {
      final type = proxy['type'] as String?;
      if (type == null) return null;

      final protocol = _getProtocolType(type);
      if (protocol == null) return null;

      // Extract tags from name
      final name = proxy['name'] as String? ?? '';
      final tags = _extractTags(name);
      final multiplier = _extractMultiplier(name);

      return ProxyNode(
        id: '${proxy['server']}_${proxy['port']}',
        name: name,
        server: proxy['server'] as String? ?? '',
        port: proxy['port'] as int? ?? 0,
        protocol: protocol,
        settings: _extractSettings(proxy, protocol),
        group: proxy['group'] as String?,
        tags: tags,
        multiplier: multiplier,
      );
    } catch (e) {
      VortexLogger.w('Failed to parse proxy: $e');
      return null;
    }
  }

  ProtocolType? _getProtocolType(String type) {
    switch (type.toLowerCase()) {
      case 'ss':
      case 'shadowsocks':
        return ProtocolType.shadowsocks;
      case 'ssr':
      case 'shadowsocksr':
        return ProtocolType.shadowsocksR;
      case 'vmess':
        return ProtocolType.vmess;
      case 'vless':
        return ProtocolType.vless;
      case 'trojan':
        return ProtocolType.trojan;
      case 'hysteria':
        return ProtocolType.hysteria;
      case 'hysteria2':
        return ProtocolType.hysteria2;
      case 'tuic':
        return ProtocolType.tuic;
      case 'wireguard':
      case 'wg':
        return ProtocolType.wireguard;
      case 'anytls':
        return ProtocolType.anytls;
      default:
        return null;
    }
  }

  Map<String, dynamic> _extractSettings(Map<String, dynamic> proxy, ProtocolType protocol) {
    final settings = Map<String, dynamic>.from(proxy);
    // Remove common fields
    settings.remove('name');
    settings.remove('server');
    settings.remove('port');
    settings.remove('type');
    settings.remove('group');
    return settings;
  }

  List<NodeTag> _extractTags(String name) {
    final tags = <NodeTag>[];
    final lowerName = name.toLowerCase();

    if (lowerName.contains('解锁') || lowerName.contains('unlock')) {
      tags.add(NodeTag.unlock);
    }
    if (lowerName.contains('游戏') || lowerName.contains('game')) {
      tags.add(NodeTag.gaming);
    }
    if (lowerName.contains('流媒体') || lowerName.contains('stream')) {
      tags.add(NodeTag.streaming);
    }
    if (lowerName.contains('chatgpt') || lowerName.contains('gpt') || lowerName.contains('openai')) {
      tags.add(NodeTag.chatgpt);
    }
    if (lowerName.contains('netflix') || lowerName.contains('nf')) {
      tags.add(NodeTag.netflix);
    }
    if (lowerName.contains('disney') || lowerName.contains('d+')) {
      tags.add(NodeTag.disney);
    }

    return tags;
  }

  double _extractMultiplier(String name) {
    // Match patterns like "0.5x", "2x", "1.5倍"
    final regex = RegExp(r'(\d+\.?\d*)\s*[xX倍]');
    final match = regex.firstMatch(name);
    if (match != null) {
      return double.tryParse(match.group(1)!) ?? 1.0;
    }
    return 1.0;
  }

  Future<void> testAllLatencies() async {
    state = state.copyWith(isLoading: true);

    final latencies = await ProxyCore.instance.testAllLatencies(state.nodes);

    state = state.copyWith(
      latencies: latencies,
      isLoading: false,
    );
  }

  Future<void> testLatency(ProxyNode node) async {
    final latency = await ProxyCore.instance.testLatency(node);
    final newLatencies = Map<String, int?>.from(state.latencies);
    newLatencies[node.id] = latency;
    state = state.copyWith(latencies: newLatencies);
  }
}

final nodesProvider = NodesProvider();
