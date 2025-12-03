import 'package:logger/logger.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class VortexLogger {
  static late Logger _logger;
  static File? _logFile;

  VortexLogger._();

  static void init() {
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
  }

  static Future<void> initFileLogging() async {
    final directory = await getApplicationSupportDirectory();
    final logDir = Directory('${directory.path}/logs');
    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }
    _logFile = File(
      '${logDir.path}/vortex_${DateTime.now().toIso8601String().split('T')[0]}.log',
    );
  }

  static void d(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.d(message, error: error, stackTrace: stackTrace);
    _writeToFile('DEBUG', message);
  }

  static void i(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.i(message, error: error, stackTrace: stackTrace);
    _writeToFile('INFO', message);
  }

  static void w(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w(message, error: error, stackTrace: stackTrace);
    _writeToFile('WARN', message);
  }

  static void e(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
    _writeToFile('ERROR', message, error, stackTrace);
  }

  static void api(String method, String url, {int? statusCode, dynamic body}) {
    final msg =
        'API [$method] $url ${statusCode != null ? "-> $statusCode" : ""}';
    _logger.i(msg);
    _writeToFile('API', '$msg\n$body');
  }

  static void subscription(String action, String url, {String? error}) {
    final msg =
        'SUBSCRIPTION [$action] $url ${error != null ? "Error: $error" : ""}';
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
    final timestamp = DateTime.now().toIso8601String();
    var logEntry = '[$timestamp] [$level] $message\n';
    if (error != null) {
      logEntry += 'Error: $error\n';
    }
    if (stackTrace != null) {
      logEntry += 'StackTrace: $stackTrace\n';
    }
    _logFile!.writeAsStringSync(logEntry, mode: FileMode.append);
  }

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
