import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

import '../../shared/constants/app_constants.dart';
import '../utils/logger.dart';
import '../utils/dev_mode.dart';

/// Panel type enum for build configuration
enum BuildPanelType { v2board, sspanel }

/// Build configuration loaded from build_config.yaml
/// This configuration is set at build time and cannot be changed at runtime
class BuildConfig {
  // Singleton instance
  static BuildConfig? _instance;
  static BuildConfig get instance {
    if (_instance == null) {
      throw StateError(
        'BuildConfig not initialized. Call BuildConfig.load() first.',
      );
    }
    return _instance!;
  }

  // Basic Info
  final String appName;
  final String appNameCn;

  // Panel Configuration
  final BuildPanelType panelType;
  final String subscriptionType;

  // API Configuration
  final List<String> apiEndpoints;
  final List<String> ossEndpoints;
  final int cloudUpdateInterval; // hours
  final List<String> dnsTxtDomains;

  // Proxy Configuration
  final List<String> builtinProxies;
  final bool disableDirect;

  // Client Configuration
  final String userAgent;

  // Links
  final String homepageUrl;
  final String supportUrl;
  final String telegramUrl;

  const BuildConfig._({
    required this.appName,
    required this.appNameCn,
    required this.panelType,
    required this.subscriptionType,
    required this.apiEndpoints,
    required this.ossEndpoints,
    required this.cloudUpdateInterval,
    required this.dnsTxtDomains,
    required this.builtinProxies,
    required this.disableDirect,
    required this.userAgent,
    required this.homepageUrl,
    required this.supportUrl,
    required this.telegramUrl,
  });

  /// Load build configuration from assets
  static Future<BuildConfig> load() async {
    if (_instance != null) {
      return _instance!;
    }

    try {
      DevMode.instance.log('BuildConfig', '开始加载 build_config.yaml');
      final yamlString = await rootBundle.loadString('build_config.yaml');
      DevMode.instance.log(
        'BuildConfig',
        'YAML 文件加载成功',
        detail: '长度: ${yamlString.length}',
      );

      final yaml = loadYaml(yamlString) as YamlMap;
      DevMode.instance.log('BuildConfig', 'YAML 解析成功');

      _instance = BuildConfig._(
        appName: _getString(yaml, 'app_name', 'Vortex'),
        appNameCn: _getString(yaml, 'app_name_cn', '漩涡'),
        panelType: _getPanelType(yaml),
        subscriptionType: _getString(yaml, 'subscription_type', ''),
        apiEndpoints: _getStringList(yaml, 'api_endpoints'),
        ossEndpoints: _getStringList(yaml, 'oss_endpoints'),
        cloudUpdateInterval: _getInt(yaml, 'cloud_update_interval', 24),
        dnsTxtDomains: _getStringList(yaml, 'dns_txt_domains'),
        builtinProxies: _getStringList(yaml, 'builtin_proxies'),
        disableDirect: _getBool(yaml, 'disable_direct', false),
        userAgent: _getString(yaml, 'user_agent', ''),
        homepageUrl: _getString(yaml, 'homepage_url', ''),
        supportUrl: _getString(yaml, 'support_url', ''),
        telegramUrl: _getString(yaml, 'telegram_url', ''),
      );

      VortexLogger.i(
        'BuildConfig loaded: ${_instance!.appName} (${_instance!.panelType.name})',
      );
      VortexLogger.i('API endpoints: ${_instance!.apiEndpoints.length}');

      // 详细的调试日志
      DevMode.instance.log(
        'BuildConfig',
        '配置加载完成',
        detail:
            '''
应用名称: ${_instance!.appName}
中文名称: ${_instance!.appNameCn}
面板类型: ${_instance!.panelType.name}
订阅类型: ${_instance!.subscriptionType.isEmpty ? '(未设置)' : _instance!.subscriptionType}
API 地址数量: ${_instance!.apiEndpoints.length}
API 地址列表: ${_instance!.apiEndpoints.join(', ')}''',
      );

      return _instance!;
    } catch (e, stack) {
      VortexLogger.e('Failed to load build_config.yaml', e);
      DevMode.instance.error('BuildConfig', '加载配置文件失败', e, stack);

      // Return default configuration
      _instance = const BuildConfig._(
        appName: 'Vortex',
        appNameCn: '漩涡',
        panelType: BuildPanelType.v2board,
        subscriptionType: '',
        apiEndpoints: [],
        ossEndpoints: [],
        cloudUpdateInterval: 24,
        dnsTxtDomains: [],
        builtinProxies: [],
        disableDirect: false,
        userAgent: '',
        homepageUrl: '',
        supportUrl: '',
        telegramUrl: '',
      );

      DevMode.instance.log('BuildConfig', '使用默认配置', detail: 'API 地址为空，需要手动配置');
      return _instance!;
    }
  }

