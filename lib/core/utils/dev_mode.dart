import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 开发者模式管理
/// 用于调试和查看详细错误信息
/// 正式上线时可以移除或禁用
class DevMode {
  static final DevMode _instance = DevMode._internal();
  static DevMode get instance => _instance;
  DevMode._internal();

  /// 是否启用开发者模式
  /// 在 debug 模式下默认启用
  bool _enabled = kDebugMode;

  /// 调试日志列表
  final List<DebugLogEntry> _logs = [];

  /// 最大日志条数
  static const int _maxLogs = 200;

  /// 是否启用
  bool get isEnabled => _enabled;

  /// 获取所有日志
  List<DebugLogEntry> get logs => List.unmodifiable(_logs);

  /// 启用开发者模式
  void enable() {
    _enabled = true;
    log('DevMode', '开发者模式已启用');
  }

  /// 禁用开发者模式
  void disable() {
    _enabled = false;
    _logs.clear();
  }

  /// 切换开发者模式
  void toggle() {
    if (_enabled) {
      disable();
    } else {
      enable();
    }
  }

  /// 添加日志
  void log(String tag, String message, {String? detail, bool isError = false}) {
    if (!_enabled) return;

    final entry = DebugLogEntry(
      timestamp: DateTime.now(),
      tag: tag,
      message: message,
      detail: detail,
      isError: isError,
    );

    _logs.add(entry);

    // 保持日志数量在限制内
    while (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }

    // 同时输出到控制台
    if (kDebugMode) {
      final prefix = isError ? '❌' : '📝';
      // ignore: avoid_print
      print('$prefix [$tag] $message${detail != null ? '\n   $detail' : ''}');
    }
  }

  /// 添加错误日志
  void error(String tag, String message, [dynamic error, StackTrace? stack]) {
    String? detail;
    if (error != null) {
      detail = error.toString();
      if (stack != null) {
        detail += '\n$stack';
      }
    }
    log(tag, message, detail: detail, isError: true);
  }

  /// 清除日志
  void clearLogs() {
    _logs.clear();
  }

  /// 导出日志为文本
  String exportLogs() {
    final buffer = StringBuffer();
    buffer.writeln('=== Vortex Debug Logs ===');
    buffer.writeln('Time: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Total: ${_logs.length} entries');
    buffer.writeln('');

    for (final entry in _logs) {
      final prefix = entry.isError ? '[ERROR]' : '[INFO]';
      buffer.writeln(
        '${entry.timestamp.toIso8601String()} $prefix [${entry.tag}] ${entry.message}',
      );
      if (entry.detail != null) {
        buffer.writeln('  Detail: ${entry.detail}');
      }
    }

    return buffer.toString();
  }
}

/// 调试日志条目
class DebugLogEntry {
  final DateTime timestamp;
  final String tag;
  final String message;
  final String? detail;
  final bool isError;

  const DebugLogEntry({
    required this.timestamp,
    required this.tag,
    required this.message,
    this.detail,
    this.isError = false,
  });

  @override
  String toString() {
    final time =
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
    return '[$time] [$tag] $message';
  }
}

/// DevMode Provider
final devModeProvider = StateNotifierProvider<DevModeNotifier, bool>((ref) {
  return DevModeNotifier();
});

class DevModeNotifier extends StateNotifier<bool> {
  DevModeNotifier() : super(DevMode.instance.isEnabled);

  void toggle() {
    DevMode.instance.toggle();
    state = DevMode.instance.isEnabled;
  }

  void enable() {
    DevMode.instance.enable();
    state = true;
  }

  void disable() {
    DevMode.instance.disable();
    state = false;
  }
}
