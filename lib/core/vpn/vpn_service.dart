import 'dart:async';
import 'dart:io';

import '../../shared/models/proxy_node.dart';
import '../platform/platform_channel_service.dart';
import '../proxy/mihomo_service.dart';
import '../utils/logger.dart';

/// VPN 服务管理器 - 管理 VPN 连接的完整生命周期
class VpnService {
  static final VpnService _instance = VpnService._internal();
  static VpnService get instance => _instance;

  VpnService._internal();

  final PlatformChannelService _platformChannel =
      PlatformChannelService.instance;
  final MihomoService _mihomoService = MihomoService.instance;

  bool _isInitialized = false;
  ProxyNode? _currentNode;
  List<ProxyNode> _nodes = [];
  String? _currentConfigPath;

  // 配置
  bool _tunEnabled = false;
  final int _httpPort = 7890;
  final int _socksPort = 7891;
  final int _mixedPort = 7892;
  final int _controllerPort = 9090;
  final String _controllerSecret = '';

  /// 获取当前状态
  VpnState get currentState => _platformChannel.currentState;

  /// 状态流
  Stream<VpnState> get stateStream => _platformChannel.stateStream;

  /// 流量统计流
  Stream<TrafficStats> get trafficStream => _platformChannel.trafficStream;

  /// 日志流
  Stream<String> get logStream => _platformChannel.logStream;

  /// 当前流量统计
  TrafficStats get trafficStats => _platformChannel.trafficStats;

  /// 是否已连接
  bool get isConnected => _platformChannel.isConnected;

  /// 当前连接的节点
  ProxyNode? get currentNode => _currentNode;

  /// 节点列表
  List<ProxyNode> get nodes => _nodes;

  /// TUN 模式是否启用
  bool get tunEnabled => _tunEnabled;

  /// 初始化 VPN 服务
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      // 初始化平台通道
      await _platformChannel.init();

      // 创建配置目录
      await _ensureConfigDirectory();

      // 初始化 Mihomo REST API 服务
      await _mihomoService.init(
        host: '127.0.0.1',
        port: _controllerPort,
        secret: _controllerSecret,
      );