  /// Get string from yaml with default value
  static String _getString(YamlMap yaml, String key, String defaultValue) {
    final value = yaml[key];
    if (value == null || value.toString().isEmpty) {
      return defaultValue;
    }
    return value.toString();
  }

  /// Get int from yaml with default value
  static int _getInt(YamlMap yaml, String key, int defaultValue) {
    final value = yaml[key];
    if (value == null) {
      return defaultValue;
    }
    if (value is int) {
      return value;
    }
    return int.tryParse(value.toString()) ?? defaultValue;
  }

  /// Get bool from yaml with default value
  static bool _getBool(YamlMap yaml, String key, bool defaultValue) {
    final value = yaml[key];
    if (value == null) {
      return defaultValue;
    }
    if (value is bool) {
      return value;
    }
    return value.toString().toLowerCase() == 'true';
  }

  /// Get string list from yaml
  static List<String> _getStringList(YamlMap yaml, String key) {
    final value = yaml[key];
    if (value == null) {
      return [];
    }
    if (value is YamlList) {
      return value.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    return [];
  }

  /// Get panel type from yaml
  static BuildPanelType _getPanelType(YamlMap yaml) {
    final value = _getString(yaml, 'panel_type', 'v2board').toLowerCase();
    if (value == 'sspanel') {
      return BuildPanelType.sspanel;
    }
    return BuildPanelType.v2board;
  }

  /// Check if this is a V2board panel
  bool get isV2board => panelType == BuildPanelType.v2board;

  /// Check if this is a SSPanel
  bool get isSSPanel => panelType == BuildPanelType.sspanel;

  /// Get the subscription URL suffix based on panel type and subscription type
  /// This is appended to the base subscribe URL
  String get subscriptionSuffix {
    if (subscriptionType.isEmpty) {
      return '';
    }

    if (isV2board) {
      // V2board: append ?type=clashmeta or ?type=meta
      return '&flag=$subscriptionType';
    } else {
      // SSPanel: append clash=1, clash=2, etc.
      return '&clash=$subscriptionType';
    }
  }

  /// Get guest config endpoint for the panel type
  String get guestConfigEndpoint {
    if (isV2board) {
      return AppConstants.v2boardGuestConfig;
    }
    return AppConstants.sspanelGuestConfig;
  }

  /// Get effective User-Agent
  String get effectiveUserAgent {
    if (userAgent.isNotEmpty) {
      return userAgent;
    }
    return 'Vortex/${AppConstants.appVersion}';
  }

  /// Check if has API endpoints configured
  bool get hasApiEndpoints => apiEndpoints.isNotEmpty;

  /// Check if has OSS endpoints configured
  bool get hasOssEndpoints => ossEndpoints.isNotEmpty;

  /// Check if has DNS TXT domains configured
  bool get hasDnsTxtDomains => dnsTxtDomains.isNotEmpty;

  /// Check if has builtin proxies configured
  bool get hasBuiltinProxies => builtinProxies.isNotEmpty;

  /// Check if has homepage URL configured
  bool get hasHomepage => homepageUrl.isNotEmpty;

  /// Check if has support URL configured
  bool get hasSupport => supportUrl.isNotEmpty;

  /// Check if has Telegram URL configured
  bool get hasTelegram => telegramUrl.isNotEmpty;
}
