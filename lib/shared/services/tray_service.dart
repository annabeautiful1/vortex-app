import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

import '../../core/utils/logger.dart';

/// Proxy mode enum
enum ProxyMode { rule, global, direct }

/// Tray service for desktop platforms
class TrayService with TrayListener {
  static final TrayService _instance = TrayService._internal();
  static TrayService get instance => _instance;

  TrayService._internal();

  bool _isInitialized = false;

  // Callbacks
  VoidCallback? onShowDashboard;
  void Function(ProxyMode)? onProxyModeChanged;
  VoidCallback? onUpdateSubscription;
  void Function(bool)? onSystemProxyChanged;
  void Function(bool)? onTunModeChanged;
  VoidCallback? onOpenConfigDir;
  VoidCallback? onOpenCoreDir;
  VoidCallback? onOpenLogDir;
  VoidCallback? onRestartCore;
  VoidCallback? onRestartApp;
  VoidCallback? onQuitApp;

  // State
  ProxyMode _proxyMode = ProxyMode.rule;
  bool _systemProxyEnabled = false;
  bool _tunModeEnabled = false;
  String _version = '1.0.0';

  /// Initialize tray
  Future<void> init({
    String version = '1.0.0',
    ProxyMode initialProxyMode = ProxyMode.rule,
    bool initialSystemProxy = false,
    bool initialTunMode = false,
  }) async {
    if (_isInitialized) return;
    if (!_isDesktop) return;

    _version = version;
    _proxyMode = initialProxyMode;
    _systemProxyEnabled = initialSystemProxy;
    _tunModeEnabled = initialTunMode;

    try {
      trayManager.addListener(this);

      // Set tray icon
      String iconPath;
      if (Platform.isWindows) {
        iconPath = 'assets/icons/app_icon.ico';
      } else if (Platform.isMacOS) {
        iconPath = 'assets/icons/app_icon.png';
      } else {
        iconPath = 'assets/icons/app_icon.png';
      }

      await trayManager.setIcon(iconPath);
      await trayManager.setToolTip('Vortex - 漩涡');
      await _updateMenu();

      _isInitialized = true;
      VortexLogger.i('Tray service initialized');
    } catch (e) {
      VortexLogger.e('Failed to initialize tray', e);
    }
  }

  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// Update tray menu
  Future<void> _updateMenu() async {
    final menu = Menu(
      items: [
        MenuItem(label: '仪表盘', key: 'dashboard'),
        MenuItem.separator(),
        MenuItem.submenu(
          label: '代理模式',
          submenu: Menu(
            items: [
              MenuItem.checkbox(
                label: '规则模式',
                key: 'mode_rule',
                checked: _proxyMode == ProxyMode.rule,
              ),
              MenuItem.checkbox(
                label: '全局模式',
                key: 'mode_global',
                checked: _proxyMode == ProxyMode.global,
              ),
              MenuItem.checkbox(
                label: '直连模式',
                key: 'mode_direct',
                checked: _proxyMode == ProxyMode.direct,
              ),
            ],
          ),
        ),
        MenuItem.separator(),
        MenuItem(label: '更新订阅', key: 'update_subscription'),
        MenuItem.checkbox(
          label: '系统代理',
          key: 'system_proxy',
          checked: _systemProxyEnabled,
        ),
        MenuItem.checkbox(
          label: 'TUN 模式',
          key: 'tun_mode',
          checked: _tunModeEnabled,
        ),
        MenuItem.separator(),
        MenuItem.submenu(
          label: '打开目录',
          submenu: Menu(
            items: [
              MenuItem(label: '配置目录', key: 'open_config'),
              MenuItem(label: '核心目录', key: 'open_core'),
              MenuItem(label: '日志目录', key: 'open_log'),
            ],
          ),
        ),
        MenuItem.separator(),
        MenuItem(label: '重启核心', key: 'restart_core'),
        MenuItem(label: '重启应用', key: 'restart_app'),
        MenuItem.separator(),
        MenuItem(label: '版本号: $_version', disabled: true),
        MenuItem.separator(),
        MenuItem(label: '退出', key: 'quit'),
      ],
    );

    await trayManager.setContextMenu(menu);
  }

  /// Update proxy mode
  Future<void> setProxyMode(ProxyMode mode) async {
    _proxyMode = mode;
    await _updateMenu();
  }

  /// Update system proxy state
  Future<void> setSystemProxyEnabled(bool enabled) async {
    _systemProxyEnabled = enabled;
    await _updateMenu();
  }

  /// Update TUN mode state
  Future<void> setTunModeEnabled(bool enabled) async {
    _tunModeEnabled = enabled;
    await _updateMenu();
  }

  /// Update version
  Future<void> setVersion(String version) async {
    _version = version;
    await _updateMenu();
  }

  @override
  void onTrayIconMouseDown() {
    // Show window on click
    _showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'dashboard':
        _showWindow();
        onShowDashboard?.call();
        break;
      case 'mode_rule':
        _proxyMode = ProxyMode.rule;
        _updateMenu();
        onProxyModeChanged?.call(ProxyMode.rule);
        break;
      case 'mode_global':
        _proxyMode = ProxyMode.global;
        _updateMenu();
        onProxyModeChanged?.call(ProxyMode.global);
        break;
      case 'mode_direct':
        _proxyMode = ProxyMode.direct;
        _updateMenu();
        onProxyModeChanged?.call(ProxyMode.direct);
        break;
      case 'update_subscription':
        onUpdateSubscription?.call();
        break;
      case 'system_proxy':
        _systemProxyEnabled = !_systemProxyEnabled;
        _updateMenu();
        onSystemProxyChanged?.call(_systemProxyEnabled);
        break;
      case 'tun_mode':
        _tunModeEnabled = !_tunModeEnabled;
        _updateMenu();
        onTunModeChanged?.call(_tunModeEnabled);
        break;
      case 'open_config':
        onOpenConfigDir?.call();
        _openConfigDirectory();
        break;
      case 'open_core':
        onOpenCoreDir?.call();
        _openCoreDirectory();
        break;
      case 'open_log':
        onOpenLogDir?.call();
        _openLogDirectory();
        break;
      case 'restart_core':
        onRestartCore?.call();
        break;
      case 'restart_app':
        onRestartApp?.call();
        break;
      case 'quit':
        onQuitApp?.call();
        _quit();
        break;
    }
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _openConfigDirectory() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final configDir = path.join(dir.path, 'config');
      await Directory(configDir).create(recursive: true);
      _openDirectory(configDir);
    } catch (e) {
      VortexLogger.e('Failed to open config directory', e);
    }
  }

  Future<void> _openCoreDirectory() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _openDirectory(dir.path);
    } catch (e) {
      VortexLogger.e('Failed to open core directory', e);
    }
  }

  Future<void> _openLogDirectory() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final logDir = path.join(dir.path, 'logs');
      await Directory(logDir).create(recursive: true);
      _openDirectory(logDir);
    } catch (e) {
      VortexLogger.e('Failed to open log directory', e);
    }
  }

  void _openDirectory(String dirPath) {
    if (Platform.isWindows) {
      Process.run('explorer', [dirPath]);
    } else if (Platform.isMacOS) {
      Process.run('open', [dirPath]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [dirPath]);
    }
  }

  Future<void> _quit() async {
    await trayManager.destroy();
    exit(0);
  }

  /// Dispose tray
  Future<void> dispose() async {
    if (!_isInitialized) return;
    trayManager.removeListener(this);
    await trayManager.destroy();
    _isInitialized = false;
  }
}
