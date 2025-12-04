import 'dart:convert';
import 'package:dio/dio.dart';
import '../utils/logger.dart';
import '../../shared/constants/app_constants.dart';

/// SSPanel API Service
/// Supports SSPanel-UIM with Cool Theme
class SSPanelApi {
  final Dio _dio;
  final String baseUrl;

  SSPanelApi({required this.baseUrl})
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: AppConstants.connectTimeout,
          receiveTimeout: AppConstants.apiTimeout,
          sendTimeout: AppConstants.apiTimeout,
          followRedirects: true,
          maxRedirects: 5,
          // SSPanel 需要 form-urlencoded 格式
          contentType: Headers.formUrlEncodedContentType,
          // 允许 200-399 的状态码（包括重定向）
          validateStatus: (status) => status != null && status < 400,
        ),
      ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          VortexLogger.api(options.method, options.uri.toString());
          return handler.next(options);
        },
        onResponse: (response, handler) {
          VortexLogger.api(
            response.requestOptions.method,
            response.requestOptions.uri.toString(),
            statusCode: response.statusCode,
          );
          return handler.next(response);
        },
        onError: (error, handler) {
          VortexLogger.e(
            'SSPanel API Error: ${error.requestOptions.uri}',
            error.message,
          );
          return handler.next(error);
        },
      ),
    );
  }

  /// Set cookies for session-based authentication
  void setCookies(List<String> cookies) {
    _dio.options.headers['Cookie'] = cookies.join('; ');
  }

  /// Clear authentication data
  void clearAuthData() {
    _dio.options.headers.remove('Cookie');
  }

  // ==================== Guest API ====================

  /// Get guest config
  /// GET /guest_config.txt
  Future<SSPanelGuestConfig> getGuestConfig() async {
    try {
      var response = await _dio.get('/guest_config.txt');
      if (response.data is String) {
        // Parse JSON string
        final data = response.data as String;
        if (data.trim().startsWith('{')) {
          return SSPanelGuestConfig.fromJsonString(data);
        }
      } else if (response.data is Map) {
        return SSPanelGuestConfig.fromJson(
          response.data as Map<String, dynamic>,
        );
      }
      throw Exception('Invalid guest config format');
    } catch (e) {
      VortexLogger.e('Failed to get guest config', e);
      rethrow;
    }
  }

  // ==================== Auth API ====================

  /// Login
  /// POST /auth/login
  Future<SSPanelAuthResponse> login({
    required String email,
    required String password,
    String? code, // 2FA code
    bool rememberMe = true,
  }) async {
    try {
      final data = <String, dynamic>{'email': email, 'passwd': password};
      if (code != null && code.isNotEmpty) {
        data['2fa-code'] = code;
      }
      if (rememberMe) {
        data['remember_me'] = 'on';
      }

      var response = await _dio.post('/auth/login', data: data);

      final result = response.data;
      if (result['ret'] == 1) {
        // Extract cookies from response for session
        final cookies = response.headers['set-cookie'] ?? [];
        return SSPanelAuthResponse(
          success: true,
          message: result['msg'] ?? 'Login successful',
          cookies: cookies,
        );
      } else if (result['ret'] == 2) {
        // 2FA required
        throw SSPanel2FARequiredException(result['msg'] ?? '2FA required');
      } else if (result['ret'] == -1) {
        throw Exception('Session expired');
      }
      throw Exception(result['msg'] ?? 'Login failed');
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// Alternative login endpoint (some SSPanel versions)
  /// GET /authorization
  Future<SSPanelAuthResponse> authLogin({
    required String email,
    required String password,
  }) async {
    try {
      var response = await _dio.get(
        '/authorization',
        queryParameters: {'email': email, 'passwd': password},
      );

      final result = response.data;
      if (result['ret'] == 1) {
        final cookies = response.headers['set-cookie'] ?? [];
        return SSPanelAuthResponse(
          success: true,
          message: result['msg'] ?? 'Login successful',
          cookies: cookies,
        );
      }
      throw Exception(result['msg'] ?? 'Login failed');
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// Register
  /// POST /auth/register
  Future<SSPanelAuthResponse> register({
    required String name,
    required String email,
    required String password,
    String? inviteCode,
    String? emailCode,
  }) async {
    try {
      final data = <String, dynamic>{
        'name': name,
        'email': email,
        'passwd': password,
        'repasswd': password,
      };
      if (inviteCode != null && inviteCode.isNotEmpty) {
        data['code'] = inviteCode;
      }
      if (emailCode != null && emailCode.isNotEmpty) {
        data['emailcode'] = emailCode;
      }

      var response = await _dio.post('/auth/register', data: data);

      final result = response.data;
      if (result['ret'] == 1) {
        final cookies = response.headers['set-cookie'] ?? [];
        return SSPanelAuthResponse(
          success: true,
          message: result['msg'] ?? 'Registration successful',
          cookies: cookies,
        );
      }
      throw Exception(result['msg'] ?? 'Registration failed');
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// Send email verification code
  /// POST /auth/send
  Future<bool> sendEmailVerifyCode(String email) async {
    try {
      var response = await _dio.post('/auth/send', data: {'email': email});
      return response.data['ret'] == 1;
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// Reset password request
  /// POST /password/reset
  Future<bool> resetPasswordRequest(String email) async {
    try {
      var response = await _dio.post('/password/reset', data: {'email': email});
      return response.data['ret'] == 1;
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  // ==================== User API ====================

  /// Get user info
  /// GET /getuserinfo
  Future<SSPanelUserInfo> getUserInfo() async {
    try {
      var response = await _dio.get('/getuserinfo');
      if (response.data['ret'] != 1) {
        throw Exception(response.data['msg'] ?? 'Failed to get user info');
      }
      return SSPanelUserInfo.fromJson(response.data['info']);
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// Get latest announcement
  /// GET /notice
  Future<SSPanelNotice?> getLatestNotice() async {
    try {
      var response = await _dio.get('/notice');
      if (response.data['ret'] == 1 && response.data['data'] != null) {
        return SSPanelNotice.fromJson(
          response.data['data'] as Map<String, dynamic>,
        );
      }
      return null;
    } on DioException catch (e) {
      VortexLogger.w('Failed to get notice: ${e.message}');
      return null;
    }
  }

  /// Get all announcements
  /// GET /user/announcement?json=1
  Future<List<SSPanelNotice>> getAnnouncements() async {
    try {
      var response = await _dio.get(
        '/user/announcement',
        queryParameters: {'json': 1},
      );
      if (response.data['ret'] == 1 && response.data['anns'] != null) {
        final List<dynamic> data = response.data['anns'];
        return data
            .map((e) => SSPanelNotice.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } on DioException catch (e) {
      VortexLogger.w('Failed to get announcements: ${e.message}');
      return [];
    }
  }

  /// Get shop list (plans)
  /// GET /user/shop?format=json or /shop?format=json
  Future<List<SSPanelShop>> getShopList() async {
    try {
      // Try user shop first
      var response = await _dio.get(
        '/user/shop',
        queryParameters: {'format': 'json'},
      );
      if (response.data['ret'] == 1 && response.data['shops'] != null) {
        final List<dynamic> data = response.data['shops'];
        return data
            .map((e) => SSPanelShop.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      // Fall back to public shop
      try {
        var response = await _dio.get(
          '/shop',
          queryParameters: {'format': 'json'},
        );
        if (response.data['ret'] == 1 && response.data['list'] != null) {
          final List<dynamic> data = response.data['list'];
          return data
              .map((e) => SSPanelShop.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      } catch (_) {}
    }
    return [];
  }

  /// Get user invite info
  /// GET /user/invite?format=json
  Future<SSPanelInviteInfo> getInviteInfo() async {
    try {
      var response = await _dio.get(
        '/user/invite',
        queryParameters: {'format': 'json'},
      );
      if (response.data['ret'] == 1) {
        return SSPanelInviteInfo.fromJson(response.data);
      }
      throw Exception('Failed to get invite info');
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// Change password
  /// POST /user/password
  Future<bool> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      var response = await _dio.post(
        '/user/password',
        data: {'oldpwd': oldPassword, 'pwd': newPassword, 'repwd': newPassword},
      );
      return response.data['ret'] == 1;
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// Reset subscription URL
  /// GET /user/url_reset
  Future<bool> resetSubscribeUrl() async {
    try {
      await _dio.get('/user/url_reset');
      return true;
    } on DioException catch (e) {
      VortexLogger.e('Failed to reset URL', e);
      return false;
    }
  }

  /// Do daily checkin
  /// POST /user/checkin
  Future<SSPanelCheckinResult> doCheckin() async {
    try {
      var response = await _dio.post('/user/checkin');
      return SSPanelCheckinResult(
        success: response.data['ret'] == 1,
        message: response.data['msg'] ?? '',
        traffic: response.data['traffic'],
        trafficInfo: response.data['trafficInfo'],
      );
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// Get purchase history
  /// GET /user/code?json=1
  Future<List<SSPanelPurchase>> getPurchaseHistory() async {
    try {
      var response = await _dio.get('/user/code', queryParameters: {'json': 1});
      if (response.data['ret'] == 1 && response.data['shops'] != null) {
        final List<dynamic> data = response.data['shops'];
        return data
            .map((e) => SSPanelPurchase.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } on DioException catch (e) {
      VortexLogger.w('Failed to get purchase history: ${e.message}');
      return [];
    }
  }

  // ==================== Helper Methods ====================

  String _extractErrorMessage(DioException e) {
    if (e.response?.data != null) {
      final data = e.response!.data;
      if (data is Map && data['msg'] != null) {
        return data['msg'].toString();
      }
    }
    return e.message ?? 'Network error';
  }
}

// ==================== Exceptions ====================

/// Exception for 2FA requirement
class SSPanel2FARequiredException implements Exception {
  final String message;
  SSPanel2FARequiredException(this.message);

  @override
  String toString() => message;
}

// ==================== Data Models ====================

/// Guest configuration
class SSPanelGuestConfig {
  final bool isEmailVerify;
  final bool isInviteForce;
  final List<String>? emailWhitelistSuffix;
  final String? appDescription;

  SSPanelGuestConfig({
    this.isEmailVerify = false,
    this.isInviteForce = false,
    this.emailWhitelistSuffix,
    this.appDescription,
  });

  factory SSPanelGuestConfig.fromJson(Map<String, dynamic> json) {
    List<String>? whitelist;
    if (json['email_whitelist_suffix'] != null) {
      if (json['email_whitelist_suffix'] is List) {
        whitelist = (json['email_whitelist_suffix'] as List)
            .map((e) => e.toString())
            .toList();
      }
    }

    return SSPanelGuestConfig(
      isEmailVerify: json['is_email_verify'] == true,
      isInviteForce: json['is_invite_force'] == true,
      emailWhitelistSuffix: whitelist,
      appDescription: json['app_description'] as String?,
    );
  }

  factory SSPanelGuestConfig.fromJsonString(String jsonStr) {
    try {
      final Map<String, dynamic> json = Map<String, dynamic>.from(
        jsonDecode(jsonStr),
      );
      return SSPanelGuestConfig.fromJson(json);
    } catch (e) {
      VortexLogger.e('Failed to parse guest config', e);
      return SSPanelGuestConfig();
    }
  }
}

/// Auth response
class SSPanelAuthResponse {
  final bool success;
  final String message;
  final List<String> cookies;

  SSPanelAuthResponse({
    required this.success,
    required this.message,
    this.cookies = const [],
  });
}

/// User info from /getuserinfo
class SSPanelUserInfo {
  final SSPanelUser user;
  final String ssrSubToken;
  final bool mergeSub;
  final String subUrl;
  final String baseUrl;
  final SSPanelSubInfo subInfo;
  final String? gravatar;

  SSPanelUserInfo({
    required this.user,
    required this.ssrSubToken,
    required this.mergeSub,
    required this.subUrl,
    required this.baseUrl,
    required this.subInfo,
    this.gravatar,
  });

  factory SSPanelUserInfo.fromJson(Map<String, dynamic> json) {
    return SSPanelUserInfo(
      user: SSPanelUser.fromJson(json['user'] as Map<String, dynamic>),
      ssrSubToken: json['ssrSubToken'] as String? ?? '',
      mergeSub: json['mergeSub'] == true,
      subUrl: json['subUrl'] as String? ?? '',
      baseUrl: json['baseUrl'] as String? ?? '',
      subInfo: SSPanelSubInfo.fromJson(
        json['subInfo'] as Map<String, dynamic>? ?? {},
      ),
      gravatar: json['gravatar'] as String?,
    );
  }

  /// Get full subscribe URL
  String get subscribeUrl {
    if (subUrl.isEmpty || ssrSubToken.isEmpty) return '';
    final base = subUrl.endsWith('/') ? subUrl : '$subUrl/';
    return '$base$ssrSubToken';
  }
}

/// User details
class SSPanelUser {
  final int id;
  final String email;
  final String? userName;
  final int? port;
  final String? passwd; // Node connection password
  final int? t; // Last use time
  final int u; // Upload bytes
  final int d; // Download bytes
  final int transferEnable; // Total transfer limit
  final int enable; // Account enabled
  final int nodeSpeedlimit; // Speed limit (Mbps)
  final int? nodeConnector; // Connection limit
  final double money; // Balance
  final double imMoney; // Commission balance
  final int class_; // User class/level
  final String classExpire; // Class expire time
  final int? expireIn; // Account expire timestamp
  final int? nodeGroup; // Node group
  final int onlineIpCount;
  final int? telegramId;

  SSPanelUser({
    required this.id,
    required this.email,
    this.userName,
    this.port,
    this.passwd,
    this.t,
    this.u = 0,
    this.d = 0,
    this.transferEnable = 0,
    this.enable = 1,
    this.nodeSpeedlimit = 0,
    this.nodeConnector,
    this.money = 0,
    this.imMoney = 0,
    this.class_ = 0,
    this.classExpire = '',
    this.expireIn,
    this.nodeGroup,
    this.onlineIpCount = 0,
    this.telegramId,
  });

  factory SSPanelUser.fromJson(Map<String, dynamic> json) {
    return SSPanelUser(
      id: json['id'] as int? ?? 0,
      email: json['email'] as String? ?? '',
      userName: json['user_name'] as String?,
      port: json['port'] as int?,
      passwd: json['passwd'] as String?,
      t: json['t'] as int?,
      u: json['u'] as int? ?? 0,
      d: json['d'] as int? ?? 0,
      transferEnable: json['transfer_enable'] as int? ?? 0,
      enable: json['enable'] as int? ?? 1,
      nodeSpeedlimit: json['node_speedlimit'] as int? ?? 0,
      nodeConnector: json['node_connector'] as int?,
      money: (json['money'] as num?)?.toDouble() ?? 0,
      imMoney: (json['im_money'] as num?)?.toDouble() ?? 0,
      class_: json['class'] as int? ?? 0,
      classExpire: json['class_expire'] as String? ?? '',
      expireIn: json['expire_in'] as int?,
      nodeGroup: json['node_group'] as int?,
      onlineIpCount: json['online_ip_count'] as int? ?? 0,
      telegramId: json['telegram_id'] as int?,
    );
  }

  /// Used traffic in bytes
  int get usedTraffic => u + d;

  /// Remaining traffic in bytes
  int get remainingTraffic => transferEnable - usedTraffic;

  /// Traffic usage percentage (0.0 - 1.0)
  double get trafficUsagePercent {
    if (transferEnable == 0) return 0;
    return usedTraffic / transferEnable;
  }

  /// Check if account is enabled
  bool get isEnabled => enable == 1;

  /// Format bytes to human readable
  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  /// Get class expire date
  DateTime? get classExpireDate {
    if (classExpire.isEmpty) return null;
    try {
      return DateTime.parse(classExpire);
    } catch (_) {
      return null;
    }
  }

  /// Get account expire date
  DateTime? get expireDate {
    if (expireIn == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(expireIn! * 1000);
  }
}

/// Subscribe info
class SSPanelSubInfo {
  final int todayUsed; // Today used traffic
  final int monthlyUsed; // Monthly used traffic
  final int total; // Total transfer limit
  final int used; // Total used
  final int remaining; // Remaining
  final String? expireDate; // Expire date string

  SSPanelSubInfo({
    this.todayUsed = 0,
    this.monthlyUsed = 0,
    this.total = 0,
    this.used = 0,
    this.remaining = 0,
    this.expireDate,
  });

  factory SSPanelSubInfo.fromJson(Map<String, dynamic> json) {
    return SSPanelSubInfo(
      todayUsed: _parseTrafficBytes(json['todayUsedTraffic']),
      monthlyUsed: _parseTrafficBytes(json['lastUsedTraffic']),
      total: _parseTrafficBytes(json['transfer_enable']),
      used: _parseTrafficBytes(json['usedTraffic']),
      remaining: _parseTrafficBytes(json['unusedTraffic']),
      expireDate: json['expire_date'] as String?,
    );
  }

  static int _parseTrafficBytes(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) {
      // Parse strings like "1.5 GB", "500 MB"
      final regex = RegExp(r'([\d.]+)\s*([KMGT]?B?)', caseSensitive: false);
      final match = regex.firstMatch(value);
      if (match != null) {
        final num = double.tryParse(match.group(1) ?? '0') ?? 0;
        final unit = (match.group(2) ?? '').toUpperCase();
        switch (unit) {
          case 'KB':
          case 'K':
            return (num * 1024).round();
          case 'MB':
          case 'M':
            return (num * 1024 * 1024).round();
          case 'GB':
          case 'G':
            return (num * 1024 * 1024 * 1024).round();
          case 'TB':
          case 'T':
            return (num * 1024 * 1024 * 1024 * 1024).round();
          default:
            return num.round();
        }
      }
    }
    return 0;
  }
}

/// Announcement/Notice
class SSPanelNotice {
  final int id;
  final String title;
  final String content;
  final String date;

  SSPanelNotice({
    required this.id,
    required this.title,
    required this.content,
    required this.date,
  });

  factory SSPanelNotice.fromJson(Map<String, dynamic> json) {
    return SSPanelNotice(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      date: json['date'] as String? ?? '',
    );
  }
}

/// Shop item (plan)
class SSPanelShop {
  final int id;
  final String name;
  final double price;
  final int? autoRenew; // 0: one-time, 1: monthly, etc.
  final int? autoResetDay; // Day to reset traffic
  final int? content; // Traffic GB
  final int? class_; // Class/level
  final int? classExpire; // Days of class
  final int status; // 1: active

  SSPanelShop({
    required this.id,
    required this.name,
    required this.price,
    this.autoRenew,
    this.autoResetDay,
    this.content,
    this.class_,
    this.classExpire,
    this.status = 1,
  });

  factory SSPanelShop.fromJson(Map<String, dynamic> json) {
    return SSPanelShop(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      autoRenew: json['auto_renew'] as int?,
      autoResetDay: json['auto_reset_day'] as int?,
      content: json['content'] as int?,
      class_: json['class'] as int?,
      classExpire: json['class_expire'] as int?,
      status: json['status'] as int? ?? 1,
    );
  }

  /// Get traffic in GB
  int? get trafficGB => content;

  /// Is subscription (auto-renew)
  bool get isSubscription => autoRenew != null && autoRenew! > 0;
}

/// Invite info
class SSPanelInviteInfo {
  final String? code;
  final double codePayback;
  final int inviteNum;
  final double paybacksSum;

  SSPanelInviteInfo({
    this.code,
    this.codePayback = 0,
    this.inviteNum = 0,
    this.paybacksSum = 0,
  });

  factory SSPanelInviteInfo.fromJson(Map<String, dynamic> json) {
    return SSPanelInviteInfo(
      code: json['code'] is Map
          ? (json['code'] as Map)['code'] as String?
          : null,
      codePayback: (json['code_payback'] as num?)?.toDouble() ?? 0,
      inviteNum: json['invite_num'] as int? ?? 0,
      paybacksSum: (json['paybacks_sum'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Checkin result
class SSPanelCheckinResult {
  final bool success;
  final String message;
  final String? traffic; // Traffic gained
  final String? trafficInfo; // Current traffic info

  SSPanelCheckinResult({
    required this.success,
    required this.message,
    this.traffic,
    this.trafficInfo,
  });
}

/// Purchase history item
class SSPanelPurchase {
  final int id;
  final String name;
  final String? content;
  final String datetime;

  SSPanelPurchase({
    required this.id,
    required this.name,
    this.content,
    required this.datetime,
  });

  factory SSPanelPurchase.fromJson(Map<String, dynamic> json) {
    return SSPanelPurchase(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      content: json['content'] as String?,
      datetime: json['datetime'] as String? ?? '',
    );
  }
}
