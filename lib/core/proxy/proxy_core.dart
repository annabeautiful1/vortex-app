import 'dart:io';
import 'dart:ffi';
import 'package:path_provider/path_provider.dart';

import '../../shared/models/proxy_node.dart';
import '../utils/logger.dart';
import 'mihomo_service.dart';

/// Proxy core interface for Clash.Meta
class ProxyCore {
  static final ProxyCore _instance = ProxyCore._internal();
  static ProxyCore get instance => _instance;

  ProxyCore._internal();

  bool _isInitialized = false;
  bool _isConnected = false;
  bool _tunEnabled = false;
  ProxyNode? _currentNode;

  // Native library for Clash.Meta core (will be loaded via FFI)
  // ignore: unused_field
  DynamicLibrary? _clashLib;

  Future<void> init() async {
    if (_isInitialized) return;

    try {
      // Load native library based on platform
      _clashLib = _loadNativeLibrary();

      // Initialize core
      await _initCore();

      _isInitialized = true;
      VortexLogger.i('Proxy core initialized');
    } catch (e) {
      VortexLogger.e('Failed to initialize proxy core', e);
      rethrow;
    }
  }

  DynamicLibrary? _loadNativeLibrary() {
    try {
      if (Platform.isAndroid) {
        return DynamicLibrary.open('libclash.so');
      } else if (Platform.isIOS || Platform.isMacOS) {
        return DynamicLibrary.process();
      } else if (Platform.isWindows) {
        return DynamicLibrary.open('clash.dll');
      } else if (Platform.isLinux) {
        return DynamicLibrary.open('libclash.so');
      }
    } catch (e) {
      VortexLogger.e('Failed to load native library', e);
    }
    return null;
  }

