import 'dart:convert';
import 'package:dio/dio.dart';
import '../utils/logger.dart';
import '../utils/dev_mode.dart';
import '../config/build_config.dart';
import '../../shared/constants/app_constants.dart';

/// API endpoint configuration
class ApiEndpoint {
  final String url;
  final bool isActive;
  final int priority;
  final DateTime? lastChecked;
  final int failCount;

  const ApiEndpoint({
    required this.url,
    this.isActive = false,
    this.priority = 0,
    this.lastChecked,
    this.failCount = 0,
  });

  ApiEndpoint copyWith({
    String? url,
    bool? isActive,
    int? priority,
    DateTime? lastChecked,
    int? failCount,
  }) {
    return ApiEndpoint(
      url: url ?? this.url,
      isActive: isActive ?? this.isActive,
      priority: priority ?? this.priority,
      lastChecked: lastChecked ?? this.lastChecked,
      failCount: failCount ?? this.failCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'isActive': isActive,
    'priority': priority,
    'lastChecked': lastChecked?.toIso8601String(),
    'failCount': failCount,
  };

  factory ApiEndpoint.fromJson(Map<String, dynamic> json) => ApiEndpoint(
    url: json['url'] as String,
    isActive: json['isActive'] as bool? ?? false,
    priority: json['priority'] as int? ?? 0,
    lastChecked: json['lastChecked'] != null
        ? DateTime.parse(json['lastChecked'] as String)
        : null,
    failCount: json['failCount'] as int? ?? 0,
  );
}

/// API Manager for handling multiple OSS/API endpoints with auto-polling
/// Uses BuildConfig for panel type and subscription type
class ApiManager {
  static final ApiManager _instance = ApiManager._internal();
  static ApiManager get instance => _instance;

  ApiManager._internal();

  late Dio _dio;
  final List<ApiEndpoint> _endpoints = [];
  ApiEndpoint? _activeEndpoint;
  bool _initialized = false;

  /// Get panel type from BuildConfig
  String get panelType => BuildConfig.instance.isV2board
      ? AppConstants.panelV2Board
      : AppConstants.panelSSPanel;

  /// Get subscription type from BuildConfig
  String get subscriptionType => BuildConfig.instance.subscriptionType;

  /// Get subscription suffix from BuildConfig
  String get subscriptionSuffix => BuildConfig.instance.subscriptionSuffix;

  /// Get guest config endpoint based on panel type
  String get guestConfigEndpoint => BuildConfig.instance.guestConfigEndpoint;

