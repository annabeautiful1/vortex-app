import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'shared/themes/app_theme.dart';
import 'core/config/build_config.dart';
import 'core/utils/logger.dart';
import 'features/auth/domain/auth_provider.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/dashboard/presentation/pages/dashboard_page.dart';
import 'features/nodes/presentation/pages/nodes_page.dart';
import 'features/nodes/domain/nodes_provider.dart';
import 'features/dashboard/domain/connection_provider.dart';
import 'features/settings/presentation/pages/settings_page.dart';
import 'features/support/presentation/pages/support_page.dart';

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
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // 等待认证状态检查完成
    // AuthNotifier 构造时会自动调用 _checkStoredSession
    await Future.delayed(const Duration(milliseconds: 500));

    // 如果已登录，加载节点列表
    final authState = ref.read(authProvider);
    if (authState.isAuthenticated) {
      await _loadNodesIfLoggedIn();
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
        }
      }
    } catch (e) {
      VortexLogger.e('Failed to load nodes on startup', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = BuildConfig.instance;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Container(
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
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              '正在加载...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
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
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _getSelectedIndex(context),
            onDestinationSelected: (index) =>
                _onDestinationSelected(context, index),
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: Text('Dashboard'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.dns_outlined),
                selectedIcon: Icon(Icons.dns),
                label: Text('Nodes'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.support_agent_outlined),
                selectedIcon: Icon(Icons.support_agent),
                label: Text('Support'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }

  int _getSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/dashboard')) return 0;
    if (location.startsWith('/nodes')) return 1;
    if (location.startsWith('/settings')) return 2;
    if (location.startsWith('/support')) return 3;
    return 0;
  }

  void _onDestinationSelected(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/dashboard');
        break;
      case 1:
        context.go('/nodes');
        break;
      case 2:
        context.go('/settings');
        break;
      case 3:
        context.go('/support');
        break;
    }
  }
}
