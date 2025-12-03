import 'package:dio/dio.dart';
import '../utils/logger.dart';
import '../../shared/constants/app_constants.dart';

/// V2board API Service
/// 支持 V2board 1.7.1 - 1.7.4
class V2boardApi {
  final Dio _dio;
  final String baseUrl;

  V2boardApi({required this.baseUrl})
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: AppConstants.connectTimeout,
          receiveTimeout: AppConstants.apiTimeout,
          sendTimeout: AppConstants.apiTimeout,
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
            'V2board API Error: ${error.requestOptions.uri}',
            error.message,
          );
          return handler.next(error);
        },
      ),
    );
  }

  /// 设置认证数据
  void setAuthData(String authData) {
    _dio.options.headers['Authorization'] = authData;
  }

  /// 清除认证数据
  void clearAuthData() {
    _dio.options.headers.remove('Authorization');
  }

  // ==================== Guest API ====================

  /// 获取站点配置 (Guest)
  /// GET /api/v1/gt/cm/cf 或 /api/v1/guest/comm/config
  Future<V2boardGuestConfig> getGuestConfig() async {
    try {
      // 尝试简写路径
      var response = await _dio.get('/api/v1/gt/cm/cf');
      return V2boardGuestConfig.fromJson(response.data['data']);
    } catch (e) {
      // 回退到完整路径
      try {
        var response = await _dio.get('/api/v1/guest/comm/config');
        return V2boardGuestConfig.fromJson(response.data['data']);
      } catch (e2) {
        VortexLogger.e('Failed to get guest config', e2);
        rethrow;
      }
    }
  }

  // ==================== Passport API ====================

  /// 登录
  /// POST /api/v1/pt/au/lg
  Future<V2boardAuthResponse> login({
    required String email,
    required String password,
  }) async {
    try {
      var response = await _dio.post(
        '/api/v1/pt/au/lg',
        data: {'email': email, 'password': password},
      );

      if (response.data['data'] != null) {
        final authResponse = V2boardAuthResponse.fromJson(
          response.data['data'],
        );
        setAuthData(authResponse.authData);
        return authResponse;
      }
      throw Exception(response.data['message'] ?? '登录失败');
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// 注册
  /// POST /api/v1/pt/au/rg
  Future<V2boardAuthResponse> register({
    required String email,
    required String password,
    String? inviteCode,
    String? emailCode,
    String? recaptchaData,
  }) async {
    try {
      final data = <String, dynamic>{'email': email, 'password': password};
      if (inviteCode != null && inviteCode.isNotEmpty) {
        data['invite_code'] = inviteCode;
      }
      if (emailCode != null && emailCode.isNotEmpty) {
        data['email_code'] = emailCode;
      }
      if (recaptchaData != null && recaptchaData.isNotEmpty) {
        data['recaptcha_data'] = recaptchaData;
      }

      var response = await _dio.post('/api/v1/pt/au/rg', data: data);

      if (response.data['data'] != null) {
        final authResponse = V2boardAuthResponse.fromJson(
          response.data['data'],
        );
        setAuthData(authResponse.authData);
        return authResponse;
      }
      throw Exception(response.data['message'] ?? '注册失败');
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// 发送邮箱验证码
  /// POST /api/v1/pt/cm/sev
  Future<bool> sendEmailVerifyCode(String email) async {
    try {
      var response = await _dio.post(
        '/api/v1/pt/cm/sev',
        data: {'email': email},
      );
      return response.data['data'] == true;
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// 忘记密码
  /// POST /api/v1/pt/au/fg
  Future<bool> forgetPassword({
    required String email,
    required String emailCode,
    required String newPassword,
  }) async {
    try {
      var response = await _dio.post(
        '/api/v1/pt/au/fg',
        data: {
          'email': email,
          'email_code': emailCode,
          'password': newPassword,
        },
      );
      return response.data['data'] == true;
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  // ==================== User API ====================

  /// 获取用户信息
  /// GET /api/v1/user/info
  Future<V2boardUserInfo> getUserInfo() async {
    try {
      var response = await _dio.get('/api/v1/user/info');
      return V2boardUserInfo.fromJson(response.data['data']);
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// 获取订阅信息
  /// GET /api/v1/user/getSubscribe
  Future<V2boardSubscribeInfo> getSubscribe() async {
    try {
      var response = await _dio.get('/api/v1/user/getSubscribe');
      return V2boardSubscribeInfo.fromJson(response.data['data']);
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// 重置订阅链接
  /// GET /api/v1/user/resetSecurity
  Future<String> resetSecurity() async {
    try {
      var response = await _dio.get('/api/v1/user/resetSecurity');
      return response.data['data'] as String;
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// 获取公告列表
  /// GET /api/v1/user/notice/fetch
  Future<V2boardNoticeList> getNotices({int page = 1}) async {
    try {
      var response = await _dio.get(
        '/api/v1/user/notice/fetch',
        queryParameters: {'current': page},
      );
      return V2boardNoticeList.fromJson(response.data);
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// 获取套餐列表
  /// GET /api/v1/user/plan/fetch
  Future<List<V2boardPlan>> getPlans() async {
    try {
      var response = await _dio.get('/api/v1/user/plan/fetch');
      final List<dynamic> data = response.data['data'] ?? [];
      return data.map((e) => V2boardPlan.fromJson(e)).toList();
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// 获取用户统计
  /// GET /api/v1/user/getStat
  Future<V2boardUserStat> getUserStat() async {
    try {
      var response = await _dio.get('/api/v1/user/getStat');
      final List<dynamic> data = response.data['data'] ?? [0, 0, 0];
      return V2boardUserStat(
        pendingOrders: data[0] as int,
        pendingTickets: data[1] as int,
        invitedUsers: data[2] as int,
      );
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// 修改密码
  /// POST /api/v1/user/changePassword
  Future<bool> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      var response = await _dio.post(
        '/api/v1/user/changePassword',
        data: {'old_password': oldPassword, 'new_password': newPassword},
      );
      return response.data['data'] == true;
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// 获取服务器列表 (节点)
  /// GET /api/v1/user/server/fetch
  Future<List<dynamic>> getServers() async {
    try {
      var response = await _dio.get('/api/v1/user/server/fetch');
      return response.data['data'] as List<dynamic>? ?? [];
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// 获取知识库分类
  /// GET /api/v1/user/knowledge/getCategory
  Future<List<dynamic>> getKnowledgeCategories() async {
    try {
      var response = await _dio.get('/api/v1/user/knowledge/getCategory');
      return response.data['data'] as List<dynamic>? ?? [];
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// 获取知识库文章
  /// GET /api/v1/user/knowledge/fetch
  Future<List<dynamic>> getKnowledgeArticles({
    String? keyword,
    int? categoryId,
  }) async {
    try {
      final params = <String, dynamic>{};
      if (keyword != null) params['keyword'] = keyword;
      if (categoryId != null) params['category_id'] = categoryId;

      var response = await _dio.get(
        '/api/v1/user/knowledge/fetch',
        queryParameters: params,
      );
      return response.data['data'] as List<dynamic>? ?? [];
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  // ==================== Helper Methods ====================

  String _extractErrorMessage(DioException e) {
    if (e.response?.data != null) {
      final data = e.response!.data;
      if (data is Map && data['message'] != null) {
        return data['message'].toString();
      }
    }
    return e.message ?? '网络错误';
  }
}

// ==================== Data Models ====================

/// 访客配置
class V2boardGuestConfig {
  final String? tosUrl;
  final bool isEmailVerify;
  final bool isInviteForce;
  final List<String>? emailWhitelistSuffix;
  final bool isRecaptcha;
  final String? recaptchaSiteKey;
  final String? appDescription;
  final String? appUrl;
  final String? logo;

  V2boardGuestConfig({
    this.tosUrl,
    this.isEmailVerify = false,
    this.isInviteForce = false,
    this.emailWhitelistSuffix,
    this.isRecaptcha = false,
    this.recaptchaSiteKey,
    this.appDescription,
    this.appUrl,
    this.logo,
  });

  factory V2boardGuestConfig.fromJson(Map<String, dynamic> json) {
    List<String>? whitelist;
    if (json['email_whitelist_suffix'] != null &&
        json['email_whitelist_suffix'] != 0) {
      if (json['email_whitelist_suffix'] is List) {
        whitelist = (json['email_whitelist_suffix'] as List)
            .map((e) => e.toString())
            .toList();
      }
    }

    return V2boardGuestConfig(
      tosUrl: json['tos_url'] as String?,
      isEmailVerify: json['is_email_verify'] == 1,
      isInviteForce: json['is_invite_force'] == 1,
      emailWhitelistSuffix: whitelist,
      isRecaptcha: json['is_recaptcha'] == 1,
      recaptchaSiteKey: json['recaptcha_site_key'] as String?,
      appDescription: json['app_description'] as String?,
      appUrl: json['app_url'] as String?,
      logo: json['logo'] as String?,
    );
  }
}

/// 认证响应
class V2boardAuthResponse {
  final String token;
  final bool isAdmin;
  final String authData;

  V2boardAuthResponse({
    required this.token,
    required this.isAdmin,
    required this.authData,
  });

  factory V2boardAuthResponse.fromJson(Map<String, dynamic> json) {
    return V2boardAuthResponse(
      token: json['token'] as String,
      isAdmin: json['is_admin'] == true || json['is_admin'] == 1,
      authData: json['auth_data'] as String,
    );
  }
}

/// 用户信息
class V2boardUserInfo {
  final String email;
  final int transferEnable; // bytes
  final int? lastLoginAt;
  final int createdAt;
  final bool banned;
  final bool remindExpire;
  final bool remindTraffic;
  final int? expiredAt;
  final int balance; // cents
  final int commissionBalance; // cents
  final int? planId;
  final int? discount;
  final int? commissionRate;
  final int? telegramId;
  final String uuid;
  final String? avatarUrl;

  V2boardUserInfo({
    required this.email,
    required this.transferEnable,
    this.lastLoginAt,
    required this.createdAt,
    this.banned = false,
    this.remindExpire = false,
    this.remindTraffic = false,
    this.expiredAt,
    this.balance = 0,
    this.commissionBalance = 0,
    this.planId,
    this.discount,
    this.commissionRate,
    this.telegramId,
    required this.uuid,
    this.avatarUrl,
  });

  factory V2boardUserInfo.fromJson(Map<String, dynamic> json) {
    return V2boardUserInfo(
      email: json['email'] as String,
      transferEnable: json['transfer_enable'] as int? ?? 0,
      lastLoginAt: json['last_login_at'] as int?,
      createdAt: json['created_at'] as int? ?? 0,
      banned: json['banned'] == 1 || json['banned'] == true,
      remindExpire: json['remind_expire'] == 1 || json['remind_expire'] == true,
      remindTraffic:
          json['remind_traffic'] == 1 || json['remind_traffic'] == true,
      expiredAt: json['expired_at'] as int?,
      balance: json['balance'] as int? ?? 0,
      commissionBalance: json['commission_balance'] as int? ?? 0,
      planId: json['plan_id'] as int?,
      discount: json['discount'] as int?,
      commissionRate: json['commission_rate'] as int?,
      telegramId: json['telegram_id'] as int?,
      uuid: json['uuid'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  /// 获取格式化的流量限额
  String get formattedTransferEnable {
    return _formatBytes(transferEnable);
  }

  /// 获取格式化的余额 (元)
  String get formattedBalance {
    return (balance / 100).toStringAsFixed(2);
  }

  /// 获取到期时间
  DateTime? get expireDate {
    if (expiredAt == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(expiredAt! * 1000);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}

/// 订阅信息
class V2boardSubscribeInfo {
  final int? planId;
  final String token;
  final int? expiredAt;
  final int u; // upload bytes
  final int d; // download bytes
  final int transferEnable;
  final String email;
  final String uuid;
  final V2boardPlan? plan;
  final String subscribeUrl;
  final int? resetDay;

  V2boardSubscribeInfo({
    this.planId,
    required this.token,
    this.expiredAt,
    this.u = 0,
    this.d = 0,
    this.transferEnable = 0,
    required this.email,
    required this.uuid,
    this.plan,
    required this.subscribeUrl,
    this.resetDay,
  });

  factory V2boardSubscribeInfo.fromJson(Map<String, dynamic> json) {
    return V2boardSubscribeInfo(
      planId: json['plan_id'] as int?,
      token: json['token'] as String? ?? '',
      expiredAt: json['expired_at'] as int?,
      u: json['u'] as int? ?? 0,
      d: json['d'] as int? ?? 0,
      transferEnable: json['transfer_enable'] as int? ?? 0,
      email: json['email'] as String? ?? '',
      uuid: json['uuid'] as String? ?? '',
      plan: json['plan'] != null ? V2boardPlan.fromJson(json['plan']) : null,
      subscribeUrl: json['subscribe_url'] as String? ?? '',
      resetDay: json['reset_day'] as int?,
    );
  }

  /// 已使用流量
  int get usedTraffic => u + d;

  /// 剩余流量
  int get remainingTraffic => transferEnable - usedTraffic;

  /// 流量使用百分比
  double get trafficPercentage {
    if (transferEnable == 0) return 0;
    return usedTraffic / transferEnable;
  }
}

/// 套餐信息
class V2boardPlan {
  final int id;
  final int groupId;
  final int? transferEnable; // GB
  final String name;
  final int? speedLimit; // Mbps
  final bool show;
  final int sort;
  final bool renew;
  final String? content;
  final int? monthPrice;
  final int? quarterPrice;
  final int? halfYearPrice;
  final int? yearPrice;
  final int? twoYearPrice;
  final int? threeYearPrice;
  final int? onetimePrice;
  final int? resetPrice;
  final int? capacityLimit;

  V2boardPlan({
    required this.id,
    required this.groupId,
    this.transferEnable,
    required this.name,
    this.speedLimit,
    this.show = true,
    this.sort = 0,
    this.renew = true,
    this.content,
    this.monthPrice,
    this.quarterPrice,
    this.halfYearPrice,
    this.yearPrice,
    this.twoYearPrice,
    this.threeYearPrice,
    this.onetimePrice,
    this.resetPrice,
    this.capacityLimit,
  });

  factory V2boardPlan.fromJson(Map<String, dynamic> json) {
    return V2boardPlan(
      id: json['id'] as int,
      groupId: json['group_id'] as int? ?? 0,
      transferEnable: json['transfer_enable'] as int?,
      name: json['name'] as String? ?? '',
      speedLimit: json['speed_limit'] as int?,
      show: json['show'] == 1 || json['show'] == true,
      sort: json['sort'] as int? ?? 0,
      renew: json['renew'] == 1 || json['renew'] == true,
      content: json['content'] as String?,
      monthPrice: json['month_price'] as int?,
      quarterPrice: json['quarter_price'] as int?,
      halfYearPrice: json['half_year_price'] as int?,
      yearPrice: json['year_price'] as int?,
      twoYearPrice: json['two_year_price'] as int?,
      threeYearPrice: json['three_year_price'] as int?,
      onetimePrice: json['onetime_price'] as int?,
      resetPrice: json['reset_price'] as int?,
      capacityLimit: json['capacity_limit'] as int?,
    );
  }
}

/// 公告
class V2boardNotice {
  final int id;
  final String title;
  final String content;
  final int createdAt;

  V2boardNotice({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
  });

  factory V2boardNotice.fromJson(Map<String, dynamic> json) {
    return V2boardNotice(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      createdAt: json['created_at'] as int? ?? 0,
    );
  }

  DateTime get createdDate {
    return DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
  }
}

/// 公告列表
class V2boardNoticeList {
  final List<V2boardNotice> notices;
  final int total;

  V2boardNoticeList({required this.notices, required this.total});

  factory V2boardNoticeList.fromJson(Map<String, dynamic> json) {
    final List<dynamic> data = json['data'] ?? [];
    return V2boardNoticeList(
      notices: data.map((e) => V2boardNotice.fromJson(e)).toList(),
      total: json['total'] as int? ?? 0,
    );
  }
}

/// 用户统计
class V2boardUserStat {
  final int pendingOrders;
  final int pendingTickets;
  final int invitedUsers;

  V2boardUserStat({
    required this.pendingOrders,
    required this.pendingTickets,
    required this.invitedUsers,
  });
}
