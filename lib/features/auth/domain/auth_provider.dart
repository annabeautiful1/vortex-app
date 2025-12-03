import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/user.dart';
import '../../../core/api/api_manager.dart';
import '../../../core/api/v2board_api.dart';
import '../../../core/api/sspanel_api.dart';
import '../../../shared/services/storage_service.dart';
import '../../../shared/constants/app_constants.dart';
import '../../../core/utils/logger.dart';

/// Panel type enum
enum PanelType { unknown, v2board, sspanel }

/// Guest config (unified for both panels)
class GuestConfig {
  final bool isEmailVerify;
  final bool isInviteForce;
  final List<String>? emailWhitelistSuffix;
  final String? appDescription;
  final String? tosUrl;
  final bool isRecaptcha;
  final String? recaptchaSiteKey;
  final String? logo;

  const GuestConfig({
    this.isEmailVerify = false,
    this.isInviteForce = false,
    this.emailWhitelistSuffix,
    this.appDescription,
    this.tosUrl,
    this.isRecaptcha = false,
    this.recaptchaSiteKey,
    this.logo,
  });

  factory GuestConfig.fromV2board(V2boardGuestConfig config) {
    return GuestConfig(
      isEmailVerify: config.isEmailVerify,
      isInviteForce: config.isInviteForce,
      emailWhitelistSuffix: config.emailWhitelistSuffix,
      appDescription: config.appDescription,
      tosUrl: config.tosUrl,
      isRecaptcha: config.isRecaptcha,
      recaptchaSiteKey: config.recaptchaSiteKey,
      logo: config.logo,
    );
  }

  factory GuestConfig.fromSSPanel(SSPanelGuestConfig config) {
    return GuestConfig(
      isEmailVerify: config.isEmailVerify,
      isInviteForce: config.isInviteForce,
      emailWhitelistSuffix: config.emailWhitelistSuffix,
      appDescription: config.appDescription,
    );
  }
}

/// Auth state
class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final User? user;
  final String? error;
  final GuestConfig? guestConfig;
  final PanelType panelType;
  final String? baseUrl;

  const AuthState({
    this.isAuthenticated = false,
    this.isLoading = false,
    this.user,
    this.error,
    this.guestConfig,
    this.panelType = PanelType.unknown,
    this.baseUrl,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    User? user,
    String? error,
    GuestConfig? guestConfig,
    PanelType? panelType,
    String? baseUrl,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      user: user ?? this.user,
      error: error,
      guestConfig: guestConfig ?? this.guestConfig,
      panelType: panelType ?? this.panelType,
      baseUrl: baseUrl ?? this.baseUrl,
    );
  }
}

