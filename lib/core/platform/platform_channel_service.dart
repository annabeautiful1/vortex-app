import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import '../utils/logger.dart';

/// 平台通道服务 - 用于与原生代码通信
class PlatformChannelService {
  static const MethodChannel _channel = MethodChannel('com.vortex.app/core');
  static const EventChannel _eventChannel = EventChannel(
    'com.vortex.app/events',
  );

  static final PlatformChannelService _instance =
      PlatformChannelService._internal();
  static PlatformChannelService get instance => _instance;

  PlatformChannelService._internal();

  StreamSubscription? _eventSubscription;

  /// 初始化平台通道
  Future<void> init() async {
    // 监听来自原生端的事件
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      _handlePlatformEvent,
      onError: (error) {
        VortexLogger.e('Platform event error', error);
      },
    );

    VortexLogger.i('Platform channel initialized');
  }

  void _handlePlatformEvent(dynamic event) {
    if (event is Map) {
      final type = event['type'] as String?;
      final data = event['data'];

      switch (type) {
        case 'vpn_state_changed':
          _onVpnStateChanged?.call(data);
          break;
        case 'traffic_update':
          _onTrafficUpdate?.call(data);
          break;
        case 'log':
          VortexLogger.i('[Native] $data');
          break;
        default:
          VortexLogger.w('Unknown platform event: $type');
      }
    }
  }

  // 事件回调
  Function(dynamic)? _onVpnStateChanged;
  Function(dynamic)? _onTrafficUpdate;

  void setVpnStateCallback(Function(dynamic) callback) {
    _onVpnStateChanged = callback;
  }

  void setTrafficCallback(Function(dynamic) callback) {
    _onTrafficUpdate = callback;
  }

  /// 启动 Mihomo 核心
  Future<bool> startCore(String configPath) async {
    try {
      final result = await _channel.invokeMethod('startCore', {
        'configPath': configPath,
      });
      return result == true;
    } on PlatformException catch (e) {
      VortexLogger.e('Failed to start core: ${e.message}');
      return false;
    }
  }

  /// 停止 Mihomo 核心
  Future<bool> stopCore() async {
    try {
      final result = await _channel.invokeMethod('stopCore');
      return result == true;
    } on PlatformException catch (e) {
      VortexLogger.e('Failed to stop core: ${e.message}');
      return false;
    }
  }

  /// 启动 VPN 服务
  Future<bool> startVpn() async {
    try {
      final result = await _channel.invokeMethod('startVpn');
      return result == true;
    } on PlatformException catch (e) {
      VortexLogger.e('Failed to start VPN: ${e.message}');
      return false;
    }
  }

  /// 停止 VPN 服务
  Future<bool> stopVpn() async {
    try {
      final result = await _channel.invokeMethod('stopVpn');
      return result == true;
    } on PlatformException catch (e) {
      VortexLogger.e('Failed to stop VPN: ${e.message}');
      return false;
    }
  }

  /// 设置系统代理
  Future<bool> setSystemProxy(bool enable, {int port = 7890}) async {
    try {
      final result = await _channel.invokeMethod('setSystemProxy', {
        'enable': enable,
        'port': port,
      });
      return result == true;
    } on PlatformException catch (e) {
      VortexLogger.e('Failed to set system proxy: ${e.message}');
      return false;
    }
  }

  /// 获取 VPN 状态
  Future<String> getVpnState() async {
    try {
      final result = await _channel.invokeMethod('getVpnState');
      return result as String? ?? 'unknown';
    } on PlatformException catch (e) {
      VortexLogger.e('Failed to get VPN state: ${e.message}');
      return 'error';
    }
  }

  /// 获取核心版本
  Future<String?> getCoreVersion() async {
    try {
      final result = await _channel.invokeMethod('getCoreVersion');
      return result as String?;
    } on PlatformException catch (e) {
      VortexLogger.e('Failed to get core version: ${e.message}');
      return null;
    }
  }

  /// 复制日志到剪贴板 (Android)
  Future<bool> copyLogsToClipboard() async {
    try {
      final result = await _channel.invokeMethod('copyLogsToClipboard');
      return result == true;
    } on PlatformException catch (e) {
      VortexLogger.e('Failed to copy logs: ${e.message}');
      return false;
    }
  }

  /// 请求 VPN 权限 (Android)
  Future<bool> requestVpnPermission() async {
    if (!Platform.isAndroid) return true;

    try {
      final result = await _channel.invokeMethod('requestVpnPermission');
      return result == true;
    } on PlatformException catch (e) {
      VortexLogger.e('Failed to request VPN permission: ${e.message}');
      return false;
    }
  }

  /// 检查电池优化 (Android)
  Future<bool> checkBatteryOptimization() async {
    if (!Platform.isAndroid) return true;

    try {
      final result = await _channel.invokeMethod('checkBatteryOptimization');
      return result == true;
    } on PlatformException catch (e) {
      VortexLogger.e('Failed to check battery optimization: ${e.message}');
      return false;
    }
  }

  /// 安装系统扩展 (macOS)
  Future<bool> installSystemExtension() async {
    if (!Platform.isMacOS) return true;

    try {
      final result = await _channel.invokeMethod('installSystemExtension');
      return result == true;
    } on PlatformException catch (e) {
      VortexLogger.e('Failed to install system extension: ${e.message}');
      return false;
    }
  }

  /// 获取设备信息
  Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      final result = await _channel.invokeMethod('getDeviceInfo');
      return Map<String, dynamic>.from(result ?? {});
    } on PlatformException catch (e) {
      VortexLogger.e('Failed to get device info: ${e.message}');
      return {};
    }
  }

  /// 释放资源
  void dispose() {
    _eventSubscription?.cancel();
  }
}
