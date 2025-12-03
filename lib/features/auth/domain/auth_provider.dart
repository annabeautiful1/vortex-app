import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/user.dart';
import '../../../core/api/api_manager.dart';
import '../../../core/api/v2board_api.dart';
import '../../../shared/services/storage_service.dart';
import '../../../shared/constants/app_constants.dart';
import '../../../core/utils/logger.dart';

/// Auth state
class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final User? user;
  final String? error;
  final V2boardGuestConfig? guestConfig;

  const AuthState({
    this.isAuthenticated = false,
    this.isLoading = false,
    this.user,
    this.error,
    this.guestConfig,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    User? user,
    String? error,
    V2boardGuestConfig? guestConfig,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      user: user ?? this.user,
      error: error,
      guestConfig: guestConfig ?? this.guestConfig,
    );
  }
}

/// Auth notifier
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _checkStoredSession();
  }

  V2boardApi? _v2boardApi;

  /// 获取V2board API实例
  V2boardApi? get v2boardApi => _v2boardApi;

  Future<void> _checkStoredSession() async {
    final authData = await StorageService.instance.getSecure(
      AppConstants.tokenKey,
    );
    final baseUrl = await StorageService.instance.getSecure(
      AppConstants.apiEndpointsKey,
    );

    if (authData != null && baseUrl != null) {
      state = state.copyWith(isLoading: true);
      try {
        _v2boardApi = V2boardApi(baseUrl: baseUrl);
        _v2boardApi!.setAuthData(authData);
        await _fetchUserInfo();
      } catch (e) {
        VortexLogger.e('Failed to restore session', e);
        await logout();
      }
    }
  }

  /// 初始化API连接并获取访客配置
  Future<V2boardGuestConfig?> initializeApi(String baseUrl) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      _v2boardApi = V2boardApi(baseUrl: baseUrl);
      final config = await _v2boardApi!.getGuestConfig();

      // 保存base URL
      await StorageService.instance.setSecure(
        AppConstants.apiEndpointsKey,
        baseUrl,
      );

      state = state.copyWith(isLoading: false, guestConfig: config);
      VortexLogger.i('API initialized: $baseUrl');
      return config;
    } catch (e) {
      VortexLogger.e('Failed to initialize API', e);
      state = state.copyWith(isLoading: false, error: e.toString());
      return null;
    }
  }

  /// 获取访客配置 (使用ApiManager兼容模式)
  Future<Map<String, dynamic>?> getGuestConfig() async {
    return await ApiManager.instance.getGuestConfig();
  }

  /// 登录
  Future<void> login({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      if (_v2boardApi == null) {
        throw Exception('请先选择服务器');
      }

      final authResponse = await _v2boardApi!.login(
        email: email,
        password: password,
      );

      // 保存认证数据
      await StorageService.instance.setSecure(
        AppConstants.tokenKey,
        authResponse.authData,
      );

      // 获取用户信息
      await _fetchUserInfo();

      VortexLogger.i('User logged in: $email');
    } catch (e) {
      VortexLogger.e('Login failed', e);
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  /// 注册
  Future<void> register({
    required String email,
    required String password,
    String? inviteCode,
    String? emailCode,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      if (_v2boardApi == null) {
        throw Exception('请先选择服务器');
      }

      final authResponse = await _v2boardApi!.register(
        email: email,
        password: password,
        inviteCode: inviteCode,
        emailCode: emailCode,
      );

      // 保存认证数据
      await StorageService.instance.setSecure(
        AppConstants.tokenKey,
        authResponse.authData,
      );

      // 获取用户信息
      await _fetchUserInfo();

      VortexLogger.i('User registered: $email');
    } catch (e) {
      VortexLogger.e('Registration failed', e);
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  /// 发送邮箱验证码
  Future<bool> sendEmailVerifyCode(String email) async {
    if (_v2boardApi == null) {
      throw Exception('请先选择服务器');
    }
    return await _v2boardApi!.sendEmailVerifyCode(email);
  }

  /// 忘记密码
  Future<bool> forgetPassword({
    required String email,
    required String emailCode,
    required String newPassword,
  }) async {
    if (_v2boardApi == null) {
      throw Exception('请先选择服务器');
    }
    return await _v2boardApi!.forgetPassword(
      email: email,
      emailCode: emailCode,
      newPassword: newPassword,
    );
  }

  /// 获取用户信息
  Future<void> _fetchUserInfo() async {
    try {
      if (_v2boardApi == null) {
        throw Exception('API未初始化');
      }

      final userInfo = await _v2boardApi!.getUserInfo();
      final subscribeInfo = await _v2boardApi!.getSubscribe();

      final user = User(
        id: userInfo.uuid,
        email: userInfo.email,
        username: userInfo.email.split('@').first,
        avatarUrl: userInfo.avatarUrl,
        subscription: UserSubscription(
          planName: subscribeInfo.plan?.name ?? '无套餐',
          expireAt: userInfo.expireDate ?? DateTime.now(),
          trafficTotal: subscribeInfo.transferEnable,
          trafficUsed: subscribeInfo.usedTraffic,
          trafficRemaining: subscribeInfo.remainingTraffic,
          subscriptionUrl: subscribeInfo.subscribeUrl,
        ),
        balance: userInfo.balance,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          userInfo.createdAt * 1000,
        ),
      );

      state = AuthState(
        isAuthenticated: true,
        isLoading: false,
        user: user,
        guestConfig: state.guestConfig,
      );
    } catch (e) {
      VortexLogger.e('Failed to fetch user info', e);
      rethrow;
    }
  }

  /// 登出
  Future<void> logout() async {
    await StorageService.instance.deleteSecure(AppConstants.tokenKey);
    _v2boardApi?.clearAuthData();
    state = AuthState(guestConfig: state.guestConfig);
    VortexLogger.i('User logged out');
  }

  /// 刷新用户信息
  Future<void> refreshUserInfo() async {
    if (_v2boardApi != null && state.isAuthenticated) {
      await _fetchUserInfo();
    }
  }

  /// 获取公告列表
  Future<V2boardNoticeList?> getNotices({int page = 1}) async {
    if (_v2boardApi == null) return null;
    try {
      return await _v2boardApi!.getNotices(page: page);
    } catch (e) {
      VortexLogger.e('Failed to get notices', e);
      return null;
    }
  }

  /// 获取套餐列表
  Future<List<V2boardPlan>?> getPlans() async {
    if (_v2boardApi == null) return null;
    try {
      return await _v2boardApi!.getPlans();
    } catch (e) {
      VortexLogger.e('Failed to get plans', e);
      return null;
    }
  }

  /// 获取订阅信息
  Future<V2boardSubscribeInfo?> getSubscribeInfo() async {
    if (_v2boardApi == null) return null;
    try {
      return await _v2boardApi!.getSubscribe();
    } catch (e) {
      VortexLogger.e('Failed to get subscribe info', e);
      return null;
    }
  }

  /// 重置订阅链接
  Future<String?> resetSubscribeUrl() async {
    if (_v2boardApi == null) return null;
    try {
      final newUrl = await _v2boardApi!.resetSecurity();
      await refreshUserInfo();
      return newUrl;
    } catch (e) {
      VortexLogger.e('Failed to reset subscribe url', e);
      return null;
    }
  }
}

/// Auth provider
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
