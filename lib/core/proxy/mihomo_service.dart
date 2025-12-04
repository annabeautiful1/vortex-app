import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../shared/models/proxy_node.dart';
import '../utils/logger.dart';

/// Mihomo (Clash.Meta) Core Service
/// 通过 RESTful API 与 Mihomo 核心通信
class MihomoService {
  static final MihomoService _instance = MihomoService._internal();
  static MihomoService get instance => _instance;

  MihomoService._internal();

  // Mihomo API 配置
  static const String _defaultHost = '127.0.0.1';
  static const int _defaultPort = 9090;
  static const String _defaultSecret = '';

  // 延迟测试 URL 列表（按优先级排序）
  static const List<String> delayTestUrls = [
    'https://www.gstatic.com/generate_204', // Google - 最稳定
    'https://cp.cloudflare.com/generate_204', // Cloudflare
    'https://www.google.com/generate_204', // Google 备用
    'http://www.msftconnecttest.com/connecttest.txt', // Microsoft
  ];

  // 默认延迟测试 URL
  static const String defaultDelayTestUrl =
      'https://www.gstatic.com/generate_204';

  // 默认超时时间（毫秒）- 增加到 10 秒以适应跨国延迟
  static const int defaultDelayTimeout = 10000;

  late Dio _dio;
  String _host = _defaultHost;
  int _port = _defaultPort;
  String _secret = _defaultSecret;

  bool _isRunning = false;
  Process? _coreProcess;

  String get apiBaseUrl => 'http://$_host:$_port';

