import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/proxy_node.dart';
import '../../../core/proxy/proxy_core.dart';
import '../../../core/utils/logger.dart';

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
}

class VpnConnectionState {
  final ConnectionStatus status;
  final ProxyNode? connectedNode;
  final bool tunEnabled;
  final int? latency;
  final String? error;

  const VpnConnectionState({
    this.status = ConnectionStatus.disconnected,
    this.connectedNode,
    this.tunEnabled = false,
    this.latency,
    this.error,
  });

  VpnConnectionState copyWith({
    ConnectionStatus? status,
    ProxyNode? connectedNode,
    bool? tunEnabled,
    int? latency,
    String? error,
  }) {
    return VpnConnectionState(
      status: status ?? this.status,
      connectedNode: connectedNode ?? this.connectedNode,
      tunEnabled: tunEnabled ?? this.tunEnabled,
      latency: latency ?? this.latency,
      error: error,
    );
  }
}

class ConnectionNotifier extends StateNotifier<VpnConnectionState> {
  ConnectionNotifier() : super(const VpnConnectionState());

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

      state = const VpnConnectionState(
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
    return null;
  }
}

final connectionProvider = StateNotifierProvider<ConnectionNotifier, VpnConnectionState>((ref) {
  return ConnectionNotifier();
});
