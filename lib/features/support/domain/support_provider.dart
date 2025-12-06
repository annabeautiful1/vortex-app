import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/build_config.dart';
import '../../../core/utils/logger.dart';
import '../../../shared/services/crisp_service.dart';

/// 客服状态
class SupportState {
  final bool isOnline;
  final bool isLoading;
  final bool isConfigured;
  final String? chatUrl;
  final String welcomeMessage;

  const SupportState({
    this.isOnline = false,
    this.isLoading = true,
    this.isConfigured = false,
    this.chatUrl,
    this.welcomeMessage = '您好！请问有什么可以帮助您的？',
  });

  SupportState copyWith({
    bool? isOnline,
    bool? isLoading,
    bool? isConfigured,
    String? chatUrl,
    String? welcomeMessage,
  }) {
    return SupportState(
      isOnline: isOnline ?? this.isOnline,
      isLoading: isLoading ?? this.isLoading,
      isConfigured: isConfigured ?? this.isConfigured,
      chatUrl: chatUrl ?? this.chatUrl,
      welcomeMessage: welcomeMessage ?? this.welcomeMessage,
    );
  }
}

/// 客服状态管理
class SupportNotifier extends StateNotifier<SupportState> {
  SupportNotifier() : super(const SupportState()) {
    _init();
  }

  Timer? _statusTimer;

  Future<void> _init() async {
    final config = BuildConfig.instance;

    // 检查是否配置了 Crisp
    if (!config.hasCrisp) {
      state = state.copyWith(
        isLoading: false,
        isConfigured: false,
      );
      VortexLogger.w('Crisp not configured');
      return;
    }

    // 初始化 Crisp 服务
    await CrispService.instance.init();

    // 获取聊天 URL
    final chatUrl = CrispService.instance.getChatUrl();

    state = state.copyWith(
      isLoading: false,
      isConfigured: true,
      chatUrl: chatUrl,
      welcomeMessage: config.crispWelcomeMessage,
    );

    // 监听在线状态变化
    CrispService.instance.operatorOnline.addListener(_onOperatorStatusChanged);

    // 初始检查状态
    await checkOnlineStatus();

    // 定期检查状态（每 30 秒）
    _statusTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => checkOnlineStatus(),
    );
  }

  void _onOperatorStatusChanged() {
    state = state.copyWith(isOnline: CrispService.instance.operatorOnline.value);
  }

  /// 检查客服在线状态
  Future<void> checkOnlineStatus() async {
    if (!state.isConfigured) return;

    try {
      final isOnline = await CrispService.instance.checkOperatorStatus();
      state = state.copyWith(isOnline: isOnline);
    } catch (e) {
      VortexLogger.e('Failed to check online status', e);
    }
  }

  /// 获取带用户信息的聊天 URL
  String? getChatUrlWithUserInfo({
    String? email,
    String? nickname,
    Map<String, dynamic>? userData,
  }) {
    return CrispService.instance.getChatUrl(
      email: email,
      nickname: nickname,
      userData: userData,
    );
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    CrispService.instance.operatorOnline.removeListener(_onOperatorStatusChanged);
    super.dispose();
  }
}

final supportProvider = StateNotifierProvider<SupportNotifier, SupportState>((
  ref,
) {
  return SupportNotifier();
});