      _isInitialized = true;
      VortexLogger.i('VPN service initialized');
    } catch (e) {
      VortexLogger.e('Failed to initialize VPN service', e);
      rethrow;
    }
  }

  /// 设置节点列表
  void setNodes(List<ProxyNode> nodes) {
    _nodes = nodes;
    VortexLogger.i('Loaded ${nodes.length} nodes');
  }

  /// 连接到指定节点
  Future<bool> connect({ProxyNode? node}) async {
    if (!_isInitialized) {
      await init();
    }

    try {
      // 选择节点
      final targetNode = node ?? _selectBestNode();
      if (targetNode == null) {
        throw Exception('没有可用的节点');
      }

      VortexLogger.i('Connecting to ${targetNode.name}...');

      // 生成并写入配置文件
      _currentConfigPath = await _writeConfig(targetNode);

      // 启动核心
      final coreStarted = await _platformChannel.startCore(_currentConfigPath!);
      if (!coreStarted) {
        throw Exception('启动核心失败');
      }

      // 根据模式设置代理
      if (_tunEnabled) {
        // TUN 模式 - 启动 VPN 服务
        if (Platform.isAndroid || Platform.isIOS) {
          final vpnStarted = await _platformChannel.startVpn();
          if (!vpnStarted) {
            throw Exception('启动 VPN 服务失败');
          }
        }
      } else {
        // 系统代理模式
        await _platformChannel.setSystemProxy(true, port: _httpPort);
      }

      _currentNode = targetNode;
      VortexLogger.i('Connected to ${targetNode.name}');
      return true;
    } catch (e) {
      VortexLogger.e('Connection failed', e);
      // 清理
      await _cleanup();
      return false;
    }
  }

  /// 断开连接
  Future<bool> disconnect() async {
    try {
      VortexLogger.i('Disconnecting...');

      // 使用超时保护，防止卡死
      await Future.wait([
        // 停止 VPN 服务
        if (_tunEnabled && (Platform.isAndroid || Platform.isIOS))
          _platformChannel.stopVpn().timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              VortexLogger.w('stopVpn timed out');
              return;
            },
          ),

        // 关闭系统代理
        _platformChannel
            .setSystemProxy(false)
            .timeout(
              const Duration(seconds: 3),
              onTimeout: () {
                VortexLogger.w('setSystemProxy(false) timed out');
                return;
              },
            ),

        // 停止核心
        _platformChannel.stopCore().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            VortexLogger.w('stopCore timed out');
            return;
          },
        ),
      ]);

      _currentNode = null;
      _currentConfigPath = null;

      VortexLogger.i('Disconnected');
      return true;
    } catch (e) {
      VortexLogger.e('Disconnect failed', e);
      // 即使出错也要清理状态
      _currentNode = null;
      _currentConfigPath = null;
      return false;
    }
  }

  /// 切换节点
  Future<bool> switchNode(ProxyNode node) async {
    if (_currentNode?.id == node.id) {
      return true; // 已经连接到该节点
    }

    try {
      VortexLogger.i('Switching to ${node.name}...');

      // 如果核心正在运行，使用热切换
      if (isConnected) {
        // 1. 通过 Mihomo API 切换代理组中的节点
        final success = await _mihomoService.selectProxy('Proxy', node.name);
        if (success) {
          // 2. 关闭现有的所有连接，强制使用新节点建立新连接
          await _mihomoService.closeAllConnections();
          VortexLogger.i('Closed all existing connections');

          _currentNode = node;
          VortexLogger.i('Switched to ${node.name} via API');
          return true;
        }
      }

      // 否则重新连接
      await disconnect();
      return await connect(node: node);
    } catch (e) {
      VortexLogger.e('Switch node failed', e);
      return false;
    }
  }

  /// 设置 TUN 模式
  Future<void> setTunMode(bool enabled) async {
    if (_tunEnabled == enabled) return;

    _tunEnabled = enabled;
    VortexLogger.i('TUN mode ${enabled ? 'enabled' : 'disabled'}');

    // 如果已连接，需要重新连接以应用新设置
    if (isConnected) {
      final node = _currentNode;
      await disconnect();
      await connect(node: node);
    }
  }

  /// 测试节点延迟
  Future<int> testNodeDelay(ProxyNode node, {int timeout = 5000}) async {
    // 如果核心运行中，使用 API 测试
    if (isConnected) {
      final delay = await _mihomoService.testProxyDelay(
        node.name,
        timeout: timeout,
      );
      return delay ?? -1;
    }

    // 否则直接 TCP 连接测试
    try {
      final stopwatch = Stopwatch()..start();
      final socket = await Socket.connect(
        node.server,
        node.port,
        timeout: Duration(milliseconds: timeout),
      );
      await socket.close();
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds;
    } catch (e) {
      return -1;
    }
  }

  /// 测试所有节点延迟
  Future<Map<String, int>> testAllNodesDelay({int timeout = 5000}) async {
    final results = <String, int>{};

    // 如果核心运行中，使用 API 批量测试
    if (isConnected) {
      final proxies = await _mihomoService.getProxies();
      if (proxies != null && proxies['proxies'] != null) {
        for (final node in _nodes) {
          final delay = await _mihomoService.testProxyDelay(
            node.name,
            timeout: timeout,
          );
          results[node.id] = delay ?? -1;
        }
        return results;
      }
    }

    // 并行测试（限制并发数）
    const batchSize = 10;
    for (var i = 0; i < _nodes.length; i += batchSize) {
      final batch = _nodes.skip(i).take(batchSize).toList();
      final futures = batch.map((node) async {
        final delay = await testNodeDelay(node, timeout: timeout);
        return MapEntry(node.id, delay);
      });
      final batchResults = await Future.wait(futures);
      results.addEntries(batchResults);
    }

    return results;
  }

  /// 获取连接信息
  Future<Map<String, dynamic>?> getConnections() async {
    if (!isConnected) return null;
    return await _mihomoService.getConnections();
  }

  /// 关闭指定连接
  Future<bool> closeConnection(String id) async {
    if (!isConnected) return false;
    return await _mihomoService.closeConnection(id);
  }

  /// 关闭所有连接
  Future<bool> closeAllConnections() async {
    if (!isConnected) return false;
    return await _mihomoService.closeAllConnections();
  }

  /// 导出日志
  Future<String?> exportLogs() async {
    return await _platformChannel.exportLogs();
  }

  /// 复制日志到剪贴板
  Future<bool> copyLogsToClipboard() async {
    return await _platformChannel.copyLogsToClipboard();
  }

  /// 选择最佳节点（延迟最低）
  ProxyNode? _selectBestNode() {
    if (_nodes.isEmpty) return null;
    // 简单返回第一个节点，后续可以实现智能选择
    return _nodes.first;
  }

  /// 确保配置目录存在
  Future<String> _ensureConfigDirectory() async {
    final configDir = await _platformChannel.getConfigDirectory();
    final dir = Directory(configDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return configDir;
  }

  /// 生成并写入配置文件
  Future<String> _writeConfig(ProxyNode node) async {
    final configDir = await _ensureConfigDirectory();
    final configPath = '$configDir/config.yaml';

    // 生成配置
    final config = _generateConfig(node);

    // 写入文件
    final file = File(configPath);
    await file.writeAsString(config);

    VortexLogger.d('Config written to: $configPath');
    return configPath;
  }

  /// 生成 Mihomo 配置
  String _generateConfig(ProxyNode node) {
    final buffer = StringBuffer();

    // 基础配置
    buffer.writeln('# Vortex Generated Config');
    buffer.writeln('port: $_httpPort');
    buffer.writeln('socks-port: $_socksPort');
    buffer.writeln('mixed-port: $_mixedPort');
    buffer.writeln('allow-lan: false');
    buffer.writeln('mode: rule');
    buffer.writeln('log-level: info');
    buffer.writeln('external-controller: 127.0.0.1:$_controllerPort');
    if (_controllerSecret.isNotEmpty) {
      buffer.writeln('secret: $_controllerSecret');
    }
    buffer.writeln();

    // DNS 配置
    buffer.writeln('dns:');
    buffer.writeln('  enable: true');
    buffer.writeln('  enhanced-mode: fake-ip');
    buffer.writeln('  fake-ip-range: 198.18.0.1/16');
    buffer.writeln('  nameserver:');
    buffer.writeln('    - 8.8.8.8');
    buffer.writeln('    - 1.1.1.1');
    buffer.writeln('  fallback:');
    buffer.writeln('    - tls://8.8.8.8');
    buffer.writeln('    - tls://1.1.1.1');
    buffer.writeln();

    // TUN 配置
    if (_tunEnabled) {
      buffer.writeln('tun:');
      buffer.writeln('  enable: true');
      buffer.writeln('  stack: system');
      buffer.writeln('  auto-route: true');
      buffer.writeln('  auto-detect-interface: true');
      buffer.writeln('  dns-hijack:');
      buffer.writeln('    - any:53');
      buffer.writeln();
    }

    // 代理配置
    buffer.writeln('proxies:');
    buffer.write(_generateProxyConfig(node));
    buffer.writeln();

    // 代理组配置 - 包含所有节点
    buffer.writeln('proxy-groups:');
    buffer.writeln('  - name: Proxy');
    buffer.writeln('    type: select');
    buffer.writeln('    proxies:');
    for (final n in _nodes) {
      buffer.writeln('      - ${n.name}');
    }
    if (_nodes.isEmpty) {
      buffer.writeln('      - ${node.name}');
    }
    buffer.writeln();

    // 规则配置
    buffer.writeln('rules:');
    buffer.writeln('  - GEOIP,CN,DIRECT');
    buffer.writeln('  - MATCH,Proxy');

    return buffer.toString();
  }

  /// 生成单个代理节点配置
  String _generateProxyConfig(ProxyNode node) {
    final buffer = StringBuffer();

    // 如果有多个节点，全部添加
    final nodesToAdd = _nodes.isNotEmpty ? _nodes : [node];

    for (final n in nodesToAdd) {
      buffer.writeln('  - name: ${n.name}');
      buffer.writeln('    server: ${n.server}');
      buffer.writeln('    port: ${n.port}');
      buffer.writeln('    type: ${_getProxyType(n.protocol)}');

      // 添加协议特定设置
      n.settings.forEach((key, value) {
        if (value != null && value.toString().isNotEmpty) {
          if (value is String && value.contains(':')) {
            buffer.writeln('    $key: "$value"');
          } else if (value is bool) {
            buffer.writeln('    $key: $value');
          } else if (value is List) {
            buffer.writeln('    $key:');
            for (final item in value) {
              buffer.writeln('      - $item');
            }
          } else if (value is Map) {
            buffer.writeln('    $key:');
            value.forEach((k, v) {
              buffer.writeln('      $k: $v');
            });
          } else {
            buffer.writeln('    $key: $value');
          }
        }
      });
    }

    return buffer.toString();
  }

  String _getProxyType(ProtocolType protocol) {
    switch (protocol) {
      case ProtocolType.shadowsocks:
        return 'ss';
      case ProtocolType.shadowsocksR:
        return 'ssr';
      case ProtocolType.vmess:
        return 'vmess';
      case ProtocolType.vless:
        return 'vless';
      case ProtocolType.trojan:
        return 'trojan';
      case ProtocolType.hysteria:
        return 'hysteria';
      case ProtocolType.hysteria2:
        return 'hysteria2';
      case ProtocolType.tuic:
        return 'tuic';
      case ProtocolType.wireguard:
        return 'wireguard';
      case ProtocolType.anytls:
        return 'anytls';
    }
  }

  /// 清理资源
  Future<void> _cleanup() async {
    try {
      await _platformChannel.stopVpn();
      await _platformChannel.setSystemProxy(false);
      await _platformChannel.stopCore();
    } catch (e) {
      VortexLogger.e('Cleanup error', e);
    }
    _currentNode = null;
    _currentConfigPath = null;
  }

  /// 释放资源
  void dispose() {
    _cleanup();
  }
}
