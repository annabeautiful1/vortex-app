import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/proxy_node.dart';
import '../../../core/vpn/vpn_service.dart';
import '../../../core/platform/platform_channel_service.dart';
import '../../../core/utils/logger.dart';

/// 连接状态枚举
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

/// VPN 连接状态
class VpnConnectionState {
  final ConnectionStatus status;
  final ProxyNode? connectedNode;
  final bool tunEnabled;
  final int? latency;
  final String? error;
  final TrafficStats trafficStats;

  const VpnConnectionState({
    this.status = ConnectionStatus.disconnected,
    this.connectedNode,
    this.tunEnabled = false,
    this.latency,
    this.error,
    this.trafficStats = const _EmptyTrafficStats(),
  });

  VpnConnectionState copyWith({
    ConnectionStatus? status,
    ProxyNode? connectedNode,
    bool? tunEnabled,
    int? latency,
    String? error,
    TrafficStats? trafficStats,
    bool clearNode = false,
    bool clearError = false,
  }) {
    return VpnConnectionState(
      status: status ?? this.status,
      connectedNode: clearNode ? null : (connectedNode ?? this.connectedNode),
      tunEnabled: tunEnabled ?? this.tunEnabled,
      latency: latency ?? this.latency,
      error: clearError ? null : (error ?? this.error),
      trafficStats: trafficStats ?? this.trafficStats,
    );
  }

  bool get isConnected => status == ConnectionStatus.connected;
  bool get isConnecting => status == ConnectionStatus.connecting;
  bool get isDisconnecting => status == ConnectionStatus.disconnecting;
  bool get isDisconnected => status == ConnectionStatus.disconnected;
  bool get hasError => error != null;
}

/// 空流量统计（用于默认值）
class _EmptyTrafficStats implements TrafficStats {
  const _EmptyTrafficStats();

  @override
  int get upload => 0;
  @override
  int get download => 0;
  @override
  int get uploadSpeed => 0;
  @override
  int get downloadSpeed => 0;
  @override
  String get formattedUpload => '0 B';
  @override
  String get formattedDownload => '0 B';
  @override
  String get formattedUploadSpeed => '0 B/s';
  @override
  String get formattedDownloadSpeed => '0 B/s';
  @override
  String formatBytes(int bytes) => '0 B';
}

/// 连接状态管理器
class ConnectionNotifier extends StateNotifier<VpnConnectionState> {
  final VpnService _vpnService;
  StreamSubscription? _stateSubscription;
  StreamSubscription? _trafficSubscription;

  ConnectionNotifier(this._vpnService) : super(const VpnConnectionState()) {
    _init();
  }

  Future<void> _init() async {
    try {
      await _vpnService.init();

      // 监听 VPN 状态变化
      _stateSubscription = _vpnService.stateStream.listen(_onStateChanged);

      // 监听流量统计
      _trafficSubscription = _vpnService.trafficStream.listen(_onTrafficUpdate);

      // 同步初始状态
      _syncState();
    } catch (e) {
      VortexLogger.e('Failed to initialize connection notifier', e);
    }
  }

  void _syncState() {
    final vpnState = _vpnService.currentState;
    final status = _mapVpnState(vpnState);
    state = state.copyWith(
      status: status,
      connectedNode: _vpnService.currentNode,
      tunEnabled: _vpnService.tunEnabled,
      trafficStats: _vpnService.trafficStats,
    );
  }

  ConnectionStatus _mapVpnState(VpnState vpnState) {
    switch (vpnState) {
      case VpnState.connected:
        return ConnectionStatus.connected;
      case VpnState.connecting:
        return ConnectionStatus.connecting;
      case VpnState.disconnecting:
        return ConnectionStatus.disconnecting;
      case VpnState.error:
        return ConnectionStatus.error;
      case VpnState.disconnected:
        return ConnectionStatus.disconnected;
    }
  }

  void _onStateChanged(VpnState vpnState) {
    final status = _mapVpnState(vpnState);
    state = state.copyWith(
      status: status,
      connectedNode: _vpnService.currentNode,
      clearError: status == ConnectionStatus.connected,
    );
    VortexLogger.i('Connection status changed: $status');
  }

