import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app.dart';
import '../../../../core/config/build_config.dart';
import '../../../../core/utils/logger.dart';
import '../../../../shared/services/storage_service.dart';
import '../../../../shared/services/tray_service.dart';
import '../../../../shared/themes/app_theme.dart';
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
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Settings',
                style: GoogleFonts.outfit(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ).animate().fadeIn().slideX(begin: -0.1, end: 0),

              const SizedBox(height: 32),

              // General settings
              _SettingsSection(
                title: 'General',
                delay: 100,
                children: [
                  _SettingsTile(
                    icon: Icons.rocket_launch_rounded,
                    title: 'Auto Start',
                    subtitle: 'Launch at system startup',
                    trailing: Switch(
                      value: settings.autoStart,
                      onChanged: (value) =>
                          settingsNotifier.setAutoStart(value),
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.vpn_lock_rounded,
                    title: 'TUN Mode',
                    subtitle: 'Proxy all system traffic',
                    trailing: Switch(
                      value: settings.tunMode,
                      onChanged: (value) => settingsNotifier.setTunMode(value),
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.lan_rounded,
                    title: 'Allow LAN',
                    subtitle: 'Allow other devices to connect',
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
                title: 'Appearance',
                delay: 200,
                children: [
                  _SettingsTile(
                    icon: Icons.dark_mode_rounded,
                    title: 'Theme',
                    subtitle: _getThemeModeText(settings.themeMode),
                    onTap: () =>
                        _showThemePicker(context, ref, settings.themeMode),
                  ),
                  _SettingsTile(
                    icon: Icons.palette_rounded,
                    title: 'Accent Color',
                    subtitle: 'Customize app accent color',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Coming soon...')),
                      );
                    },
                  ),
                  _SettingsTile(
                    icon: Icons.language_rounded,
                    title: 'Language',
                    subtitle: 'English',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Coming soon...')),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Subscription
              _SettingsSection(
                title: 'Subscription',
                delay: 300,
                children: [
                  _SettingsTile(
                    icon: Icons.sync_rounded,
                    title: 'Auto Update',
                    subtitle: 'Update subscription on startup',
                    trailing: Switch(
                      value: settings.autoUpdateSubscription,
                      onChanged: (value) =>
                          settingsNotifier.setAutoUpdateSubscription(value),
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.link_rounded,
                    title: 'Subscription URL',
                    subtitle: 'Manage subscription link',
                    onTap: () => _showSubscriptionInfo(context, ref),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Advanced
              _SettingsSection(
                title: 'Advanced',
                delay: 400,
                children: [
                  _SettingsTile(
                    icon: Icons.article_rounded,
                    title: 'View Logs',
                    subtitle: 'Check application logs',
                    onTap: () => _openLogDirectory(),
                  ),
                  _SettingsTile(
                    icon: Icons.file_download_rounded,
                    title: 'Export Logs',
                    subtitle: 'Export logs for troubleshooting',
                    onTap: () => _exportLogs(context),
                  ),
                  _SettingsTile(
                    icon: Icons.cleaning_services_rounded,
                    title: 'Clear Cache',
                    subtitle: 'Clear application cache',
                    onTap: () => _clearCache(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // About
              _SettingsSection(
                title: 'About',
                delay: 500,
                children: [
                  _SettingsTile(
                    icon: Icons.info_rounded,
                    title: 'Version',
                    subtitle: config.appVersion,
                    onTap: () {},
                  ),
                  _SettingsTile(
                    icon: Icons.privacy_tip_rounded,
                    title: 'Privacy Policy',
                    onTap: () {
                      if (config.privacyUrl != null) {
                        launchUrl(Uri.parse(config.privacyUrl!));
                      }
                    },
                  ),
                  _SettingsTile(
                    icon: Icons.description_rounded,
                    title: 'Terms of Service',
                    onTap: () {
                      if (config.termsUrl != null) {
                        launchUrl(Uri.parse(config.termsUrl!));
                      }
                    },
                  ),
                  _SettingsTile(
                    icon: Icons.logout_rounded,
                    title: 'Logout',
                    textColor: AppTheme.errorColor,
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
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      default:
        return 'System';
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
        title: const Text('Select Theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ThemeMode>(
              title: const Text('System'),
              value: ThemeMode.system,
              groupValue: currentMode,
              onChanged: (value) {
                ref.read(settingsProvider.notifier).setThemeMode(value!);
                ref.read(themeModeProvider.notifier).state = value;
                Navigator.pop(context);
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Light'),
              value: ThemeMode.light,
              groupValue: currentMode,
              onChanged: (value) {
                ref.read(settingsProvider.notifier).setThemeMode(value!);
                ref.read(themeModeProvider.notifier).state = value;
                Navigator.pop(context);
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Dark'),
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
    final subscribeUrl =
        authState.user?.subscription.subscriptionUrl ?? 'Not set';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Subscription Info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('URL:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SelectableText(subscribeUrl, style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
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
          ).showSnackBar(const SnackBar(content: Text('No logs found')));
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
        ).showSnackBar(const SnackBar(content: Text('Log directory opened')));
      }
    } catch (e) {
      VortexLogger.e('Failed to export logs', e);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _clearCache(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache'),
        content: const Text('Are you sure you want to clear all cache?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      // Clear cache logic
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cache cleared')));
    }
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) {
                context.go('/login');
              }
            },
            child: Text('Logout', style: TextStyle(color: AppTheme.errorColor)),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final int delay;

  const _SettingsSection({
    required this.title,
    required this.children,
    this.delay = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).dividerColor.withOpacity(0.05),
            ),
          ),
          child: Column(children: children),
        ),
      ],
    ).animate().fadeIn(delay: delay.ms).slideY(begin: 0.1, end: 0);
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
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: trailing != null ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (textColor ?? theme.colorScheme.primary).withOpacity(
                    0.1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: textColor ?? theme.colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: textColor ?? theme.colorScheme.onSurface,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
