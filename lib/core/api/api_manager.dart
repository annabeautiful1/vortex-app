import 'package:dio/dio.dart';
import '../utils/logger.dart';
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
  }

  /// Load API endpoints from BuildConfig
  void _loadEndpointsFromConfig() {
    final config = BuildConfig.instance;

    // Add API endpoints from config
    for (var i = 0; i < config.apiEndpoints.length; i++) {
      final url = config.apiEndpoints[i];
      if (url.isNotEmpty) {
        addEndpoint(ApiEndpoint(url: _normalizeUrl(url), priority: i));
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
    try {
      final testUrl = '${endpoint.url}$guestConfigEndpoint';

      final response = await _dio.get(
        testUrl,
        options: Options(receiveTimeout: AppConstants.pingTimeout),
      );

      if (response.statusCode == 200) {
        if (BuildConfig.instance.isV2board) {
          // V2board returns JSON with data field
          final data = response.data;
          return data != null && data['data'] != null;
        } else {
          // SSPanel returns JSON with config fields
          final data = response.data;
          return data != null &&
              (data['is_email_verify'] != null ||
                  data['app_description'] != null);
        }
      }
      return false;
    } catch (e) {
      VortexLogger.e('Endpoint test failed: ${endpoint.url}', e);
      return false;
    }
  }

  /// Poll all endpoints and find the first available one
  Future<ApiEndpoint?> pollEndpoints() async {
    VortexLogger.i('Starting API endpoint polling...');

    if (_endpoints.isEmpty) {
      VortexLogger.w('No endpoints configured');
      return null;
    }

    for (var i = 0; i < _endpoints.length; i++) {
      final endpoint = _endpoints[i];
      final isAvailable = await testEndpoint(endpoint);

      _endpoints[i] = endpoint.copyWith(
        lastChecked: DateTime.now(),
        isActive: isAvailable,
        failCount: isAvailable ? 0 : endpoint.failCount + 1,
      );

      if (isAvailable) {
        _activeEndpoint = _endpoints[i];
        VortexLogger.i('Found active endpoint: ${endpoint.url}');
        return _activeEndpoint;
      }
    }

    VortexLogger.w('No active endpoints found');
    return null;
  }

  /// Get the first active endpoint URL or poll if none active
  Future<String?> getActiveEndpointUrl() async {
    if (_activeEndpoint != null) {
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
