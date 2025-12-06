import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/logger.dart';

/// VPN 连接状态
enum VpnState { disconnected, connecting, connected, disconnecting, error }

/// 流量统计数据
class TrafficStats {
  final int upload;
  final int download;
  final int uploadSpeed;
  final int downloadSpeed;

  TrafficStats({
    this.upload = 0,
    this.download = 0,
    this.uploadSpeed = 0,
    this.downloadSpeed = 0,
  });

  factory TrafficStats.fromMap(Map<String, dynamic> map) {
    return TrafficStats(
      upload: map['upload'] as int? ?? 0,
      download: map['download'] as int? ?? 0,
      uploadSpeed: map['uploadSpeed'] as int? ?? 0,
      downloadSpeed: map['downloadSpeed'] as int? ?? 0,
    );
  }

  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  String get formattedUpload => formatBytes(upload);
  String get formattedDownload => formatBytes(download);
  String get formattedUploadSpeed => '${formatBytes(uploadSpeed)}/s';
  String get formattedDownloadSpeed => '${formatBytes(downloadSpeed)}/s';
}

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
  bool _isInitialized = false;
  VpnState _currentState = VpnState.disconnected;
  TrafficStats _trafficStats = TrafficStats();

  // 状态流控制器
  final _stateController = StreamController<VpnState>.broadcast();
  final _trafficController = StreamController<TrafficStats>.broadcast();
  final _logController = StreamController<String>.broadcast();

  /// 状态变化流
  Stream<VpnState> get stateStream => _stateController.stream;

  /// 流量统计流
  Stream<TrafficStats> get trafficStream => _trafficController.stream;

  /// 日志流
  Stream<String> get logStream => _logController.stream;

  /// 当前状态
  VpnState get currentState => _currentState;

  /// 当前流量统计
  TrafficStats get trafficStats => _trafficStats;

  /// 是否已连接
  bool get isConnected => _currentState == VpnState.connected;

  /// 初始化平台通道
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      // 监听来自原生端的事件
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
        _handlePlatformEvent,
        onError: (error) {
          VortexLogger.e('Platform event error', error);
        },
      );

      // 获取初始状态
      await _syncState();

      _isInitialized = true;
      VortexLogger.i('Platform channel initialized');
    } catch (e) {
      VortexLogger.e('Failed to initialize platform channel', e);
    }
  }

  /// 同步状态
  Future<void> _syncState() async {
    final stateStr = await getVpnState();
    _currentState = _parseVpnState(stateStr);
    _stateController.add(_currentState);
  }

  VpnState _parseVpnState(String state) {
    switch (state.toLowerCase()) {
      case 'connected':
        return VpnState.connected;
      case 'connecting':
        return VpnState.connecting;
      case 'disconnecting':
        return VpnState.disconnecting;
      case 'error':
        return VpnState.error;
      default:
        return VpnState.disconnected;
    }
  }

  void _handlePlatformEvent(dynamic event) {
    if (event is Map) {
      final type = event['type'] as String?;
      final data = event['data'];

      switch (type) {
        case 'vpn_state_changed':
          final newState = _parseVpnState(data.toString());
          _currentState = newState;
          _stateController.add(newState);
          _onVpnStateChanged?.call(data);
          VortexLogger.i('VPN state changed: $newState');
          break;
        case 'traffic_update':
          if (data is Map) {
            _trafficStats = TrafficStats.fromMap(
              Map<String, dynamic>.from(data),
            );
            _trafficController.add(_trafficStats);
            _onTrafficUpdate?.call(data);
          }
          break;
        case 'log':
          final logMessage = data.toString();
          _logController.add(logMessage);
          VortexLogger.d('[Core] $logMessage');
          break;
        case 'error':
          VortexLogger.e('[Core Error] $data');
          _currentState = VpnState.error;
          _stateController.add(_currentState);
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

  /// 获取配置目录
  Future<String> getConfigDirectory() async {
    final appDir = await getApplicationSupportDirectory();
    final configDir = Directory('${appDir.path}/mihomo');
    if (!await configDir.exists()) {
      await configDir.create(recursive: true);
    }
    return configDir.path;
  }

  /// 获取核心文件路径
  Future<String> getCorePath() async {
    final configDir = await getConfigDirectory();
    if (Platform.isWindows) {
      return '$configDir/mihomo.exe';
    } else if (Platform.isMacOS || Platform.isLinux) {
      return '$configDir/mihomo';
    }
    // Android/iOS 使用嵌入的核心
    return '';
  }

  /// 启动 Mihomo 核心
  Future<bool> startCore(String configPath) async {
    try {
      _currentState = VpnState.connecting;
      _stateController.add(_currentState);

      final result = await _channel.invokeMethod('startCore', {
        'configPath': configPath,
        'workDir': await getConfigDirectory(),
      });

      if (result == true) {
        VortexLogger.i('Core started with config: $configPath');
        return true;
      }
      return false;
    } on PlatformException catch (e) {
      VortexLogger.e('Failed to start core: ${e.message}');
      _currentState = VpnState.error;
      _stateController.add(_currentState);
      return false;
    }
  }

  /// 停止 Mihomo 核心
  Future<bool> stopCore() async {
    try {
      _currentState = VpnState.disconnecting;
      _stateController.add(_currentState);

      // 添加超时保护，防止原生代码卡住导致 UI 卡死
      final result = await _channel
          .invokeMethod('stopCore')
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              VortexLogger.w('stopCore native call timed out');
              return true; // 假设成功，让 UI 继续
            },
          );

      if (result == true) {
        _currentState = VpnState.disconnected;
        _stateController.add(_currentState);
        _trafficStats = TrafficStats();
        _trafficController.add(_trafficStats);
        VortexLogger.i('Core stopped');
        return true;
      }
      return false;
    } on PlatformException catch (e) {
      VortexLogger.e('Failed to stop core: ${e.message}');
      // 即使失败也更新状态，防止卡死
      _currentState = VpnState.disconnected;
      _stateController.add(_currentState);
      return false;
    }
  }

  /// 重载配置
  Future<bool> reloadConfig(String configPath) async {
    try {
      final result = await _channel.invokeMethod('reloadConfig', {
        'configPath': configPath,
      });
      return result == true;
    } on PlatformException catch (e) {
      VortexLogger.e('Failed to reload config: ${e.message}');
      return false;
    }
  }

  /// 启动 VPN 服务 (TUN 模式)
  Future<bool> startVpn() async {
    try {
      // Android 需要先请求权限
      if (Platform.isAndroid) {
        final hasPermission = await requestVpnPermission();
        if (!hasPermission) {
          VortexLogger.e('VPN permission denied');
          return false;
        }
      }

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
      // 添加超时保护
      final result = await _channel
          .invokeMethod('stopVpn')
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              VortexLogger.w('stopVpn native call timed out');
              return true;
            },
          );
      return result == true;
    } on PlatformException catch (e) {
      VortexLogger.e('Failed to stop VPN: ${e.message}');
      return false;
    }
  }

  /// 设置系统代理
  Future<bool> setSystemProxy(bool enable, {int port = 7890}) async {
    try {
      // 添加超时保护
      final result = await _channel
          .invokeMethod('setSystemProxy', {
            'enable': enable,
            'host': '127.0.0.1',
            'port': port,
          })
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              VortexLogger.w('setSystemProxy native call timed out');
              return true; // 假设成功
            },
          );
      VortexLogger.i(
        'System proxy ${enable ? 'enabled' : 'disabled'} on port $port',
      );
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
      return result as String? ?? 'disconnected';
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

  /// 检查核心是否运行
  Future<bool> isCoreRunning() async {
    try {
      final result = await _channel.invokeMethod('isCoreRunning');
      return result == true;
    } on PlatformException catch (e) {
      VortexLogger.e('Failed to check core status: ${e.message}');
      return false;
    }
  }

  /// 获取流量统计
  Future<TrafficStats?> getTrafficStats() async {
    try {
      final result = await _channel.invokeMethod('getTrafficStats');
      if (result is Map) {
        return TrafficStats.fromMap(Map<String, dynamic>.from(result));
      }
      return null;
    } on PlatformException catch (e) {
      VortexLogger.e('Failed to get traffic stats: ${e.message}');
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

  /// 导出日志到文件
  Future<String?> exportLogs() async {
    try {
      final result = await _channel.invokeMethod('exportLogs');
      return result as String?;
    } on PlatformException catch (e) {
      VortexLogger.e('Failed to export logs: ${e.message}');
      return null;
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

  /// 请求忽略电池优化 (Android)
  Future<bool> requestIgnoreBatteryOptimization() async {
    if (!Platform.isAndroid) return true;

    try {
      final result = await _channel.invokeMethod(
        'requestIgnoreBatteryOptimization',
      );
      return result == true;
    } on PlatformException catch (e) {
      VortexLogger.e(
        'Failed to request ignore battery optimization: ${e.message}',
      );
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

  /// 检查系统扩展状态 (macOS)
  Future<bool> checkSystemExtension() async {
    if (!Platform.isMacOS) return true;

    try {
      final result = await _channel.invokeMethod('checkSystemExtension');
      return result == true;
    } on PlatformException catch (e) {
      VortexLogger.e('Failed to check system extension: ${e.message}');
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

  /// 打开应用设置
  Future<bool> openAppSettings() async {
    try {
      final result = await _channel.invokeMethod('openAppSettings');
      return result == true;
    } on PlatformException catch (e) {
      VortexLogger.e('Failed to open app settings: ${e.message}');
      return false;
    }
  }

  /// 设置开机自启 (Windows/macOS)
  Future<bool> setAutoStart(bool enable) async {
    if (Platform.isAndroid || Platform.isIOS) return false;

    try {
      final result = await _channel.invokeMethod('setAutoStart', {
        'enable': enable,
      });
      return result == true;
    } on PlatformException catch (e) {
      VortexLogger.e('Failed to set auto start: ${e.message}');
      return false;
    }
  }

  /// 检查开机自启状态
  Future<bool> isAutoStartEnabled() async {
    if (Platform.isAndroid || Platform.isIOS) return false;

    try {
      final result = await _channel.invokeMethod('isAutoStartEnabled');
      return result == true;
    } on PlatformException catch (e) {
      VortexLogger.e('Failed to check auto start: ${e.message}');
      return false;
    }
  }

  /// 释放资源
  void dispose() {
    _eventSubscription?.cancel();
    _stateController.close();
    _trafficController.close();
    _logController.close();
  }
}
