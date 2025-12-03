import 'dart:io';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';

import '../../shared/models/proxy_node.dart';
import '../utils/logger.dart';

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

  Future<int?> testLatency(ProxyNode node) async {
    try {
      final stopwatch = Stopwatch()..start();

      // TCP connection test to the node
      final socket = await Socket.connect(
        node.server,
        node.port,
        timeout: const Duration(seconds: 5),
      );
      await socket.close();

      stopwatch.stop();
      return stopwatch.elapsedMilliseconds;
    } catch (e) {
      VortexLogger.w('Latency test failed for ${node.name}');
      return null;
    }
  }

  Future<Map<String, int?>> testAllLatencies(List<ProxyNode> nodes) async {
    final results = <String, int?>{};

    // Test nodes in parallel with limited concurrency
    const batchSize = 10;
    for (var i = 0; i < nodes.length; i += batchSize) {
      final batch = nodes.skip(i).take(batchSize);
      final futures = batch.map((node) async {
        final latency = await testLatency(node);
        return MapEntry(node.id, latency);
      });
      final batchResults = await Future.wait(futures);
      results.addEntries(batchResults);
    }

    return results;
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
      'dns': {
        'enable': true,
        'enhanced-mode': 'fake-ip',
        'nameserver': [
          '8.8.8.8',
          '1.1.1.1',
        ],
      },
      'proxies': [_nodeToProxy(node)],
      'proxy-groups': [
        {
          'name': 'Proxy',
          'type': 'select',
          'proxies': [node.name],
        },
      ],
      'rules': [
        'MATCH,Proxy',
      ],
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