/// Auth notifier - supports both V2board and SSPanel
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _checkStoredSession();
  }

  V2boardApi? _v2boardApi;
  SSPanelApi? _sspanelApi;
  List<String>? _sspanelCookies;

  /// Get V2board API instance
  V2boardApi? get v2boardApi => _v2boardApi;

  /// Get SSPanel API instance
  SSPanelApi? get sspanelApi => _sspanelApi;

  /// Get current panel type
  PanelType get panelType => state.panelType;

  /// Get subscribe URL
  String? get subscribeUrl => state.user?.subscription.subscriptionUrl;

  Future<void> _checkStoredSession() async {
    final authData = await StorageService.instance.getSecure(
      AppConstants.tokenKey,
    );
    final baseUrl = await StorageService.instance.getSecure(
      AppConstants.apiEndpointsKey,
    );
    final panelTypeStr = StorageService.instance.getString('panel_type');

    if (authData != null && baseUrl != null) {
      state = state.copyWith(isLoading: true);
      try {
        final panelType = panelTypeStr == 'sspanel'
            ? PanelType.sspanel
            : PanelType.v2board;

        if (panelType == PanelType.v2board) {
          _v2boardApi = V2boardApi(baseUrl: baseUrl);
          _v2boardApi!.setAuthData(authData);
          await _fetchV2boardUserInfo();
        } else {
          _sspanelApi = SSPanelApi(baseUrl: baseUrl);
          _sspanelCookies = authData.split('|||');
          _sspanelApi!.setCookies(_sspanelCookies!);
          await _fetchSSPanelUserInfo();
        }

        state = state.copyWith(panelType: panelType, baseUrl: baseUrl);
      } catch (e) {
        VortexLogger.e('Failed to restore session', e);
        await logout();
      }
    }
  }

  /// Detect panel type from URL
  Future<PanelType> detectPanelType(String baseUrl) async {
    // Try V2board first
    try {
      final v2api = V2boardApi(baseUrl: baseUrl);
      await v2api.getGuestConfig();
      return PanelType.v2board;
    } catch (_) {}

    // Try SSPanel
    try {
      final ssapi = SSPanelApi(baseUrl: baseUrl);
      await ssapi.getGuestConfig();
      return PanelType.sspanel;
    } catch (_) {}

    return PanelType.unknown;
  }

  /// Initialize API connection and get guest config
  Future<GuestConfig?> initializeApi(
    String baseUrl, {
    PanelType? forcePanelType,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      PanelType detectedType;

      if (forcePanelType != null && forcePanelType != PanelType.unknown) {
        detectedType = forcePanelType;
      } else {
        detectedType = await detectPanelType(baseUrl);
      }

      if (detectedType == PanelType.unknown) {
        throw Exception('无法识别面板类型，请检查地址');
      }

      GuestConfig config;

      if (detectedType == PanelType.v2board) {
        _v2boardApi = V2boardApi(baseUrl: baseUrl);
        _sspanelApi = null;
        final v2config = await _v2boardApi!.getGuestConfig();
        config = GuestConfig.fromV2board(v2config);
      } else {
        _sspanelApi = SSPanelApi(baseUrl: baseUrl);
        _v2boardApi = null;
        final ssconfig = await _sspanelApi!.getGuestConfig();
        config = GuestConfig.fromSSPanel(ssconfig);
      }

      // Save base URL and panel type
      await StorageService.instance.setSecure(
        AppConstants.apiEndpointsKey,
        baseUrl,
      );
      await StorageService.instance.setString(
        'panel_type',
        detectedType == PanelType.v2board ? 'v2board' : 'sspanel',
      );

      state = state.copyWith(
        isLoading: false,
        guestConfig: config,
        panelType: detectedType,
        baseUrl: baseUrl,
      );
      VortexLogger.i('API initialized: $baseUrl (${detectedType.name})');
      return config;
    } catch (e) {
      VortexLogger.e('Failed to initialize API', e);
      state = state.copyWith(isLoading: false, error: e.toString());
      return null;
    }
  }

  /// Get guest config (using ApiManager compatibility mode)
  Future<Map<String, dynamic>?> getGuestConfig() async {
    return await ApiManager.instance.getGuestConfig();
  }

  /// Login
  Future<void> login({
    required String email,
    required String password,
    String? code2FA,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      if (state.panelType == PanelType.v2board && _v2boardApi != null) {
        await _loginV2board(email: email, password: password);
      } else if (state.panelType == PanelType.sspanel && _sspanelApi != null) {
        await _loginSSPanel(email: email, password: password, code2FA: code2FA);
      } else {
        throw Exception('请先选择服务器');
      }

      VortexLogger.i('User logged in: $email');
    } catch (e) {
      VortexLogger.e('Login failed', e);
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  Future<void> _loginV2board({
    required String email,
    required String password,
  }) async {
    final authResponse = await _v2boardApi!.login(
      email: email,
      password: password,
    );

    // Save auth data
    await StorageService.instance.setSecure(
      AppConstants.tokenKey,
      authResponse.authData,
    );

    // Fetch user info
    await _fetchV2boardUserInfo();
  }

  Future<void> _loginSSPanel({
    required String email,
    required String password,
    String? code2FA,
  }) async {
    final authResponse = await _sspanelApi!.login(
      email: email,
      password: password,
      code: code2FA,
    );

    // Save cookies as auth data
    _sspanelCookies = authResponse.cookies;
    await StorageService.instance.setSecure(
      AppConstants.tokenKey,
      authResponse.cookies.join('|||'),
    );
    _sspanelApi!.setCookies(authResponse.cookies);

    // Fetch user info
    await _fetchSSPanelUserInfo();
  }

  /// Register
  Future<void> register({
    required String email,
    required String password,
    String? name,
    String? inviteCode,
    String? emailCode,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      if (state.panelType == PanelType.v2board && _v2boardApi != null) {
        await _registerV2board(
          email: email,
          password: password,
          inviteCode: inviteCode,
          emailCode: emailCode,
        );
      } else if (state.panelType == PanelType.sspanel && _sspanelApi != null) {
        await _registerSSPanel(
          email: email,
          password: password,
          name: name ?? email.split('@').first,
          inviteCode: inviteCode,
          emailCode: emailCode,
        );
      } else {
        throw Exception('请先选择服务器');
      }

      VortexLogger.i('User registered: $email');
    } catch (e) {
      VortexLogger.e('Registration failed', e);
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  Future<void> _registerV2board({
    required String email,
    required String password,
    String? inviteCode,
    String? emailCode,
  }) async {
    final authResponse = await _v2boardApi!.register(
      email: email,
      password: password,
      inviteCode: inviteCode,
      emailCode: emailCode,
    );

    await StorageService.instance.setSecure(
      AppConstants.tokenKey,
      authResponse.authData,
    );

    await _fetchV2boardUserInfo();
  }

  Future<void> _registerSSPanel({
    required String email,
    required String password,
    required String name,
    String? inviteCode,
    String? emailCode,
  }) async {
    final authResponse = await _sspanelApi!.register(
      name: name,
      email: email,
      password: password,
      inviteCode: inviteCode,
      emailCode: emailCode,
    );

    _sspanelCookies = authResponse.cookies;
    await StorageService.instance.setSecure(
      AppConstants.tokenKey,
      authResponse.cookies.join('|||'),
    );
    _sspanelApi!.setCookies(authResponse.cookies);

    await _fetchSSPanelUserInfo();
  }

  /// Send email verification code
  Future<bool> sendEmailVerifyCode(String email) async {
    if (state.panelType == PanelType.v2board && _v2boardApi != null) {
      return await _v2boardApi!.sendEmailVerifyCode(email);
    } else if (state.panelType == PanelType.sspanel && _sspanelApi != null) {
      return await _sspanelApi!.sendEmailVerifyCode(email);
    }
    throw Exception('请先选择服务器');
  }

  /// Forget password
  Future<bool> forgetPassword({
    required String email,
    required String emailCode,
    required String newPassword,
  }) async {
    if (state.panelType == PanelType.v2board && _v2boardApi != null) {
      return await _v2boardApi!.forgetPassword(
        email: email,
        emailCode: emailCode,
        newPassword: newPassword,
      );
    } else if (state.panelType == PanelType.sspanel && _sspanelApi != null) {
      // SSPanel uses different password reset flow
      return await _sspanelApi!.resetPasswordRequest(email);
    }
    throw Exception('请先选择服务器');
  }

  /// Fetch V2board user info
  Future<void> _fetchV2boardUserInfo() async {
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
      createdAt: DateTime.fromMillisecondsSinceEpoch(userInfo.createdAt * 1000),
    );

    state = AuthState(
      isAuthenticated: true,
      isLoading: false,
      user: user,
      guestConfig: state.guestConfig,
      panelType: state.panelType,
      baseUrl: state.baseUrl,
    );
  }

  /// Fetch SSPanel user info
  Future<void> _fetchSSPanelUserInfo() async {
    final userInfo = await _sspanelApi!.getUserInfo();
    final ssUser = userInfo.user;

    final user = User(
      id: ssUser.id.toString(),
      email: ssUser.email,
      username: ssUser.userName ?? ssUser.email.split('@').first,
      avatarUrl: userInfo.gravatar,
      subscription: UserSubscription(
        planName: ssUser.class_ > 0 ? 'VIP ${ssUser.class_}' : '免费用户',
        expireAt: ssUser.classExpireDate ?? DateTime.now(),
        trafficTotal: ssUser.transferEnable,
        trafficUsed: ssUser.usedTraffic,
        trafficRemaining: ssUser.remainingTraffic,
        subscriptionUrl: userInfo.subscribeUrl,
      ),
      balance: (ssUser.money * 100).round(), // Convert to cents
      createdAt: DateTime.now(),
    );

    state = AuthState(
      isAuthenticated: true,
      isLoading: false,
      user: user,
      guestConfig: state.guestConfig,
      panelType: state.panelType,
      baseUrl: state.baseUrl,
    );
  }

  /// Logout
  Future<void> logout() async {
    await StorageService.instance.deleteSecure(AppConstants.tokenKey);
    _v2boardApi?.clearAuthData();
    _sspanelApi?.clearAuthData();
    _sspanelCookies = null;
    state = AuthState(
      guestConfig: state.guestConfig,
      panelType: state.panelType,
      baseUrl: state.baseUrl,
    );
    VortexLogger.i('User logged out');
  }

  /// Refresh user info
  Future<void> refreshUserInfo() async {
    if (!state.isAuthenticated) return;

    try {
      if (state.panelType == PanelType.v2board && _v2boardApi != null) {
        await _fetchV2boardUserInfo();
      } else if (state.panelType == PanelType.sspanel && _sspanelApi != null) {
        await _fetchSSPanelUserInfo();
      }
    } catch (e) {
      VortexLogger.e('Failed to refresh user info', e);
    }
  }

  /// Get notices/announcements
  Future<List<dynamic>?> getNotices({int page = 1}) async {
    try {
      if (state.panelType == PanelType.v2board && _v2boardApi != null) {
        final result = await _v2boardApi!.getNotices(page: page);
        return result.notices;
      } else if (state.panelType == PanelType.sspanel && _sspanelApi != null) {
        return await _sspanelApi!.getAnnouncements();
      }
    } catch (e) {
      VortexLogger.e('Failed to get notices', e);
    }
    return null;
  }

  /// Get plans/shop
  Future<List<dynamic>?> getPlans() async {
    try {
      if (state.panelType == PanelType.v2board && _v2boardApi != null) {
        return await _v2boardApi!.getPlans();
      } else if (state.panelType == PanelType.sspanel && _sspanelApi != null) {
        return await _sspanelApi!.getShopList();
      }
    } catch (e) {
      VortexLogger.e('Failed to get plans', e);
    }
    return null;
  }

  /// Get V2board subscribe info (V2board specific)
  Future<V2boardSubscribeInfo?> getV2boardSubscribeInfo() async {
    if (state.panelType != PanelType.v2board || _v2boardApi == null) {
      return null;
    }
    try {
      return await _v2boardApi!.getSubscribe();
    } catch (e) {
      VortexLogger.e('Failed to get subscribe info', e);
      return null;
    }
  }

  /// Reset subscribe URL
  Future<String?> resetSubscribeUrl() async {
    try {
      if (state.panelType == PanelType.v2board && _v2boardApi != null) {
        final newUrl = await _v2boardApi!.resetSecurity();
        await refreshUserInfo();
        return newUrl;
      } else if (state.panelType == PanelType.sspanel && _sspanelApi != null) {
        await _sspanelApi!.resetSubscribeUrl();
        await refreshUserInfo();
        return state.user?.subscription.subscriptionUrl;
      }
    } catch (e) {
      VortexLogger.e('Failed to reset subscribe url', e);
    }
    return null;
  }

  /// Do checkin (SSPanel specific)
  Future<SSPanelCheckinResult?> doCheckin() async {
    if (state.panelType != PanelType.sspanel || _sspanelApi == null) {
      return null;
    }
    try {
      final result = await _sspanelApi!.doCheckin();
      if (result.success) {
        await refreshUserInfo();
      }
      return result;
    } catch (e) {
      VortexLogger.e('Failed to do checkin', e);
      return null;
    }
  }
}

/// Auth provider
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
