import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'shared/themes/app_theme.dart';
import 'shared/services/tray_service.dart';
import 'core/config/build_config.dart';
import 'core/utils/logger.dart';
import 'core/utils/dev_mode.dart';
import 'core/vpn/vpn_service.dart';
import 'features/auth/domain/auth_provider.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/dashboard/presentation/pages/dashboard_page.dart';
import 'features/nodes/presentation/pages/nodes_page.dart';
import 'features/nodes/domain/nodes_provider.dart';
import 'features/dashboard/domain/connection_provider.dart';
import 'features/settings/presentation/pages/settings_page.dart';
import 'features/support/presentation/pages/support_page.dart';
import 'features/debug/presentation/pages/debug_panel.dart';

/// 创建路由，接受 WidgetRef 用于监听认证状态
GoRouter _createRouter(WidgetRef ref) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: _AuthStateNotifier(ref),
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final isLoggedIn = authState.isAuthenticated;
      final isLoading = authState.isLoading;
      final location = state.uri.path;

      // 如果正在加载认证状态，保持在当前页面
      if (isLoading && location == '/splash') {
        return null;
      }

      // 如果在 splash 页面且不在加载中
      if (location == '/splash') {
        return isLoggedIn ? '/dashboard' : '/login';
      }

      // 如果在登录页但已登录，跳转到 dashboard
      if (location == '/login' && isLoggedIn) {
        return '/dashboard';
      }

      // 如果在受保护的页面但未登录，跳转到登录页
      final protectedPaths = ['/dashboard', '/nodes', '/settings', '/support'];
      if (protectedPaths.any((p) => location.startsWith(p)) && !isLoggedIn) {
        return '/login';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardPage(),
          ),
          GoRoute(
            path: '/nodes',
            builder: (context, state) => const NodesPage(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsPage(),
          ),
          GoRoute(
            path: '/support',
            builder: (context, state) => const SupportPage(),
          ),
        ],
      ),
    ],
  );
}

/// 认证状态变化通知器
class _AuthStateNotifier extends ChangeNotifier {
  _AuthStateNotifier(this._ref) {
    _ref.listen(authProvider, (previous, next) {
      // 当认证状态变化时通知路由刷新
      if (previous?.isAuthenticated != next.isAuthenticated ||
          previous?.isLoading != next.isLoading) {
        notifyListeners();
      }
    });
  }

  final WidgetRef _ref;
}

class VortexApp extends ConsumerStatefulWidget {
  const VortexApp({super.key});

  @override
  ConsumerState<VortexApp> createState() => _VortexAppState();
}

class _VortexAppState extends ConsumerState<VortexApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = _createRouter(ref);
    _setupTrayCallbacks();
  }

  /// 设置托盘回调，确保托盘和设置页面状态同步
  void _setupTrayCallbacks() {
    TrayService.instance.onTunModeChanged = (enabled) {
      // 从托盘更新设置状态
      ref.read(settingsProvider.notifier).setTunModeFromTray(enabled);
    };

    TrayService.instance.onSystemProxyChanged = (enabled) {
      // 系统代理变更回调（如果需要）
      VortexLogger.i('System proxy changed from tray: $enabled');
    };
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final config = BuildConfig.instance;

    return MaterialApp.router(
      title: config.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: _router,
    );
  }
}

// Theme mode provider
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

