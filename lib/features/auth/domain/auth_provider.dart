import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/models/user.dart';
import '../../../core/api/api_manager.dart';
import '../../../shared/services/storage_service.dart';
import '../../../shared/constants/app_constants.dart';
import '../../../core/utils/logger.dart';

part 'auth_provider.g.dart';

/// Auth state
class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final User? user;
  final String? error;

  const AuthState({
    this.isAuthenticated = false,
    this.isLoading = false,
    this.user,
    this.error,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    User? user,
    String? error,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      user: user ?? this.user,
      error: error,
    );
  }
}

/// Auth provider
@riverpod
class Auth extends _$Auth {
  @override
  AuthState build() {
    _checkStoredSession();
    return const AuthState();
  }

  Future<void> _checkStoredSession() async {
    final token = await StorageService.instance.getSecure(AppConstants.tokenKey);
    if (token != null) {
      state = state.copyWith(isLoading: true);
      try {
        await _fetchUserInfo(token);
      } catch (e) {
        VortexLogger.e('Failed to restore session', e);
        await logout();
      }
    }
  }

  Future<Map<String, dynamic>?> getGuestConfig() async {
    return await ApiManager.instance.getGuestConfig();
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final endpoint = ApiManager.instance.activeEndpoint;
      if (endpoint == null) {
        throw Exception(ErrorMessages.noValidApi);
      }

      final response = await ApiManager.instance.request(
        endpoint.panelType == AppConstants.panelV2Board
            ? '/api/v1/passport/auth/login'
            : '/api/v1/user/login',
        method: 'POST',
        data: {
          'email': email,
          'password': password,
        },
      );

      final data = response.data;
      String token;

      if (endpoint.panelType == AppConstants.panelV2Board) {
        token = data['data']['auth_data'];
      } else {
        token = data['data']['token'];
      }

      await StorageService.instance.setSecure(AppConstants.tokenKey, token);
      await _fetchUserInfo(token);

      VortexLogger.i('User logged in: $email');
    } catch (e) {
      VortexLogger.e('Login failed', e);
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> register({
    required String email,
    required String password,
    String? inviteCode,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final endpoint = ApiManager.instance.activeEndpoint;
      if (endpoint == null) {
        throw Exception(ErrorMessages.noValidApi);
      }

      final requestData = {
        'email': email,
        'password': password,
      };

      if (inviteCode != null && inviteCode.isNotEmpty) {
        requestData['invite_code'] = inviteCode;
      }

      await ApiManager.instance.request(
        endpoint.panelType == AppConstants.panelV2Board
            ? '/api/v1/passport/auth/register'
            : '/api/v1/user/register',
        method: 'POST',
        data: requestData,
      );

      // Auto login after register
      await login(email: email, password: password);

      VortexLogger.i('User registered: $email');
    } catch (e) {
      VortexLogger.e('Registration failed', e);
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> _fetchUserInfo(String token) async {
    try {
      final endpoint = ApiManager.instance.activeEndpoint;
      if (endpoint == null) {
        throw Exception(ErrorMessages.noValidApi);
      }

      final response = await ApiManager.instance.request(
        endpoint.panelType == AppConstants.panelV2Board
            ? '/api/v1/user/info'
            : '/api/v1/user/info',
        token: token,
      );

      final data = response.data['data'];

      final user = User(
        id: data['id']?.toString() ?? '',
        email: data['email'] ?? '',
        username: data['name'] ?? data['username'],
        avatarUrl: data['avatar_url'],
        subscription: UserSubscription(
          planName: data['plan']?['name'] ?? '无套餐',
          expireAt: data['expired_at'] != null
              ? DateTime.fromMillisecondsSinceEpoch(data['expired_at'] * 1000)
              : DateTime.now(),
          trafficTotal: data['transfer_enable'] ?? 0,
          trafficUsed: (data['u'] ?? 0) + (data['d'] ?? 0),
          trafficRemaining: (data['transfer_enable'] ?? 0) -
              ((data['u'] ?? 0) + (data['d'] ?? 0)),
          subscriptionUrl: data['subscribe_url'],
        ),
        createdAt: data['created_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(data['created_at'] * 1000)
            : null,
      );

      state = AuthState(
        isAuthenticated: true,
        isLoading: false,
        user: user,
      );
    } catch (e) {
      VortexLogger.e('Failed to fetch user info', e);
      rethrow;
    }
  }

  Future<void> logout() async {
    await StorageService.instance.deleteSecure(AppConstants.tokenKey);
    state = const AuthState();
    VortexLogger.i('User logged out');
  }

  Future<void> refreshUserInfo() async {
    final token = await StorageService.instance.getSecure(AppConstants.tokenKey);
    if (token != null) {
      await _fetchUserInfo(token);
    }
  }
}

final authProvider = AuthProvider();
