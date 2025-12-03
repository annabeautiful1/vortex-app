import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/models/proxy_node.dart';
import '../../../core/proxy/proxy_core.dart';
import '../../../core/utils/logger.dart';

part 'connection_provider.g.dart';

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
}

class ConnectionState {
  final ConnectionStatus status;
  final ProxyNode? connectedNode;
  final bool tunEnabled;
  final int? latency;
  final String? error;

  const ConnectionState({
    this.status = ConnectionStatus.disconnected,
    this.connectedNode,
    this.tunEnabled = false,
    this.latency,
    this.error,
  });

  ConnectionState copyWith({
    ConnectionStatus? status,
    ProxyNode? connectedNode,
    bool? tunEnabled,
    int? latency,
    String? error,
  }) {
    return ConnectionState(
      status: status ?? this.status,
      connectedNode: connectedNode ?? this.connectedNode,
      tunEnabled: tunEnabled ?? this.tunEnabled,
      latency: latency ?? this.latency,
      error: error,
    );
  }
}

@riverpod
class Connection extends _$Connection {
  @override
  ConnectionState build() {
    return const ConnectionState();
  }

  Future<void> connect({ProxyNode? node}) async {
    state = state.copyWith(
      status: ConnectionStatus.connecting,
      error: null,
    );

    try {
      final targetNode = node ?? await _getDefaultNode();
      if (targetNode == null) {
        throw Exception('没有可用节点');
      }

      await ProxyCore.instance.connect(targetNode);

      // Test latency after connection
      final latency = await ProxyCore.instance.testLatency(targetNode);

      state = state.copyWith(
        status: ConnectionStatus.connected,
        connectedNode: targetNode,
        latency: latency,
      );

      VortexLogger.i('Connected to ${targetNode.name}');
    } catch (e) {
      VortexLogger.e('Connection failed', e);
      state = state.copyWith(
        status: ConnectionStatus.disconnected,
        error: e.toString(),
      );
    }
  }

  Future<void> disconnect() async {
    state = state.copyWith(status: ConnectionStatus.disconnecting);

    try {
      await ProxyCore.instance.disconnect();

      state = const ConnectionState(
        status: ConnectionStatus.disconnected,
      );

      VortexLogger.i('Disconnected');
    } catch (e) {
      VortexLogger.e('Disconnect failed', e);
      state = state.copyWith(
        status: ConnectionStatus.connected,
        error: e.toString(),
      );
    }
  }

  Future<void> switchNode(ProxyNode node) async {
    if (state.status == ConnectionStatus.connected) {
      await disconnect();
    }
    await connect(node: node);
  }

  void setTunMode(bool enabled) {
    state = state.copyWith(tunEnabled: enabled);
    ProxyCore.instance.setTunMode(enabled);
    VortexLogger.i('TUN mode ${enabled ? 'enabled' : 'disabled'}');
  }

  Future<void> refreshLatency() async {
    if (state.connectedNode == null) return;

    final latency = await ProxyCore.instance.testLatency(state.connectedNode!);
    state = state.copyWith(latency: latency);
  }

  Future<ProxyNode?> _getDefaultNode() async {
    // Get the first available node or last selected node
    // This should be implemented based on stored preferences
    return null;
  }
}

final connectionProvider = ConnectionProvider();