  /// 初始化服务
  Future<void> init({String? host, int? port, String? secret}) async {
    _host = host ?? _defaultHost;
    _port = port ?? _defaultPort;
    _secret = secret ?? _defaultSecret;

    _dio = Dio(
      BaseOptions(
        baseUrl: apiBaseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
        headers: _secret.isNotEmpty
            ? {'Authorization': 'Bearer $_secret'}
            : null,
      ),
    );

    VortexLogger.i('MihomoService initialized: $apiBaseUrl');
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

  /// 启动核心（通过平台通道调用原生代码）
  Future<bool> startCore() async {
    if (_isRunning) {
      VortexLogger.w('Mihomo core is already running');
      return true;
    }

    try {
      // 核心启动逻辑将通过平台通道实现
      // 这里预留接口
      VortexLogger.i('Starting Mihomo core...');

      // 等待核心启动
      await Future.delayed(const Duration(seconds: 2));

      // 验证核心是否启动
      final isHealthy = await healthCheck();
      if (isHealthy) {
        _isRunning = true;
        VortexLogger.i('Mihomo core started successfully');
        return true;
      }

      VortexLogger.e('Mihomo core health check failed');
      return false;
    } catch (e) {
      VortexLogger.e('Failed to start Mihomo core', e);
      return false;
    }
  }

  /// 停止核心
  Future<void> stopCore() async {
    if (!_isRunning) return;

    try {
      _coreProcess?.kill();
      _isRunning = false;
      VortexLogger.i('Mihomo core stopped');
    } catch (e) {
      VortexLogger.e('Failed to stop Mihomo core', e);
    }
  }

  /// 健康检查
  Future<bool> healthCheck() async {
    try {
      final response = await _dio.get('/');
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// 获取版本信息
  Future<Map<String, dynamic>?> getVersion() async {
    try {
      final response = await _dio.get('/version');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      VortexLogger.e('Failed to get version', e);
      return null;
    }
  }

  /// 获取当前配置
  Future<Map<String, dynamic>?> getConfig() async {
    try {
      final response = await _dio.get('/configs');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      VortexLogger.e('Failed to get config', e);
      return null;
    }
  }

  /// 更新配置
  Future<bool> updateConfig(Map<String, dynamic> config) async {
    try {
      await _dio.patch('/configs', data: config);
      VortexLogger.i('Config updated');
      return true;
    } catch (e) {
      VortexLogger.e('Failed to update config', e);
      return false;
    }
  }

  /// 重载配置文件
  Future<bool> reloadConfig(String configPath) async {
    try {
      await _dio.put('/configs', queryParameters: {'path': configPath});
      VortexLogger.i('Config reloaded: $configPath');
      return true;
    } catch (e) {
      VortexLogger.e('Failed to reload config', e);
      return false;
    }
  }

  /// 获取所有代理
  Future<Map<String, dynamic>?> getProxies() async {
    try {
      final response = await _dio.get('/proxies');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      VortexLogger.e('Failed to get proxies', e);
      return null;
    }
  }

  /// 获取单个代理信息
  Future<Map<String, dynamic>?> getProxy(String name) async {
    try {
      final response = await _dio.get('/proxies/${Uri.encodeComponent(name)}');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      VortexLogger.e('Failed to get proxy: $name', e);
      return null;
    }
  }

  /// 切换代理
  Future<bool> selectProxy(String groupName, String proxyName) async {
    try {
      await _dio.put(
        '/proxies/${Uri.encodeComponent(groupName)}',
        data: {'name': proxyName},
      );
      VortexLogger.i('Proxy selected: $groupName -> $proxyName');
      return true;
    } catch (e) {
      VortexLogger.e('Failed to select proxy', e);
      return false;
    }
  }

  /// 测试代理延迟（真实 TCP 延迟）
  /// 使用 HTTPS URL 测试完整的 TLS 握手延迟，反映真实使用体验
  ///
  /// [name] 代理名称
  /// [url] 测试 URL，默认使用 Google generate_204
  /// [timeout] 超时时间（毫秒），默认 10 秒
  Future<int?> testProxyDelay(String name, {String? url, int? timeout}) async {
    final testUrl = url ?? defaultDelayTestUrl;
    final testTimeout = timeout ?? defaultDelayTimeout;

    try {
      final response = await _dio.get(
        '/proxies/${Uri.encodeComponent(name)}/delay',
        queryParameters: {'url': testUrl, 'timeout': testTimeout},
        options: Options(
          receiveTimeout: Duration(milliseconds: testTimeout + 2000),
        ),
      );
      final delay = response.data['delay'] as int?;
      if (delay != null && delay > 0) {
        VortexLogger.d('Delay test for $name: ${delay}ms');
      }
      return delay;
    } catch (e) {
      VortexLogger.w('Delay test failed for $name: $e');
      return null;
    }
  }

  /// 使用多个 URL 测试延迟，返回最快的有效结果
  /// 这种方式可以避免单一 URL 被墙导致的测试失败
  Future<int?> testProxyDelayWithFallback(String name) async {
    for (final url in delayTestUrls) {
      final delay = await testProxyDelay(name, url: url, timeout: 8000);
      if (delay != null && delay > 0) {
        return delay;
      }
    }
    return null;
  }

  /// 批量测试延迟（组内所有节点）
  Future<Map<String, int?>> testGroupDelay(
    String groupName, {
    String? url,
    int? timeout,
  }) async {
    final testUrl = url ?? defaultDelayTestUrl;
    final testTimeout = timeout ?? defaultDelayTimeout;

    try {
      final response = await _dio.get(
        '/group/${Uri.encodeComponent(groupName)}/delay',
        queryParameters: {'url': testUrl, 'timeout': testTimeout},
        options: Options(
          receiveTimeout: Duration(milliseconds: testTimeout + 5000),
        ),
      );
      final data = response.data as Map<String, dynamic>;
      return data.map((key, value) => MapEntry(key, value as int?));
    } catch (e) {
      VortexLogger.e('Group delay test failed', e);
      return {};
    }
  }

  /// 并发测试多个节点的延迟
  /// 返回 Map<节点名, 延迟(ms)>，超时或失败的节点值为 null
  Future<Map<String, int?>> testMultipleProxyDelay(
    List<String> names, {
    String? url,
    int? timeout,
    int concurrency = 5, // 并发数量限制
  }) async {
    final results = <String, int?>{};
    final testUrl = url ?? defaultDelayTestUrl;
    final testTimeout = timeout ?? defaultDelayTimeout;

    // 分批并发测试
    for (var i = 0; i < names.length; i += concurrency) {
      final batch = names.skip(i).take(concurrency).toList();
      final futures = batch.map(
        (name) => testProxyDelay(
          name,
          url: testUrl,
          timeout: testTimeout,
        ).then((delay) => MapEntry(name, delay)),
      );

      final batchResults = await Future.wait(futures);
      for (final entry in batchResults) {
        results[entry.key] = entry.value;
      }
    }

    return results;
  }

  /// 获取规则
  Future<Map<String, dynamic>?> getRules() async {
    try {
      final response = await _dio.get('/rules');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      VortexLogger.e('Failed to get rules', e);
      return null;
    }
  }

  /// 获取连接列表
  Future<Map<String, dynamic>?> getConnections() async {
    try {
      final response = await _dio.get('/connections');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      VortexLogger.e('Failed to get connections', e);
      return null;
    }
  }

  /// 关闭所有连接
  Future<bool> closeAllConnections() async {
    try {
      await _dio.delete('/connections');
      VortexLogger.i('All connections closed');
      return true;
    } catch (e) {
      VortexLogger.e('Failed to close connections', e);
      return false;
    }
  }

  /// 关闭单个连接
  Future<bool> closeConnection(String id) async {
    try {
      await _dio.delete('/connections/$id');
      return true;
    } catch (e) {
      VortexLogger.e('Failed to close connection: $id', e);
      return false;
    }
  }

  /// 获取流量统计
  Future<Stream<Map<String, dynamic>>> getTrafficStream() async {
    final controller = StreamController<Map<String, dynamic>>();

    try {
      final response = await _dio.get(
        '/traffic',
        options: Options(responseType: ResponseType.stream),
      );

      final stream = response.data.stream as Stream<List<int>>;
      stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (line.isNotEmpty) {
                try {
                  final data = jsonDecode(line) as Map<String, dynamic>;
                  controller.add(data);
                } catch (_) {}
              }
            },
            onError: controller.addError,
            onDone: controller.close,
          );
    } catch (e) {
      controller.addError(e);
      controller.close();
    }

    return controller.stream;
  }

  /// 获取日志流
  Future<Stream<Map<String, dynamic>>> getLogsStream({
    String level = 'info',
  }) async {
    final controller = StreamController<Map<String, dynamic>>();

    try {
      final response = await _dio.get(
        '/logs',
        queryParameters: {'level': level},
        options: Options(responseType: ResponseType.stream),
      );

      final stream = response.data.stream as Stream<List<int>>;
      stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (line.isNotEmpty) {
                try {
                  final data = jsonDecode(line) as Map<String, dynamic>;
                  controller.add(data);
                } catch (_) {}
              }
            },
            onError: controller.addError,
            onDone: controller.close,
          );
    } catch (e) {
      controller.addError(e);
      controller.close();
    }