  /// Initialize ApiManager
  void init() {
    if (_initialized) return;

    _dio = Dio(
      BaseOptions(
        connectTimeout: AppConstants.connectTimeout,
        receiveTimeout: AppConstants.apiTimeout,
        sendTimeout: AppConstants.apiTimeout,
        headers: {'User-Agent': BuildConfig.instance.effectiveUserAgent},
      ),
    );

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
            'API Error: ${error.requestOptions.uri}',
            error.message,
          );
          return handler.next(error);
        },
      ),
    );

    // Load endpoints from BuildConfig
    _loadEndpointsFromConfig();

    _initialized = true;
    VortexLogger.i(
      'ApiManager initialized with ${_endpoints.length} endpoints',
    );
    DevMode.instance.log(
      'ApiManager',
      '初始化完成',
      detail: '端点数量: ${_endpoints.length}',
    );
  }

  /// Load API endpoints from BuildConfig
  void _loadEndpointsFromConfig() {
    final config = BuildConfig.instance;

    DevMode.instance.log(
      'ApiManager',
      '从配置加载端点',
      detail:
          '''
配置中的端点数量: ${config.apiEndpoints.length}
端点列表: ${config.apiEndpoints}''',
    );

    // Add API endpoints from config
    for (var i = 0; i < config.apiEndpoints.length; i++) {
      final url = config.apiEndpoints[i];
      if (url.isNotEmpty) {
        final normalizedUrl = _normalizeUrl(url);
        addEndpoint(ApiEndpoint(url: normalizedUrl, priority: i));
        DevMode.instance.log('ApiManager', '添加端点', detail: normalizedUrl);
      }
    }

    VortexLogger.i('Loaded ${_endpoints.length} API endpoints from config');
  }

  /// Normalize URL (remove trailing slash)
  String _normalizeUrl(String url) {
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// Add API endpoint
  void addEndpoint(ApiEndpoint endpoint) {
    // Check for duplicates
    if (_endpoints.any((e) => e.url == endpoint.url)) {
      return;
    }
    _endpoints.add(endpoint);
    _endpoints.sort((a, b) => a.priority.compareTo(b.priority));
  }

  /// Remove API endpoint
  void removeEndpoint(String url) {
    _endpoints.removeWhere((e) => e.url == url);
  }

  /// Clear all endpoints
  void clearEndpoints() {
    _endpoints.clear();
    _activeEndpoint = null;
  }

  /// Get all endpoints
  List<ApiEndpoint> get endpoints => List.unmodifiable(_endpoints);

  /// Get active endpoint
  ApiEndpoint? get activeEndpoint => _activeEndpoint;

  /// Test API endpoint availability
  Future<bool> testEndpoint(ApiEndpoint endpoint) async {
    final testUrl = '${endpoint.url}$guestConfigEndpoint';
    DevMode.instance.log('ApiManager', '测试端点', detail: testUrl);

    try {
      final response = await _dio.get(
        testUrl,
        options: Options(receiveTimeout: AppConstants.pingTimeout),
      );

      DevMode.instance.log(
        'ApiManager',
        '端点响应',
        detail:
            '''
URL: $testUrl
状态码: ${response.statusCode}
响应类型: ${response.data.runtimeType}''',
      );

      if (response.statusCode == 200) {
        if (BuildConfig.instance.isV2board) {
          // V2board returns JSON with data field
          var data = response.data;
          // 如果是字符串，先解析为 Map
          if (data is String) {
            try {
              data = jsonDecode(data);
            } catch (e) {
              DevMode.instance.error('ApiManager', 'V2board JSON 解析失败', e);
              return false;
            }
          }
          final success = data != null && data is Map && data['data'] != null;
          DevMode.instance.log(
            'ApiManager',
            'V2board 端点测试',
            detail: '成功: $success',
          );
          return success;
        } else {
          // SSPanel returns JSON (可能是 String 或已解析的 Map)
          var data = response.data;
          // 如果是字符串，先解析为 Map
          if (data is String) {
            try {
              data = jsonDecode(data);
            } catch (e) {
              DevMode.instance.error('ApiManager', 'SSPanel JSON 解析失败', e);
              return false;
            }
          }

          if (data is! Map) {
            DevMode.instance.log(
              'ApiManager',
              'SSPanel 响应不是 Map',
              detail: '类型: ${data.runtimeType}',
              isError: true,
            );
            return false;
          }

          final success =
              data['is_email_verify'] != null ||
              data['app_description'] != null;
          DevMode.instance.log(
            'ApiManager',
            'SSPanel 端点测试',
            detail:
                '''
成功: $success
响应数据: $data''',
          );
          return success;
        }
      }
      DevMode.instance.log(
        'ApiManager',
        '端点测试失败',
        detail: '状态码: ${response.statusCode}',
        isError: true,
      );
      return false;
    } catch (e, stack) {
      VortexLogger.e('Endpoint test failed: ${endpoint.url}', e);
      DevMode.instance.error('ApiManager', '端点测试异常: ${endpoint.url}', e, stack);
      return false;
    }
  }

  /// Poll all endpoints and find the first available one
  Future<ApiEndpoint?> pollEndpoints() async {
    VortexLogger.i('Starting API endpoint polling...');
    DevMode.instance.log(
      'ApiManager',
      '开始轮询端点',
      detail: '端点数量: ${_endpoints.length}',
    );

    if (_endpoints.isEmpty) {
      VortexLogger.w('No endpoints configured');
      DevMode.instance.log('ApiManager', '没有配置端点', isError: true);
      return null;
    }

    for (var i = 0; i < _endpoints.length; i++) {
      final endpoint = _endpoints[i];
      DevMode.instance.log(
        'ApiManager',
        '测试端点 ${i + 1}/${_endpoints.length}',
        detail: endpoint.url,
      );

      final isAvailable = await testEndpoint(endpoint);

      _endpoints[i] = endpoint.copyWith(
        lastChecked: DateTime.now(),
        isActive: isAvailable,
        failCount: isAvailable ? 0 : endpoint.failCount + 1,
      );

      if (isAvailable) {
        _activeEndpoint = _endpoints[i];
        VortexLogger.i('Found active endpoint: ${endpoint.url}');
        DevMode.instance.log('ApiManager', '找到可用端点', detail: endpoint.url);
        return _activeEndpoint;
      }
    }

    VortexLogger.w('No active endpoints found');
    DevMode.instance.log('ApiManager', '未找到可用端点', isError: true);
    return null;
  }

  /// Get the first active endpoint URL or poll if none active
  Future<String?> getActiveEndpointUrl() async {
    if (_activeEndpoint != null) {
      DevMode.instance.log(
        'ApiManager',
        '使用已缓存的端点',
        detail: _activeEndpoint!.url,
      );
      return _activeEndpoint!.url;
    }

    final endpoint = await pollEndpoints();
    return endpoint?.url;
  }

  /// Make authenticated request
  Future<Response<T>> request<T>(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
    String? token,
  }) async {
    if (_activeEndpoint == null) {
      await pollEndpoints();
      if (_activeEndpoint == null) {
        throw Exception(ErrorMessages.noValidApi);
      }
    }

    final options = Options(
      method: method,
      headers: token != null ? {'Authorization': 'Bearer $token'} : null,
    );

    return await _dio.request<T>(
      '${_activeEndpoint!.url}$path',
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  /// Get guest config
  Future<Map<String, dynamic>?> getGuestConfig() async {
    if (_activeEndpoint == null) {
      await pollEndpoints();
    }
    if (_activeEndpoint == null) return null;

    try {
      final response = await _dio.get(
        '${_activeEndpoint!.url}$guestConfigEndpoint',
      );

      if (BuildConfig.instance.isV2board) {
        // V2board wraps response in data field
        final responseData = response.data;
        if (responseData is Map && responseData['data'] != null) {
          return responseData['data'] as Map<String, dynamic>?;
        }
      }

      return response.data as Map<String, dynamic>?;
    } catch (e) {
      VortexLogger.e('Failed to get guest config', e);
      return null;
    }
  }

  /// Get Dio instance for direct use
  Dio get dio => _dio;
}
