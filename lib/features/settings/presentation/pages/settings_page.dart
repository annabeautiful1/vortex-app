import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
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
                      value: false,
                      onChanged: (value) {},
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.wifi_tethering,
                    title: 'TUN 模式',
                    subtitle: '代理全部系统流量',
                    trailing: Switch(
                      value: false,
                      onChanged: (value) {},
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.lan,
                    title: '允许局域网连接',
                    subtitle: '允许其他设备通过本机代理',
                    trailing: Switch(
                      value: false,
                      onChanged: (value) {},
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
                    subtitle: '跟随系统',
                    onTap: () {
                      // Show theme picker
                    },
                  ),
                  _SettingsTile(
                    icon: Icons.palette,
                    title: '主题色',
                    subtitle: '自定义主题颜色',
                    onTap: () {
                      // Show color picker
                    },
                  ),
                  _SettingsTile(
                    icon: Icons.language,
                    title: '语言',
                    subtitle: '简体中文',
                    onTap: () {
                      // Show language picker
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
                      value: true,
                      onChanged: (value) {},
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.link,
                    title: '订阅地址',
                    subtitle: '查看和管理订阅',
                    onTap: () {},
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
                    onTap: () {},
                  ),
                  _SettingsTile(
                    icon: Icons.file_download,
                    title: '导出日志',
                    subtitle: '导出日志用于排查问题',
                    onTap: () {},
                  ),
                  _SettingsTile(
                    icon: Icons.cleaning_services,
                    title: '清除缓存',
                    subtitle: '清除应用缓存数据',
                    onTap: () {},
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
                    subtitle: '1.0.0',
                    onTap: () {},
                  ),
                  _SettingsTile(
                    icon: Icons.privacy_tip,
                    title: '隐私政策',
                    onTap: () {},
                  ),
                  _SettingsTile(
                    icon: Icons.description,
                    title: '服务条款',
                    onTap: () {},
                  ),
                  _SettingsTile(
                    icon: Icons.logout,
                    title: '退出登录',
                    textColor: Colors.red,
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.children,
  });

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
          child: Column(
            children: children,
          ),
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
      title: Text(
        title,
        style: TextStyle(color: textColor),
      ),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_right) : null),
      onTap: onTap,
    );
  }
}
