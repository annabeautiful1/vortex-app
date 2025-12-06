import 'package:logger/logger.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class VortexLogger {
  static late Logger _logger;
  static File? _logFile;
  static bool _initialized = false;

  VortexLogger._();

  static void init() {
    if (_initialized) return;
    _logger = Logger(
      printer: PrettyPrinter(
        methodCount: 2,
        errorMethodCount: 8,
        lineLength: 120,
        colors: true,
        printEmojis: true,
        dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
      ),
    );
    _initialized = true;
  }

  static Future<void> initFileLogging() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final logDir = Directory('${directory.path}/logs');
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      _logFile = File(
        '${logDir.path}/vortex_${DateTime.now().toIso8601String().split('T')[0]}.log',
      );
      // 写入启动标记
      _writeToFile('INFO', '========== App Starting ==========');
      _writeToFile('INFO', 'Log file: ${_logFile!.path}');
    } catch (e) {
      // 如果文件日志初始化失败，打印到控制台
      print('Failed to initialize file logging: $e');
    }
  }

  static void d(String message, [dynamic error, StackTrace? stackTrace]) {
    if (!_initialized) init();
    _logger.d(message, error: error, stackTrace: stackTrace);
    _writeToFile('DEBUG', message, error, stackTrace);
  }

  static void i(String message, [dynamic error, StackTrace? stackTrace]) {
    if (!_initialized) init();
    _logger.i(message, error: error, stackTrace: stackTrace);
    _writeToFile('INFO', message, error, stackTrace);
  }

  static void w(String message, [dynamic error, StackTrace? stackTrace]) {
    if (!_initialized) init();
    _logger.w(message, error: error, stackTrace: stackTrace);
    _writeToFile('WARN', message, error, stackTrace);
  }

  static void e(String message, [dynamic error, StackTrace? stackTrace]) {
    if (!_initialized) init();
    _logger.e(message, error: error, stackTrace: stackTrace);
    _writeToFile('ERROR', message, error, stackTrace);
  }

  static void api(String method, String url, {int? statusCode, dynamic body}) {
    final msg =
        'API [$method] $url ${statusCode != null ? "-> $statusCode" : ""}';
    if (!_initialized) init();
    _logger.i(msg);
    _writeToFile('API', '$msg${body != null ? '\n$body' : ''}');
  }

  static void subscription(String action, String url, {String? error}) {
    final msg =
        'SUBSCRIPTION [$action] $url ${error != null ? "Error: $error" : ""}';
    if (!_initialized) init();
    if (error != null) {
      _logger.e(msg);
    } else {
      _logger.i(msg);
    }
    _writeToFile('SUB', msg);
  }

  static void _writeToFile(
    String level,
    String message, [
    dynamic error,
    StackTrace? stackTrace,
  ]) {
    if (_logFile == null) return;
    try {
      final timestamp = DateTime.now().toIso8601String();
      var logEntry = '[$timestamp] [$level] $message\n';
      if (error != null) {
        logEntry += 'Error: $error\n';
      }
      if (stackTrace != null) {
        logEntry += 'StackTrace: $stackTrace\n';
      }
      _logFile!.writeAsStringSync(logEntry, mode: FileMode.append, flush: true);
    } catch (e) {
      // 忽略文件写入错误
    }
  }

  /// 获取日志文件路径
  static String? get logFilePath => _logFile?.path;

  static Future<String> exportLogs() async {
    if (_logFile == null || !await _logFile!.exists()) {
      return 'No logs available';
    }
    return await _logFile!.readAsString();
  }

  static Future<List<File>> getLogFiles() async {
    final directory = await getApplicationSupportDirectory();
    final logDir = Directory('${directory.path}/logs');
    if (!await logDir.exists()) {
      return [];
    }
    return logDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.log'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
  }
}