  Future<void> _initCore() async {
    final configDir = await _getConfigDirectory();

    // Create config directory if not exists
    final dir = Directory(configDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // Initialize with default config
    VortexLogger.i('Config directory: $configDir');
  }

  Future<String> _getConfigDirectory() async {
    final appDir = await getApplicationSupportDirectory();
    return '${appDir.path}/clash';
  }

  Future<void> connect(ProxyNode node) async {
    if (!_isInitialized) {
      await init();
    }

    try {
      VortexLogger.i('Connecting to ${node.name}...');

      // Generate Clash config for this node
      final config = _generateConfig(node);

      // Write config to file
      final configPath = await _writeConfig(config);

      // Start Clash core with config
      await _startCore(configPath);

      // Set system proxy
      if (!_tunEnabled) {
        await _setSystemProxy(true);
      }

      _currentNode = node;
      _isConnected = true;

      VortexLogger.i('Connected to ${node.name}');
    } catch (e) {
      VortexLogger.e('Connection failed', e);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    try {
      VortexLogger.i('Disconnecting...');

      // Stop Clash core
      await _stopCore();

      // Remove system proxy
      await _setSystemProxy(false);

      _currentNode = null;
      _isConnected = false;

      VortexLogger.i('Disconnected');
    } catch (e) {
      VortexLogger.e('Disconnect failed', e);
      rethrow;
    }
  }

  void setTunMode(bool enabled) {
    _tunEnabled = enabled;
    if (_isConnected) {
      // Reconfigure TUN mode
      _configureTun(enabled);
    }
  }

  /// 测试节点延迟 - 使用 Mihomo API 测量真实代理延迟
  ///
  /// 这个方法测量的是通过代理访问目标 URL 的完整延迟，包括：
  /// - DNS 解析
  /// - TCP 连接建立（包括中转服务器链路）
  /// - TLS 握手（如果使用 HTTPS）
  /// - HTTP 请求/响应
  ///
  /// 参考 Clash for Windows, Clash Verge Rev, FlClash 的实现方式
  /// 真实延迟 = 用户设备 → 中转服务器(可选) → 落地服务器 → 测试URL
  Future<int?> testLatency(ProxyNode node) async {
    try {
      // 直接使用 Mihomo API 测试真实代理延迟
      // MihomoService 会处理核心未运行的情况
      final mihomoDelay = await MihomoService.instance.testProxyDelay(
        node.name,
        url: MihomoService.defaultDelayTestUrl,
        timeout: MihomoService.defaultDelayTimeout,
      );

      if (mihomoDelay != null && mihomoDelay > 0) {
        VortexLogger.d('Real delay for ${node.name}: ${mihomoDelay}ms');
        return mihomoDelay;
      }

      // 如果 API 返回 null 或 0，说明测试失败或节点不可用
      VortexLogger.d('Delay test returned null/0 for ${node.name}');
      return null;
    } catch (e) {
      VortexLogger.w('Latency test failed for ${node.name}: $e');
      return null;
    }
  }

  /// 直接 TCP 连接测试（仅用于连通性检测，不反映真实延迟）
  /// 注意：这只测试到代理服务器的 TCP 连接时间，不是真实的代理延迟
  /// 已弃用：请使用 testLatency() 获取真实延迟
  @Deprecated('Use testLatency() for real proxy delay')
  Future<int?> testTcpConnectivity(ProxyNode node) async {
    try {
      final stopwatch = Stopwatch()..start();

      final socket = await Socket.connect(
        node.server,
        node.port,
        timeout: const Duration(seconds: 5),
      );
      await socket.close();

      stopwatch.stop();
      final latency = stopwatch.elapsedMilliseconds;
      VortexLogger.d('TCP latency for ${node.name}: ${latency}ms (direct)');
      return latency;
    } catch (e) {
      return null;
    }
  }

  /// 批量测试所有节点延迟 - 使用 Mihomo API
  ///
  /// 优先使用 Mihomo 的批量测试 API，效率更高
  /// 注意：此方法需要 Mihomo 核心运行中，否则返回空结果
  /// 推荐使用 VpnService.testAllNodesDelay() 获取更可靠的结果
  Future<Map<String, int?>> testAllLatencies(List<ProxyNode> nodes) async {
    final results = <String, int?>{};

    if (nodes.isEmpty) return results;

    // 获取所有节点名称
    final nodeNames = nodes.map((n) => n.name).toList();

    // 使用 Mihomo API 批量测试
    try {
      final mihomoResults = await MihomoService.instance.testMultipleProxyDelay(
        nodeNames,
        url: MihomoService.defaultDelayTestUrl,
        timeout: MihomoService.defaultDelayTimeout,
        concurrency: 5, // 并发限制，避免请求过多
      );

      // 将结果映射到节点 ID
      for (final node in nodes) {
        results[node.id] = mihomoResults[node.name];
      }

      VortexLogger.i(
        'Batch delay test completed: ${results.length} nodes tested',
      );
      return results;
    } catch (e) {
      VortexLogger.w('Mihomo batch test failed: $e');
      // 如果 API 失败，返回空结果（不再使用不准确的 TCP 测试）
      return results;
    }
  }

  Map<String, dynamic> _generateConfig(ProxyNode node) {
    // Generate Clash.Meta compatible config
    final config = {
      'port': 7890,
      'socks-port': 7891,
      'mixed-port': 7892,
      'allow-lan': false,
      'mode': 'rule',
      'log-level': 'info',
      'external-controller': '127.0.0.1:9090',
      // 启用统一延迟测试 - 测量完整的 TCP/TLS 握手延迟
      'unified-delay': true,
      // TCP 并发，提高连接成功率
      'tcp-concurrent': true,
      'dns': {
        'enable': true,
        'enhanced-mode': 'fake-ip',
        'nameserver': ['8.8.8.8', '1.1.1.1'],
      },
      'proxies': [_nodeToProxy(node)],
      'proxy-groups': [
        {
          'name': 'Proxy',
          'type': 'select',
          'proxies': [node.name],
        },
      ],
      'rules': ['MATCH,Proxy'],
    };

    if (_tunEnabled) {
      config['tun'] = {
        'enable': true,
        'stack': 'system',
        'auto-route': true,
        'auto-detect-interface': true,
      };
    }

    return config;
  }

  Map<String, dynamic> _nodeToProxy(ProxyNode node) {
    final proxy = <String, dynamic>{
      'name': node.name,
      'server': node.server,
      'port': node.port,
    };

    switch (node.protocol) {
      case ProtocolType.shadowsocks:
        proxy['type'] = 'ss';
        proxy.addAll(node.settings);
        break;
      case ProtocolType.shadowsocksR:
        proxy['type'] = 'ssr';
        proxy.addAll(node.settings);
        break;
      case ProtocolType.vmess:
        proxy['type'] = 'vmess';
        proxy.addAll(node.settings);
        break;
      case ProtocolType.vless:
        proxy['type'] = 'vless';
        proxy.addAll(node.settings);
        break;
      case ProtocolType.trojan:
        proxy['type'] = 'trojan';
        proxy.addAll(node.settings);
        break;
      case ProtocolType.hysteria:
        proxy['type'] = 'hysteria';
        proxy.addAll(node.settings);
        break;
      case ProtocolType.hysteria2:
        proxy['type'] = 'hysteria2';
        proxy.addAll(node.settings);
        break;
      case ProtocolType.tuic:
        proxy['type'] = 'tuic';
        proxy.addAll(node.settings);
        break;
      case ProtocolType.wireguard:
        proxy['type'] = 'wireguard';
        proxy.addAll(node.settings);
        break;
      case ProtocolType.anytls:
        proxy['type'] = 'anytls';
        proxy.addAll(node.settings);
        break;
    }

    return proxy;
  }

  Future<String> _writeConfig(Map<String, dynamic> config) async {
    final configDir = await _getConfigDirectory();
    final configFile = File('$configDir/config.yaml');

    // Convert to YAML format
    final yamlContent = _mapToYaml(config);
    await configFile.writeAsString(yamlContent);

    return configFile.path;
  }

  String _mapToYaml(Map<String, dynamic> map, [int indent = 0]) {
    final buffer = StringBuffer();
    final prefix = '  ' * indent;

    map.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        buffer.writeln('$prefix$key:');
        buffer.write(_mapToYaml(value, indent + 1));
      } else if (value is List) {
        buffer.writeln('$prefix$key:');
        for (final item in value) {
          if (item is Map<String, dynamic>) {
            buffer.writeln('$prefix  -');
            buffer.write(_mapToYaml(item, indent + 2));
          } else {
            buffer.writeln('$prefix  - $item');
          }
        }
      } else {
        buffer.writeln('$prefix$key: $value');
      }
    });

    return buffer.toString();
  }

  Future<void> _startCore(String configPath) async {
    // Platform-specific core start implementation
    VortexLogger.i('Starting core with config: $configPath');
    // This will be implemented via FFI or platform channels
  }

  Future<void> _stopCore() async {
    // Platform-specific core stop implementation
    VortexLogger.i('Stopping core');
  }

  Future<void> _setSystemProxy(bool enable) async {
    // Platform-specific system proxy configuration
    VortexLogger.i('System proxy ${enable ? 'enabled' : 'disabled'}');
  }

  void _configureTun(bool enable) {
    // Platform-specific TUN configuration
    VortexLogger.i('TUN mode ${enable ? 'enabled' : 'disabled'}');
  }

  bool get isConnected => _isConnected;
  bool get tunEnabled => _tunEnabled;
  ProxyNode? get currentNode => _currentNode;
}
