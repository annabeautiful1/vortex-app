/// Application constants
class AppConstants {
  AppConstants._();

  // App Info
  static const String appName = 'Vortex';
  static const String appNameCn = '漩涡';
  static const String appDescription = 'Modern Cross-Platform VPN Client';
  static const String appVersion = '1.0.0';

  // API Endpoints
  static const Duration apiTimeout = Duration(seconds: 30);
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration pingTimeout = Duration(seconds: 5);

  // Storage Keys
  static const String tokenKey = 'auth_token';
  static const String userKey = 'user_data';
  static const String serverListKey = 'server_list';
  static const String settingsKey = 'app_settings';
  static const String themeKey = 'theme_mode';
  static const String apiEndpointsKey = 'api_endpoints';
  static const String savedEmailKey = 'saved_email';
  static const String savedPasswordKey = 'saved_password';

  // Panel Types
  static const String panelSSPanel = 'sspanel';
  static const String panelV2Board = 'v2board';

  // Subscription Types for V2Board
  static const String subTypeClashMeta = 'clashmeta'; // For V2board 1.7.1-1.7.3
  static const String subTypeMeta = 'meta'; // For V2board 1.7.4

  // SSPanel Guest Config
  static const String sspanelGuestConfig = '/guest_config.txt';
  static const String v2boardGuestConfig = '/api/v1/guest/comm/config';

  // Log Paths (platform specific)
  static const String logFolderName = 'com.vortex.helper';

  // Supported Protocols
  static const List<String> supportedProtocols = [
    'shadowsocks',
    'shadowsocksr',
    'vmess',
    'vless',
    'trojan',
    'hysteria',
    'hysteria2',
    'tuic',
    'wireguard',
    'anytls',
  ];

  // Animation Durations
  static const Duration shortAnimation = Duration(milliseconds: 200);
  static const Duration mediumAnimation = Duration(milliseconds: 350);
  static const Duration longAnimation = Duration(milliseconds: 500);
}

/// Error Messages
class ErrorMessages {
  ErrorMessages._();

  static const String queryingBackend = '查询有效后端';
  static const String noValidApi = '无可用 API 或 API 全部测活失败';
  static const String subscriptionFailed = '订阅拉取失败';
  static const String noNodes = '无可用节点';
  static const String coreNotStarted = '核心未启动';
  static const String networkError = '网络错误，请检查连接';
  static const String pleaseWait = '请等待';
  static const String descriptionNotLoaded = '简介未加载';
}

/// Help Messages for common issues
class HelpMessages {
  HelpMessages._();

  static const String queryingBackendHelp = '''
如果遇到"查询有效后端"的问题，表明无可用 API 或 API 全部测活失败。
此时可先查看对应客户端的日志排查问题。
或者检查打包后台和 OSS 内的 API 地址测活是否正常：
- V2board: http(s)://API地址/api/v1/guest/comm/config
- SSPanel/WHMCS: http(s)://API地址/guest_config.txt
''';

  static const String subscriptionHelp = '''
如果遇到订阅无法正常拉取或无节点或只有 DIRECT、REJECT 两个节点：
1. 检查订阅链接的国内连接性
2. 检查是否有 Vortex 不支持的字段（如 GEOSITE）
3. 配置文件过大时，建议使用 rule-provider 规则集
''';

  static const String networkHelp = '''
如遇到电脑直接断电关机等，重启后无法连接网络：
1. 检查系统代理是否已被恢复
2. 打开 Vortex 客户端会自动修复系统代理
3. 建议勾选"开机启动"避免网络问题
''';

  static const String coreNotStartedHelp = '''
如果提示"请等待"或左下角简介未加载，核心可能未启动：
- macOS: 其他软件（surge/clashx）后台占用，卸载后重启
- Windows: 杀毒软件干扰，关闭后重新安装
- 注意区分 Intel 和 M 芯片的 macOS 版本
''';
}