    return controller.stream;
  }

  /// 获取内存使用
  Future<Map<String, dynamic>?> getMemory() async {
    try {
      final response = await _dio.get('/memory');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      VortexLogger.e('Failed to get memory', e);
      return null;
    }
  }

  /// 刷新代理 Provider
  Future<bool> updateProxyProvider(String name) async {
    try {
      await _dio.put('/providers/proxies/${Uri.encodeComponent(name)}');
      VortexLogger.i('Proxy provider updated: $name');
      return true;
    } catch (e) {
      VortexLogger.e('Failed to update proxy provider', e);
      return false;
    }
  }

  /// 刷新规则 Provider
  Future<bool> updateRuleProvider(String name) async {
    try {
      await _dio.put('/providers/rules/${Uri.encodeComponent(name)}');
      VortexLogger.i('Rule provider updated: $name');
      return true;
    } catch (e) {
      VortexLogger.e('Failed to update rule provider', e);
      return false;
    }
  }

  /// 设置系统代理
  Future<bool> setSystemProxy(bool enable) async {
    // 通过更新配置来控制 TUN
    return await updateConfig({
      'tun': {'enable': enable},
    });
  }

  /// 生成配置文件
  Future<String> generateConfig({
    required List<ProxyNode> nodes,
    required int mixedPort,
    bool tunEnabled = false,
    bool allowLan = false,
    String mode = 'rule',
    String logLevel = 'info',
  }) async {
    final config = {
      'mixed-port': mixedPort,
      'allow-lan': allowLan,
      'mode': mode,
      'log-level': logLevel,
      'ipv6': false,
      'external-controller': '$_host:$_port',
      if (_secret.isNotEmpty) 'secret': _secret,
      // 启用统一延迟测试 - 测量完整的 TCP/TLS 握手延迟
      // 参考 clash verge rev 的实现
      'unified-delay': true,
      // TCP 并发，提高连接成功率
      'tcp-concurrent': true,
      'dns': {
        'enable': true,
        'enhanced-mode': 'fake-ip',
        'fake-ip-range': '198.18.0.1/16',
        'nameserver': ['223.5.5.5', '119.29.29.29'],
        'fallback': [
          'https://dns.google/dns-query',
          'https://cloudflare-dns.com/dns-query',
        ],
        'fallback-filter': {'geoip': true, 'geoip-code': 'CN'},
      },
      if (tunEnabled)
        'tun': {
          'enable': true,
          'stack': 'system',
          'auto-route': true,
          'auto-detect-interface': true,
          'dns-hijack': ['any:53'],
        },
      'proxies': nodes.map((n) => _nodeToProxy(n)).toList(),
      'proxy-groups': [
        {
          'name': 'PROXY',
          'type': 'select',
          'proxies': ['AUTO', ...nodes.map((n) => n.name)],
        },
        {
          'name': 'AUTO',
          'type': 'url-test',
          'proxies': nodes.map((n) => n.name).toList(),
          // 使用 HTTPS URL 测试真实 TLS 延迟
          'url': defaultDelayTestUrl,
          'interval': 300,
          'tolerance': 50, // 容差 50ms，避免频繁切换
        },
      ],
      'rules': ['GEOIP,LAN,DIRECT', 'GEOIP,CN,DIRECT', 'MATCH,PROXY'],
    };

    final configDir = await getConfigDirectory();
    final configFile = File('$configDir/config.yaml');
    await configFile.writeAsString(_toYaml(config));

    return configFile.path;
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

  String _toYaml(Map<String, dynamic> map, [int indent = 0]) {
    final buffer = StringBuffer();
    final prefix = '  ' * indent;

    map.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        buffer.writeln('$prefix$key:');
        buffer.write(_toYaml(value, indent + 1));
      } else if (value is List) {
        buffer.writeln('$prefix$key:');
        for (final item in value) {
          if (item is Map<String, dynamic>) {
            buffer.writeln('$prefix  -');
            item.forEach((k, v) {
              if (v is Map || v is List) {
                buffer.writeln('$prefix    $k:');
                if (v is Map<String, dynamic>) {
                  buffer.write(_toYaml(v, indent + 3));
                } else if (v is List) {
                  for (final i in v) {
                    buffer.writeln('$prefix      - $i');
                  }
                }
              } else {
                buffer.writeln('$prefix    $k: $v');
              }
            });
          } else {
            buffer.writeln('$prefix  - $item');
          }
        }
      } else if (value is String) {
        buffer.writeln('$prefix$key: "$value"');
      } else {
        buffer.writeln('$prefix$key: $value');
      }
    });

    return buffer.toString();
  }

  bool get isRunning => _isRunning;
}