/// 启动屏幕 - 检查认证状态并加载节点
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  String _statusText = '正在加载...';
  bool _hasError = false;
  String? _errorMessage;

  // 开发者模式触发
  int _logoTapCount = 0;
  DateTime? _lastLogoTap;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  /// 处理 Logo 点击，连续点击 5 次打开调试面板
  void _handleLogoTap() {
    final now = DateTime.now();

    // 如果超过 2 秒没有点击，重置计数
    if (_lastLogoTap != null && now.difference(_lastLogoTap!).inSeconds > 2) {
      _logoTapCount = 0;
    }

    _lastLogoTap = now;
    _logoTapCount++;

    VortexLogger.i('SplashScreen: Logo tapped $_logoTapCount times');

    if (_logoTapCount >= 5) {
      _logoTapCount = 0;
      _openDebugPanel();
    }
  }

  /// 打开调试面板
  void _openDebugPanel() {
    VortexLogger.i('SplashScreen: Opening debug panel');
    DevMode.instance.enable();

    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const DebugPanel()));
  }

  Future<void> _initializeApp() async {
    VortexLogger.i('SplashScreen: Starting initialization...');

    try {
      _updateStatus('正在检查登录状态...');

      // 等待 AuthNotifier 完成初始化（最多 10 秒）
      final authNotifier = ref.read(authProvider.notifier);
      int waitCount = 0;
      const maxWait = 100; // 10 seconds (100 * 100ms)

      while (!authNotifier.isInitialized && waitCount < maxWait) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;

        // 每秒更新一次状态
        if (waitCount % 10 == 0) {
          _updateStatus('正在连接服务器... (${waitCount ~/ 10}s)');
        }
      }

      VortexLogger.i(
        'SplashScreen: Auth initialization completed (waited ${waitCount * 100}ms)',
      );

      // 检查是否超时
      if (!authNotifier.isInitialized) {
        VortexLogger.w('SplashScreen: Auth initialization timed out');
        _updateStatus('连接超时，请检查网络');
      }

      // 如果已登录，加载节点列表
      final authState = ref.read(authProvider);
      VortexLogger.i(
        'SplashScreen: Auth state - isAuthenticated=${authState.isAuthenticated}, isLoading=${authState.isLoading}',
      );

      if (authState.isAuthenticated) {
        _updateStatus('正在加载节点列表...');
        await _loadNodesIfLoggedIn();
      }

      // 路由刷新 - 强制触发跳转
      VortexLogger.i('SplashScreen: Triggering navigation...');
      if (mounted) {
        final authState = ref.read(authProvider);
        if (authState.isAuthenticated) {
          VortexLogger.i('SplashScreen: Navigating to dashboard');
          context.go('/dashboard');
        } else {
          VortexLogger.i('SplashScreen: Navigating to login');
          context.go('/login');
        }
      }
    } catch (e, stack) {
      VortexLogger.e('SplashScreen: Initialization error', e, stack);
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _updateStatus(String status) {
    VortexLogger.i('SplashScreen: $status');
    if (mounted) {
      setState(() {
        _statusText = status;
      });
    }
  }

  Future<void> _loadNodesIfLoggedIn() async {
    try {
      final authState = ref.read(authProvider);
      final subscribeUrl = authState.user?.subscription.subscriptionUrl;

      if (subscribeUrl != null && subscribeUrl.isNotEmpty) {
        VortexLogger.i('Loading nodes from saved subscription...');

        // 获取节点列表
        await ref
            .read(nodesProvider.notifier)
            .refreshNodesFromUrl(subscribeUrl);

        // 将节点列表设置到 VPN 服务
        final nodesState = ref.read(nodesProvider);
        if (nodesState.nodes.isNotEmpty) {
          ref.read(connectionProvider.notifier).setNodes(nodesState.nodes);
          VortexLogger.i('Loaded ${nodesState.nodes.length} nodes on startup');

          // 预启动核心（异步，不阻塞启动流程）
          // 这样测速时核心已经在运行，不需要临时启动
          _startBackgroundCoreAsync();
        }
      }
    } catch (e) {
      VortexLogger.e('Failed to load nodes on startup', e);
    }
  }

  /// 异步预启动核心，不阻塞 UI
  void _startBackgroundCoreAsync() {
    Future.microtask(() async {
      try {
        VortexLogger.i(
          'Pre-starting background core for instant delay testing...',
        );
        await VpnService.instance.startBackgroundCore();
      } catch (e) {
        VortexLogger.e('Failed to pre-start background core', e);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = BuildConfig.instance;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo - 点击 5 次打开调试面板
            GestureDetector(
              onTap: _handleLogoTap,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppTheme.primaryColor, AppTheme.secondaryColor],
                  ),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: const Icon(Icons.cyclone, size: 60, color: Colors.white),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              config.appName,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              config.appNameCn,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 48),
            if (_hasError) ...[
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage ?? '未知错误',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _hasError = false;
                    _errorMessage = null;
                    _statusText = '正在加载...';
                  });
                  _initializeApp();
                },
                child: const Text('重试'),
              ),
            ] else ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                _statusText,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Main shell for navigation
class MainShell extends StatelessWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // 窄屏幕时使用抽屉式导航
        final isNarrow = constraints.maxWidth < 600;

        if (isNarrow) {
          return Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.cyclone,
                      color: AppTheme.primaryColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    BuildConfig.instance.appName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              elevation: 0,
              backgroundColor: theme.colorScheme.surface,
            ),
            drawer: Drawer(child: _buildNavContent(context, theme)),
            body: child,
          );
        }

        // 宽屏幕时使用固定侧边栏
        return Scaffold(
          body: Row(
            children: [
              Container(
                width: 240,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                    right: BorderSide(
                      color: theme.dividerColor.withValues(alpha: 0.1),
                    ),
                  ),
                ),
                child: _buildNavContent(context, theme),
              ),
              Expanded(child: child),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNavContent(BuildContext context, ThemeData theme) {
    return Column(
      children: [
        const SizedBox(height: 32),
        // Logo Area
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.cyclone,
                  color: AppTheme.primaryColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  BuildConfig.instance.appName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // Navigation Items
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                _buildNavItem(
                  context,
                  icon: Icons.dashboard_outlined,
                  activeIcon: Icons.dashboard_rounded,
                  label: '仪表盘',
                  path: '/dashboard',
                ),
                const SizedBox(height: 4),
                _buildNavItem(
                  context,
                  icon: Icons.dns_outlined,
                  activeIcon: Icons.dns_rounded,
                  label: '节点',
                  path: '/nodes',
                ),
                const SizedBox(height: 4),
                _buildNavItem(
                  context,
                  icon: Icons.settings_outlined,
                  activeIcon: Icons.settings_rounded,
                  label: '设置',
                  path: '/settings',
                ),
                const SizedBox(height: 4),
                _buildNavItem(
                  context,
                  icon: Icons.support_agent_outlined,
                  activeIcon: Icons.support_agent_rounded,
                  label: '客服',
                  path: '/support',
                ),
              ],
            ),
          ),
        ),

        // User Profile / Bottom Actions could go here
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required String path,
  }) {
    final location = GoRouterState.of(context).uri.path;
    final isSelected = location.startsWith(path);
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.go(path),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryColor.withOpacity(0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? activeIcon : icon,
                size: 22,
                color: isSelected
                    ? AppTheme.primaryColor
                    : theme.colorScheme.onSurface.withOpacity(0.6),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? AppTheme.primaryColor
                      : theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
