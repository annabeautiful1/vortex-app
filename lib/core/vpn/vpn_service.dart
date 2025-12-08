import 'dart:async';
import 'dart:io';

import '../../shared/models/proxy_node.dart';
import '../config/config_validator.dart';
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
  final ConfigValidator _configValidator = ConfigValidator.instance;

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

  /// 核心是否在运行（包括后台运行但未连接VPN的情况）
  bool get isCoreRunning => _isCoreRunning || _platformChannel.isConnected;
  bool _isCoreRunning = false;

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

      // 初始化配置验证器
      await _configValidator.init();

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

  /// 预启动核心（后台运行，不设置系统代理）
  /// 用于支持即时测速功能，避免测速时临时启动核心导致卡顿
  Future<bool> startBackgroundCore() async {
    if (_isCoreRunning || isConnected) {
      VortexLogger.i('Core already running, skip background start');
      return true;
    }

    if (_nodes.isEmpty) {
      VortexLogger.w('No nodes available, cannot start background core');
      return false;
    }

    VortexLogger.i('Starting background core for delay testing...');

    try {
      // 启用静默模式，不触发 UI 状态变化
      _platformChannel.setSilentMode(true);

      // 生成配置
      final configPath = await _writeDelayTestConfig();

      // 验证配置（后台核心也需要验证）
      final validationResult = await _configValidator.validateConfig(
        configPath,
      );
      if (!validationResult.isValid) {
        VortexLogger.w(
          'Background config validation failed: ${validationResult.errorMessage}',
        );
        // 后台核心验证失败不阻塞，继续尝试启动
      }

      // 启动核心（在后台线程执行，避免阻塞 UI）
      final started = await _platformChannel.startCore(configPath);

      if (started) {
        _isCoreRunning = true;
        VortexLogger.i('Background core started successfully');

        // 等待核心完全启动
        await Future.delayed(const Duration(milliseconds: 500));
      } else {
        VortexLogger.w('Failed to start background core');
        _platformChannel.setSilentMode(false);
      }

      return started;
    } catch (e) {
      VortexLogger.e('Error starting background core', e);
      _platformChannel.setSilentMode(false);
      return false;
    }
  }

  /// 停止后台核心
  Future<void> stopBackgroundCore() async {
    if (!_isCoreRunning || isConnected) {
      return; // 不停止正在使用的核心
    }

    VortexLogger.i('Stopping background core...');

    try {
      await _platformChannel.stopCore();
    } catch (e) {
      VortexLogger.e('Error stopping background core', e);
    } finally {
      _isCoreRunning = false;
      _platformChannel.setSilentMode(false);
    }
  }

  /// 设置节点列表
  void setNodes(List<ProxyNode> nodes) {
    _nodes = nodes;
    VortexLogger.i('Loaded ${nodes.length} nodes');
  }

  /// 连接到指定节点
  ///
  /// 使用 Draft-Validate-Apply 模式：
  /// 1. 生成配置文件
  /// 2. 验证配置
  /// 3. 启动核心
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

      // 1. Draft - 生成并写入配置文件
      _currentConfigPath = await _writeConfig(targetNode);

      // 2. Validate - 验证配置（参考 Clash Verge Rev）
      final validationResult = await _configValidator.validateConfig(
        _currentConfigPath!,
      );
      if (!validationResult.isValid) {
        VortexLogger.e(
          'Config validation failed: ${validationResult.errorMessage}',
        );
        throw Exception(validationResult.errorMessage ?? '配置验证失败');
      }
      VortexLogger.i('Config validation passed');

      // 3. Apply - 启动核心
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

      // 顺序执行而不是并行，每一步都有超时保护
      // 1. 停止 VPN 服务 (移动端)
      if (_tunEnabled && (Platform.isAndroid || Platform.isIOS)) {
        try {
          await _platformChannel.stopVpn().timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              VortexLogger.w('stopVpn timed out');
              return false;
            },
          );
        } catch (e) {
          VortexLogger.w('stopVpn error: $e');
        }
      }

      // 2. 关闭系统代理
      try {
        await _platformChannel
            .setSystemProxy(false)
            .timeout(
              const Duration(seconds: 3),
              onTimeout: () {
                VortexLogger.w('setSystemProxy(false) timed out');
                return false;
              },
            );
      } catch (e) {
        VortexLogger.w('setSystemProxy error: $e');
      }

      // 3. 停止核心
      try {
        await _platformChannel.stopCore().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            VortexLogger.w('stopCore timed out');
            return false;
          },
        );
      } catch (e) {
        VortexLogger.w('stopCore error: $e');
      }

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

  /// 测试节点延迟 - 真实全链路延迟
  ///
  /// 通过 Mihomo API 测试代理延迟，流量经过完整链路：
  /// 用户设备 → 中转服务器(可选) → 落地服务器 → 测试URL
  ///
  /// 如果核心未运行，会临时启动核心进行测试
  Future<int> testNodeDelay(ProxyNode node, {int timeout = 10000}) async {
    // 如果核心运行中，直接使用 API 测试
    if (isConnected) {
      final delay = await _mihomoService.testProxyDelay(
        node.name,
        timeout: timeout,
      );
      return delay ?? -1;
    }

    // 核心未运行，需要临时启动进行测试
    return await _testDelayWithTempCore(node, timeout: timeout);
  }

  /// 临时启动核心测试延迟
  bool _isTempCoreRunning = false;

  Future<int> _testDelayWithTempCore(
    ProxyNode node, {
    int timeout = 10000,
  }) async {
    // 如果已经有临时核心在运行，直接测试
    if (_isTempCoreRunning) {
      final delay = await _mihomoService.testProxyDelay(
        node.name,
        timeout: timeout,
      );
      return delay ?? -1;
    }

    // 没有节点，无法测试
    if (_nodes.isEmpty && node.id.isEmpty) {
      VortexLogger.w('No nodes available for delay test');
      return -1;
    }

    try {
      VortexLogger.i('Starting temp core for delay test...');
      _isTempCoreRunning = true;

      // 启用静默模式，防止状态变化影响主 UI
      _platformChannel.setSilentMode(true);

      // 生成包含所有节点的临时配置
      final configPath = await _writeDelayTestConfig();

      // 启动核心
      final started = await _platformChannel.startCore(configPath);
      if (!started) {
        VortexLogger.w('Failed to start temp core for delay test');
        _isTempCoreRunning = false;
        _platformChannel.setSilentMode(false);
        return -1;
      }

      // 等待核心启动完成
      await Future.delayed(const Duration(milliseconds: 1500));

      // 验证核心已启动
      final isHealthy = await _mihomoService.healthCheck();
      if (!isHealthy) {
        VortexLogger.w('Temp core health check failed');
        await _platformChannel.stopCore();
        _isTempCoreRunning = false;
        _platformChannel.setSilentMode(false);
        return -1;
      }

      // 测试延迟
      final delay = await _mihomoService.testProxyDelay(
        node.name,
        timeout: timeout,
      );

      return delay ?? -1;
    } catch (e) {
      VortexLogger.e('Delay test with temp core failed', e);
      return -1;
    }
  }

  /// 停止临时核心（测试完成后调用）
  Future<void> stopTempCoreIfRunning() async {
    if (_isTempCoreRunning && !isConnected) {
      VortexLogger.i('Stopping temp core...');
      try {
        await _platformChannel.stopCore().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            VortexLogger.w('Stop temp core timed out, forcing...');
            return false;
          },
        );
      } catch (e) {
        VortexLogger.e('Failed to stop temp core', e);
      }
      _isTempCoreRunning = false;
      // 关闭静默模式
      _platformChannel.setSilentMode(false);
    }
  }

  /// 生成用于延迟测试的配置（不启用系统代理）
  Future<String> _writeDelayTestConfig() async {
    final configDir = await _ensureConfigDirectory();
    final configPath = '$configDir/delay_test_config.yaml';

    final buffer = StringBuffer();

    // 基础配置
    buffer.writeln('# Vortex Delay Test Config');
    buffer.writeln('port: $_httpPort');
    buffer.writeln('socks-port: $_socksPort');
    buffer.writeln('mixed-port: $_mixedPort');
    buffer.writeln('allow-lan: false');
    buffer.writeln('mode: rule');
    buffer.writeln('log-level: warning');
    buffer.writeln('external-controller: 127.0.0.1:$_controllerPort');
    if (_controllerSecret.isNotEmpty) {
      buffer.writeln('secret: $_controllerSecret');
    }
    // 启用 unified-delay 以获取真实 TLS 延迟
    buffer.writeln('unified-delay: true');
    buffer.writeln('tcp-concurrent: true');
    buffer.writeln();

    // 最小 DNS 配置
    buffer.writeln('dns:');
    buffer.writeln('  enable: true');
    buffer.writeln('  enhanced-mode: fake-ip');
    buffer.writeln('  fake-ip-range: 198.18.0.1/16');
    buffer.writeln('  nameserver:');
    buffer.writeln('    - 8.8.8.8');
    buffer.writeln('    - 1.1.1.1');
    buffer.writeln();

    // 添加所有节点
    buffer.writeln('proxies:');
    for (final node in _nodes) {
      buffer.writeln('  - name: ${node.name}');
      buffer.writeln('    server: ${node.server}');
      buffer.writeln('    port: ${node.port}');
      buffer.writeln('    type: ${_getProxyType(node.protocol)}');

      node.settings.forEach((key, value) {
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
    buffer.writeln();

    // 代理组
    buffer.writeln('proxy-groups:');
    buffer.writeln('  - name: Proxy');
    buffer.writeln('    type: select');
    buffer.writeln('    proxies:');
    for (final node in _nodes) {
      buffer.writeln('      - ${node.name}');
    }
    buffer.writeln();

    // 简单规则 - 全部直连（仅用于测试）
    buffer.writeln('rules:');
    buffer.writeln('  - MATCH,DIRECT');

    final file = File(configPath);
    await file.writeAsString(buffer.toString());

    VortexLogger.d('Delay test config written to: $configPath');
    return configPath;
  }

  /// 测试所有节点延迟 - 真实全链路延迟
  ///
  /// 通过 Mihomo API 批量测试所有节点的真实代理延迟
  /// 如果核心未运行，会临时启动核心进行测试
  ///
  /// [timeout] 每个节点的测试超时时间（毫秒）
  /// [onProgress] 测试进度回调，参数为 (完成数, 总数, 当前节点ID, 延迟)
  Future<Map<String, int>> testAllNodesDelay({
    int timeout = 10000,
    void Function(int completed, int total, String nodeId, int delay)?
    onProgress,
  }) async {
    final results = <String, int>{};

    if (_nodes.isEmpty) {
      VortexLogger.w('No nodes to test');
      return results;
    }

    VortexLogger.i('testAllNodesDelay: Starting with ${_nodes.length} nodes');

    // 确保核心运行中
    final needStopCore = !isConnected && !_isTempCoreRunning;
    if (!isConnected && !_isTempCoreRunning) {
      VortexLogger.i('testAllNodesDelay: Need to start temp core...');
      _isTempCoreRunning = true;

      // 启用静默模式，防止状态变化影响主 UI
      _platformChannel.setSilentMode(true);
      VortexLogger.i('testAllNodesDelay: Silent mode enabled');

      try {
        VortexLogger.i('testAllNodesDelay: Writing delay test config...');
        final configPath = await _writeDelayTestConfig();
        VortexLogger.i('testAllNodesDelay: Config written to $configPath');

        VortexLogger.i('testAllNodesDelay: Starting core...');
        final started = await _platformChannel.startCore(configPath);
        VortexLogger.i('testAllNodesDelay: Core started = $started');

        if (!started) {
          VortexLogger.w('Failed to start temp core');
          _isTempCoreRunning = false;
          _platformChannel.setSilentMode(false);
          return results;
        }

        // 等待核心启动
        VortexLogger.i('testAllNodesDelay: Waiting for core to initialize...');
        await Future.delayed(const Duration(milliseconds: 1500));

        VortexLogger.i('testAllNodesDelay: Checking core health...');
        final isHealthy = await _mihomoService.healthCheck();
        VortexLogger.i('testAllNodesDelay: Core healthy = $isHealthy');

        if (!isHealthy) {
          VortexLogger.w('Temp core health check failed');
          await _platformChannel.stopCore();
          _isTempCoreRunning = false;
          _platformChannel.setSilentMode(false);
          return results;
        }
      } catch (e) {
        VortexLogger.e('Failed to start temp core for batch test', e);
        _isTempCoreRunning = false;
        _platformChannel.setSilentMode(false);
        return results;
      }
    }

    VortexLogger.i('testAllNodesDelay: Starting batch delay tests...');

    // 批量测试（并发限制为 3，减少负载）
    const batchSize = 3;
    int completed = 0;
    final total = _nodes.length;

    for (var i = 0; i < _nodes.length; i += batchSize) {
      final batch = _nodes.skip(i).take(batchSize).toList();

      // 使用 try-catch 包装每个批次，防止单个失败导致整体失败
      try {
        final futures = batch.map((node) async {
          try {
            final delay = await _mihomoService
                .testProxyDelay(node.name, timeout: timeout)
                .timeout(
                  Duration(milliseconds: timeout + 3000),
                  onTimeout: () {
                    VortexLogger.w('Delay test timeout for ${node.name}');
                    return null;
                  },
                );
            return MapEntry(node.id, delay ?? -1);
          } catch (e) {
            VortexLogger.w('Delay test error for ${node.name}: $e');
            return MapEntry(node.id, -1);
          }
        });

        final batchResults = await Future.wait(futures);
        for (final entry in batchResults) {
          results[entry.key] = entry.value;
          completed++;
          onProgress?.call(completed, total, entry.key, entry.value);
        }
      } catch (e) {
        VortexLogger.e('Batch test error at index $i', e);
        // 继续下一批
      }

      // 每批次之间让出一点时间给 UI 线程
      await Future.delayed(const Duration(milliseconds: 50));
    }

    VortexLogger.i('testAllNodesDelay: Batch tests completed');

    // 如果是临时启动的核心，停止它
    if (needStopCore && _isTempCoreRunning) {
      VortexLogger.i('testAllNodesDelay: Stopping temp core...');
      try {
        await _platformChannel.stopCore().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            VortexLogger.w('Stop core timed out after batch test');
            return false;
          },
        );
      } catch (e) {
        VortexLogger.e('Failed to stop core after batch test', e);
      }
      _isTempCoreRunning = false;
      // 关闭静默模式
      _platformChannel.setSilentMode(false);
      VortexLogger.i('testAllNodesDelay: Silent mode disabled');
    }

    VortexLogger.i('Batch delay test completed: ${results.length} nodes');
    return results;
  }

  /// 测试所有节点延迟（假设核心已在运行）
  ///
  /// 这是一个简化版本，不会启动或停止核心
  /// 用于核心已预启动或已连接VPN的情况
  Future<Map<String, int>> testAllNodesDelayWithRunningCore({
    int timeout = 10000,
    void Function(int completed, int total, String nodeId, int delay)?
    onProgress,
  }) async {
    final results = <String, int>{};

    if (_nodes.isEmpty) {
      VortexLogger.w('No nodes to test');
      return results;
    }

    VortexLogger.i(
      'testAllNodesDelayWithRunningCore: Testing ${_nodes.length} nodes',
    );

    // 批量测试（并发限制为 5）
    const batchSize = 5;
    int completed = 0;
    final total = _nodes.length;

    for (var i = 0; i < _nodes.length; i += batchSize) {
      final batch = _nodes.skip(i).take(batchSize).toList();

      try {
        final futures = batch.map((node) async {
          try {
            final delay = await _mihomoService
                .testProxyDelay(node.name, timeout: timeout)
                .timeout(
                  Duration(milliseconds: timeout + 3000),
                  onTimeout: () {
                    VortexLogger.w('Delay test timeout for ${node.name}');
                    return null;
                  },
                );
            return MapEntry(node.id, delay ?? -1);
          } catch (e) {
            VortexLogger.w('Delay test error for ${node.name}: $e');
            return MapEntry(node.id, -1);
          }
        });

        final batchResults = await Future.wait(futures);
        for (final entry in batchResults) {
          results[entry.key] = entry.value;
          completed++;
          onProgress?.call(completed, total, entry.key, entry.value);
        }
      } catch (e) {
        VortexLogger.e('Batch test error at index $i', e);
      }

      // 让出时间给 UI 线程
      await Future.delayed(const Duration(milliseconds: 20));
    }

    VortexLogger.i(
      'testAllNodesDelayWithRunningCore completed: ${results.length} nodes',
    );
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
    // 启用 unified-delay 以获取真实 TLS 延迟
    // 参考 Clash for Windows, Clash Verge Rev, FlClash 的实现
    buffer.writeln('unified-delay: true');
    buffer.writeln('tcp-concurrent: true');
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
