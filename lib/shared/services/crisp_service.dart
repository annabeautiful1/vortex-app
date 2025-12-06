import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/build_config.dart';
import '../../core/utils/logger.dart';

/// Crisp 客服服务
/// 用于与 Crisp 即时通讯系统交互
class CrispService {
  static final CrispService _instance = CrispService._internal();
  static CrispService get instance => _instance;

  CrispService._internal();

  late Dio _dio;
  String? _sessionId;
  String? _websiteId;
  bool _isInitialized = false;

  // 状态回调
  final ValueNotifier<bool> operatorOnline = ValueNotifier(false);
  final ValueNotifier<bool> isConnected = ValueNotifier(false);

  // Crisp 状态检查 URL (公开接口)
  static const String _statusBaseUrl = 'https://client.crisp.chat/v1';

  /// 初始化 Crisp 服务
  Future<void> init() async {
    if (_isInitialized) return;

    final config = BuildConfig.instance;
    _websiteId = config.crispWebsiteId;

    if (_websiteId == null || _websiteId!.isEmpty) {
      VortexLogger.w('Crisp website ID not configured');
      return;
    }

    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Content-Type': 'application/json',
        },
      ),
    );

    _isInitialized = true;
    VortexLogger.i('CrispService initialized with website: $_websiteId');

    // 检查客服在线状态
    await checkOperatorStatus();
  }

  /// 检查客服在线状态
  Future<bool> checkOperatorStatus() async {
    if (_websiteId == null || _websiteId!.isEmpty) {
      operatorOnline.value = false;
      return false;
    }

    try {
      // 使用 Crisp 公开的网站状态接口
      final response = await _dio.get(
        '$_statusBaseUrl/website/$_websiteId/availability/status',
      );

      if (response.statusCode == 200) {
        final data = response.data;
        // Crisp 返回的状态格式
        // { "data": { "status": "online" | "offline" | "away" } }
        final status = data['data']?['status'] ?? 'offline';
        final isOnline = status == 'online';
        operatorOnline.value = isOnline;
        VortexLogger.d('Crisp operator status: $status');
        return isOnline;
      }
    } catch (e) {
      VortexLogger.w('Failed to check Crisp operator status: $e');
      // 如果无法获取状态，默认显示在线（让用户可以发送消息）
      operatorOnline.value = true;
    }
    return operatorOnline.value;
  }

  /// 创建新会话
  Future<String?> createSession({
    String? email,
    String? nickname,
    Map<String, dynamic>? userData,
  }) async {
    if (_websiteId == null || _websiteId!.isEmpty) {
      VortexLogger.w('Cannot create session: website ID not configured');
      return null;
    }

    try {
      // 生成唯一的会话 ID
      _sessionId = _generateSessionId();

      VortexLogger.i('Created Crisp session: $_sessionId');
      isConnected.value = true;
      return _sessionId;
    } catch (e) {
      VortexLogger.e('Failed to create Crisp session', e);
      return null;
    }
  }

  /// 生成会话 ID
  String _generateSessionId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = timestamp.hashCode.toRadixString(36);
    return 'vortex_$random';
  }

  /// 获取 Crisp 聊天 URL（用于 WebView）
  String? getChatUrl({
    String? email,
    String? nickname,
    Map<String, dynamic>? userData,
  }) {
    if (_websiteId == null || _websiteId!.isEmpty) {
      return null;
    }

    // 构建 Crisp 聊天 URL
    final baseUrl = 'https://go.crisp.chat/chat/embed/?website_id=$_websiteId';

    final params = <String>[];

    if (email != null && email.isNotEmpty) {
      params.add('email=${Uri.encodeComponent(email)}');
    }
    if (nickname != null && nickname.isNotEmpty) {
      params.add('nickname=${Uri.encodeComponent(nickname)}');
    }

    // 添加用户数据
    if (userData != null && userData.isNotEmpty) {
      final dataJson = jsonEncode(userData);
      params.add('data=${Uri.encodeComponent(dataJson)}');
    }

    if (params.isEmpty) {
      return baseUrl;
    }

    return '$baseUrl&${params.join('&')}';
  }

  /// 获取网站 ID
  String? get websiteId => _websiteId;

  /// 获取当前会话 ID
  String? get sessionId => _sessionId;

  /// 是否已配置
  bool get isConfigured => _websiteId != null && _websiteId!.isNotEmpty;

  /// 断开连接
  void disconnect() {
    _sessionId = null;
    isConnected.value = false;
  }

  /// 释放资源
  void dispose() {
    operatorOnline.dispose();
    isConnected.dispose();
  }
}
