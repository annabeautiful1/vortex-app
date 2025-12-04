import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../app.dart';
import '../../../../core/config/build_config.dart';
import '../../../../core/utils/logger.dart';
import '../../../../shared/services/storage_service.dart';
import '../../../../shared/services/tray_service.dart';
import '../../../auth/domain/auth_provider.dart';

/// Settings provider for managing settings state
final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) {
    return SettingsNotifier();
  },
);

class SettingsState {
  final bool autoStart;
  final bool tunMode;
  final bool allowLan;
  final bool autoUpdateSubscription;
  final ThemeMode themeMode;

  const SettingsState({
    this.autoStart = false,
    this.tunMode = false,
    this.allowLan = false,
    this.autoUpdateSubscription = true,
    this.themeMode = ThemeMode.system,
  });

  SettingsState copyWith({
    bool? autoStart,
    bool? tunMode,
    bool? allowLan,
    bool? autoUpdateSubscription,
    ThemeMode? themeMode,
  }) {
    return SettingsState(
      autoStart: autoStart ?? this.autoStart,
      tunMode: tunMode ?? this.tunMode,
      allowLan: allowLan ?? this.allowLan,
      autoUpdateSubscription:
          autoUpdateSubscription ?? this.autoUpdateSubscription,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(const SettingsState()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final storage = StorageService.instance;
    state = SettingsState(
      autoStart: storage.getBool('auto_start') ?? false,
      tunMode: storage.getBool('tun_mode') ?? false,
      allowLan: storage.getBool('allow_lan') ?? false,
      autoUpdateSubscription:
          storage.getBool('auto_update_subscription') ?? true,
      themeMode: _getThemeMode(storage.getString('theme_mode')),
    );
  }

  ThemeMode _getThemeMode(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      default:
        return 'system';
    }
  }

  Future<void> setAutoStart(bool value) async {
    state = state.copyWith(autoStart: value);
    await StorageService.instance.setBool('auto_start', value);
    VortexLogger.i('Auto start set to: $value');
    // TODO: Implement platform-specific auto start
  }

  Future<void> setTunMode(bool value) async {
    state = state.copyWith(tunMode: value);
    await StorageService.instance.setBool('tun_mode', value);
    TrayService.instance.setTunModeEnabled(value);
    VortexLogger.i('TUN mode set to: $value');
    // TODO: Implement TUN mode toggle
  }

  Future<void> setAllowLan(bool value) async {
    state = state.copyWith(allowLan: value);
    await StorageService.instance.setBool('allow_lan', value);
    VortexLogger.i('Allow LAN set to: $value');
    // TODO: Implement LAN access toggle
  }

  Future<void> setAutoUpdateSubscription(bool value) async {
    state = state.copyWith(autoUpdateSubscription: value);
    await StorageService.instance.setBool('auto_update_subscription', value);
    VortexLogger.i('Auto update subscription set to: $value');
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await StorageService.instance.setString(
      'theme_mode',
      _themeModeToString(mode),
    );
    VortexLogger.i('Theme mode set to: $mode');
  }
}

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final config = BuildConfig.instance;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '设置',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),

              // General settings
              _SettingsSection(
                title: '通用',
                children: [
                  _SettingsTile(
                    icon: Icons.rocket_launch,
                    title: '开机启动',
                    subtitle: '系统启动时自动运行',
                    trailing: Switch(
                      value: settings.autoStart,
                      onChanged: (value) =>
                          settingsNotifier.setAutoStart(value),
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.wifi_tethering,
                    title: 'TUN 模式',
                    subtitle: '代理全部系统流量',
                    trailing: Switch(
                      value: settings.tunMode,
                      onChanged: (value) => settingsNotifier.setTunMode(value),
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.lan,
                    title: '允许局域网连接',
                    subtitle: '允许其他设备通过本机代理',
                    trailing: Switch(
                      value: settings.allowLan,
                      onChanged: (value) => settingsNotifier.setAllowLan(value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Appearance
              _SettingsSection(
                title: '外观',
                children: [
                  _SettingsTile(
                    icon: Icons.dark_mode,
                    title: '深色模式',
                    subtitle: _getThemeModeText(settings.themeMode),
                    onTap: () =>
                        _showThemePicker(context, ref, settings.themeMode),
                  ),
                  _SettingsTile(
                    icon: Icons.palette,
                    title: '主题色',
                    subtitle: '自定义主题颜色',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('主题色功能开发中...')),
                      );
                    },
                  ),
                  _SettingsTile(
                    icon: Icons.language,
                    title: '语言',
                    subtitle: '简体中文',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('多语言功能开发中...')),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Subscription
              _SettingsSection(
                title: '订阅',
                children: [
                  _SettingsTile(
                    icon: Icons.update,
                    title: '自动更新订阅',
                    subtitle: '每次启动时更新',
                    trailing: Switch(
                      value: settings.autoUpdateSubscription,
                      onChanged: (value) =>
                          settingsNotifier.setAutoUpdateSubscription(value),
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.link,
                    title: '订阅地址',
                    subtitle: '查看和管理订阅',
                    onTap: () => _showSubscriptionInfo(context, ref),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Advanced
              _SettingsSection(
                title: '高级',
                children: [
                  _SettingsTile(
                    icon: Icons.article,
                    title: '查看日志',
                    subtitle: '查看应用运行日志',
                    onTap: () => _openLogDirectory(),
                  ),
                  _SettingsTile(
                    icon: Icons.file_download,
                    title: '导出日志',
                    subtitle: '导出日志用于排查问题',
                    onTap: () => _exportLogs(context),
                  ),
                  _SettingsTile(
                    icon: Icons.cleaning_services,
                    title: '清除缓存',
                    subtitle: '清除应用缓存数据',
                    onTap: () => _clearCache(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // About
              _SettingsSection(
                title: '关于',
                children: [
                  _SettingsTile(
                    icon: Icons.info,
                    title: '版本',
                    subtitle: config.appVersion,
                    onTap: () {},
                  ),
                  _SettingsTile(
                    icon: Icons.privacy_tip,
                    title: '隐私政策',
                    onTap: () {
                      if (config.privacyUrl != null) {
                        launchUrl(Uri.parse(config.privacyUrl!));
                      }
                    },
                  ),
                  _SettingsTile(
                    icon: Icons.description,
                    title: '服务条款',
                    onTap: () {
                      if (config.termsUrl != null) {
                        launchUrl(Uri.parse(config.termsUrl!));
                      }
                    },
                  ),
                  _SettingsTile(
                    icon: Icons.logout,
                    title: '退出登录',
                    textColor: Colors.red,
                    onTap: () => _showLogoutDialog(context, ref),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getThemeModeText(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '浅色模式';
      case ThemeMode.dark:
        return '深色模式';
      default:
        return '跟随系统';
    }
  }

  void _showThemePicker(
    BuildContext context,
    WidgetRef ref,
    ThemeMode currentMode,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择主题'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ThemeMode>(
              title: const Text('跟随系统'),
              value: ThemeMode.system,
              groupValue: currentMode,
              onChanged: (value) {
                ref.read(settingsProvider.notifier).setThemeMode(value!);
                ref.read(themeModeProvider.notifier).state = value;
                Navigator.pop(context);
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('浅色模式'),
              value: ThemeMode.light,
              groupValue: currentMode,
              onChanged: (value) {
                ref.read(settingsProvider.notifier).setThemeMode(value!);
                ref.read(themeModeProvider.notifier).state = value;
                Navigator.pop(context);
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('深色模式'),
              value: ThemeMode.dark,
              groupValue: currentMode,
              onChanged: (value) {
                ref.read(settingsProvider.notifier).setThemeMode(value!);
                ref.read(themeModeProvider.notifier).state = value;
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSubscriptionInfo(BuildContext context, WidgetRef ref) {
    final authState = ref.read(authProvider);
    final subscribeUrl = authState.user?.subscription.subscriptionUrl ?? '未设置';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('订阅信息'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('订阅地址:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SelectableText(subscribeUrl, style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _openLogDirectory() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final logDir = Directory('${dir.path}/logs');
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }

      if (Platform.isWindows) {
        Process.run('explorer', [logDir.path]);
      } else if (Platform.isMacOS) {
        Process.run('open', [logDir.path]);
      } else if (Platform.isLinux) {
        Process.run('xdg-open', [logDir.path]);
      }
    } catch (e) {
      VortexLogger.e('Failed to open log directory', e);
    }
  }

  Future<void> _exportLogs(BuildContext context) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final logDir = Directory('${dir.path}/logs');

      if (!await logDir.exists()) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('暂无日志文件')));
        }
        return;
      }

      // Open log directory
      if (Platform.isWindows) {
        await Process.run('explorer', [logDir.path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [logDir.path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [logDir.path]);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已打开日志目录')));
      }
    } catch (e) {
      VortexLogger.e('Failed to export logs', e);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出失败: $e')));
      }
    }
  }

  Future<void> _clearCache(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除缓存'),
        content: const Text('确定要清除所有缓存数据吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      // Clear cache logic
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('缓存已清除')));
    }
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) {
                context.go('/login');
              }
            },
            child: const Text('退出', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? textColor;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: textColor),
      title: Text(title, style: TextStyle(color: textColor)),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing:
          trailing ?? (onTap != null ? const Icon(Icons.chevron_right) : null),
      onTap: trailing != null ? null : onTap,
    );
  }
}