  void _onTrafficUpdate(TrafficStats stats) {
    state = state.copyWith(trafficStats: stats);
  }

  /// 连接
  Future<void> connect({ProxyNode? node}) async {
    if (state.isConnecting || state.isConnected) return;

    state = state.copyWith(
      status: ConnectionStatus.connecting,
      clearError: true,
    );

    try {
      final success = await _vpnService.connect(node: node);

      if (success) {
        // 测试延迟
        if (_vpnService.currentNode != null) {
          final latency = await _vpnService.testNodeDelay(
            _vpnService.currentNode!,
          );
          state = state.copyWith(
            status: ConnectionStatus.connected,
            connectedNode: _vpnService.currentNode,
            latency: latency > 0 ? latency : null,
          );
        }
        VortexLogger.i('Connected to ${_vpnService.currentNode?.name}');
      } else {
        state = state.copyWith(
          status: ConnectionStatus.disconnected,
          error: '连接失败，请重试',
        );
      }
    } catch (e) {
      VortexLogger.e('Connection failed', e);
      state = state.copyWith(
        status: ConnectionStatus.error,
        error: e.toString(),
      );
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    if (state.isDisconnecting || state.isDisconnected) return;

    state = state.copyWith(status: ConnectionStatus.disconnecting);

    try {
      final success = await _vpnService.disconnect();

      if (success) {
        state = state.copyWith(
          status: ConnectionStatus.disconnected,
          clearNode: true,
          trafficStats: const _EmptyTrafficStats(),
        );
        VortexLogger.i('Disconnected');
      } else {
        state = state.copyWith(
          status: ConnectionStatus.connected,
          error: '断开连接失败',
        );
      }
    } catch (e) {
      VortexLogger.e('Disconnect failed', e);
      state = state.copyWith(
        status: ConnectionStatus.connected,
        error: e.toString(),
      );
    }
  }

  /// 切换节点
  Future<void> switchNode(ProxyNode node) async {
    if (state.connectedNode?.id == node.id) return;

    state = state.copyWith(status: ConnectionStatus.connecting);

    try {
      final success = await _vpnService.switchNode(node);

      if (success) {
        final latency = await _vpnService.testNodeDelay(node);
        state = state.copyWith(
          status: ConnectionStatus.connected,
          connectedNode: node,
          latency: latency > 0 ? latency : null,
        );
        VortexLogger.i('Switched to ${node.name}');
      } else {
        state = state.copyWith(status: ConnectionStatus.error, error: '切换节点失败');
      }
    } catch (e) {
      VortexLogger.e('Switch node failed', e);
      state = state.copyWith(
        status: ConnectionStatus.error,
        error: e.toString(),
      );
    }
  }

  /// 切换连接状态（一键连接/断开）
  Future<void> toggle({ProxyNode? node}) async {
    if (state.isConnected || state.isConnecting) {
      await disconnect();
    } else {
      await connect(node: node);
    }
  }

  /// 设置 TUN 模式
  Future<void> setTunMode(bool enabled) async {
    await _vpnService.setTunMode(enabled);
    state = state.copyWith(tunEnabled: enabled);
    VortexLogger.i('TUN mode ${enabled ? 'enabled' : 'disabled'}');
  }

  /// 刷新延迟
  Future<void> refreshLatency() async {
    if (state.connectedNode == null) return;

    final latency = await _vpnService.testNodeDelay(state.connectedNode!);
    state = state.copyWith(latency: latency > 0 ? latency : null);
  }

  /// 设置节点列表
  void setNodes(List<ProxyNode> nodes) {
    _vpnService.setNodes(nodes);
  }

  /// 清除错误
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _trafficSubscription?.cancel();
    super.dispose();
  }
}

/// Connection Provider
final connectionProvider =
    StateNotifierProvider<ConnectionNotifier, VpnConnectionState>((ref) {
      return ConnectionNotifier(VpnService.instance);
    });

/// 流量统计 Provider（独立的，用于高频更新）
final trafficStatsProvider = StreamProvider<TrafficStats>((ref) {
  return VpnService.instance.trafficStream;
});

/// VPN 状态 Provider
final vpnStateProvider = StreamProvider<VpnState>((ref) {
  return VpnService.instance.stateStream;
});
