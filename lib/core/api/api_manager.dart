import 'package:dio/dio.dart';
import '../utils/logger.dart';
import '../../shared/constants/app_constants.dart';

/// API endpoint configuration
class ApiEndpoint {
  final String url;
  final String panelType; // 'sspanel' or 'v2board'
  final String? subscriptionType; // 'clashmeta', 'meta', '1', '2', '3', '4'
  final bool isActive;
  final int priority;
  final DateTime? lastChecked;
  final int failCount;

  const ApiEndpoint({
    required this.url,
    required this.panelType,
    this.subscriptionType,
    this.isActive = false,
    this.priority = 0,
    this.lastChecked,
    this.failCount = 0,
  });

  ApiEndpoint copyWith({
    String? url,
    String? panelType,
    String? subscriptionType,
    bool? isActive,
    int? priority,
    DateTime? lastChecked,
    int? failCount,
  }) {
    return ApiEndpoint(
      url: url ?? this.url,
      panelType: panelType ?? this.panelType,
      subscriptionType: subscriptionType ?? this.subscriptionType,
      isActive: isActive ?? this.isActive,
      priority: priority ?? this.priority,
      lastChecked: lastChecked ?? this.lastChecked,
      failCount: failCount ?? this.failCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'panelType': panelType,
    'subscriptionType': subscriptionType,
    'isActive': isActive,
    'priority': priority,
    'lastChecked': lastChecked?.toIso8601String(),
    'failCount': failCount,
  };

  factory ApiEndpoint.fromJson(Map<String, dynamic> json) => ApiEndpoint(
    url: json['url'] as String,
    panelType: json['panelType'] as String,
    subscriptionType: json['subscriptionType'] as String?,
    isActive: json['isActive'] as bool? ?? false,
    priority: json['priority'] as int? ?? 0,
    lastChecked: json['lastChecked'] != null
        ? DateTime.parse(json['lastChecked'] as String)
        : null,
    failCount: json['failCount'] as int? ?? 0,
  );
}

/// API Manager for handling multiple OSS/API endpoints with auto-polling
class ApiManager {
  static final ApiManager _instance = ApiManager._internal();
  static ApiManager get instance => _instance;

  ApiManager._internal();

  late Dio _dio;
  final List<ApiEndpoint> _endpoints = [];
  ApiEndpoint? _activeEndpoint;

  void init() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: AppConstants.connectTimeout,
        receiveTimeout: AppConstants.apiTimeout,
        sendTimeout: AppConstants.apiTimeout,
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
  }

  /// Add API endpoint
  void addEndpoint(ApiEndpoint endpoint) {
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
      final testUrl = endpoint.panelType == AppConstants.panelV2Board
          ? '${endpoint.url}${AppConstants.v2boardGuestConfig}'
          : '${endpoint.url}${AppConstants.sspanelGuestConfig}';

      final response = await _dio.get(
        testUrl,
        options: Options(receiveTimeout: AppConstants.pingTimeout),
      );

      if (response.statusCode == 200) {
        if (endpoint.panelType == AppConstants.panelV2Board) {
          return response.data != null;
        } else {
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
    if (_activeEndpoint == null) return null;

    try {
      final configUrl = _activeEndpoint!.panelType == AppConstants.panelV2Board
          ? AppConstants.v2boardGuestConfig
          : AppConstants.sspanelGuestConfig;

      final response = await _dio.get('${_activeEndpoint!.url}$configUrl');
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      VortexLogger.e('Failed to get guest config', e);
      return null;
    }
  }
}
