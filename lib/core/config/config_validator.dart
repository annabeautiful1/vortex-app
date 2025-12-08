import 'dart:io';

import '../platform/platform_channel_service.dart';
import '../utils/logger.dart';

/// 配置验证结果
class ConfigValidationResult {
  final bool isValid;
  final String? errorMessage;
  final String? errorDetails;

  const ConfigValidationResult({
    required this.isValid,
    this.errorMessage,
    this.errorDetails,
  });

  factory ConfigValidationResult.success() {
    return const ConfigValidationResult(isValid: true);
  }

  factory ConfigValidationResult.failure(String message, [String? details]) {
    return ConfigValidationResult(
      isValid: false,
      errorMessage: message,
      errorDetails: details,
    );
  }
}

/// 配置验证器 - 在应用配置前验证配置文件是否有效
///
/// 参考 Clash Verge Rev 的 Draft-Validate-Apply 模式：
/// 1. 生成配置文件（Draft）
/// 2. 使用 mihomo -t 验证配置（Validate）
/// 3. 验证通过后应用配置（Apply）
class ConfigValidator {
  static final ConfigValidator _instance = ConfigValidator._internal();
  static ConfigValidator get instance => _instance;

  ConfigValidator._internal();

  final PlatformChannelService _platformChannel =
      PlatformChannelService.instance;

  String? _corePath;

  /// 初始化验证器
  Future<void> init() async {
    _corePath = await _platformChannel.getCorePath();
    VortexLogger.i('ConfigValidator initialized, core path: $_corePath');
  }

  /// 验证配置文件
  ///
  /// 使用 `mihomo -t -f config.yaml` 命令验证配置
  /// 返回验证结果，包含是否有效和错误信息
  Future<ConfigValidationResult> validateConfig(String configPath) async {
    // 检查配置文件是否存在
    final configFile = File(configPath);
    if (!await configFile.exists()) {
      return ConfigValidationResult.failure('配置文件不存在', 'Path: $configPath');
    }

    // 获取核心路径
    final corePath = _corePath ?? await _platformChannel.getCorePath();

    // 移动端不支持直接调用核心验证
    if (Platform.isAndroid || Platform.isIOS) {
      VortexLogger.d('Config validation skipped on mobile platform');
      // 移动端跳过验证，直接返回成功
      // 后续可以通过其他方式验证（如解析 YAML）
      return _validateYamlSyntax(configPath);
    }

    // 检查核心文件是否存在
    if (corePath.isEmpty) {
      VortexLogger.w('Core path is empty, skipping validation');
      return ConfigValidationResult.success();
    }

    final coreFile = File(corePath);
    if (!await coreFile.exists()) {
      VortexLogger.w('Core binary not found at: $corePath');
      // 核心不存在时跳过验证，让后续启动时报错
      return ConfigValidationResult.success();
    }

    try {
      VortexLogger.i('Validating config: $configPath');

      // 执行 mihomo -t -f config.yaml
      final result =
          await Process.run(corePath, [
            '-t',
            '-f',
            configPath,
          ], runInShell: Platform.isWindows).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              VortexLogger.w('Config validation timed out');
              return ProcessResult(0, -1, '', 'Validation timed out');
            },
          );

      if (result.exitCode == 0) {
        VortexLogger.i('Config validation passed');
        return ConfigValidationResult.success();
      } else {
        // 解析错误信息
        final stderr = result.stderr.toString();
        final stdout = result.stdout.toString();
        final errorOutput = stderr.isNotEmpty ? stderr : stdout;

        VortexLogger.e('Config validation failed: $errorOutput');

        // 提取关键错误信息
        final errorMessage = _parseErrorMessage(errorOutput);

        return ConfigValidationResult.failure(errorMessage, errorOutput);
      }
    } catch (e) {
      VortexLogger.e('Config validation error', e);
      return ConfigValidationResult.failure('配置验证失败', e.toString());
    }
  }

  /// 验证 YAML 语法（移动端使用）
  Future<ConfigValidationResult> _validateYamlSyntax(String configPath) async {
    try {
      final content = await File(configPath).readAsString();

      // 基础检查：确保包含必要的配置项
      if (!content.contains('port:') && !content.contains('mixed-port:')) {
        return ConfigValidationResult.failure(
          '配置缺少端口设置',
          '配置文件必须包含 port 或 mixed-port',
        );
      }

      if (!content.contains('proxies:')) {
        return ConfigValidationResult.failure(
          '配置缺少代理节点',
          '配置文件必须包含 proxies 部分',
        );
      }

      // 检查是否有明显的 YAML 语法错误
      // 简单检查缩进和冒号
      final lines = content.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // 跳过空行和注释
        if (line.trim().isEmpty || line.trim().startsWith('#')) continue;

        // 检查是否有 tab 字符（YAML 不允许）
        if (line.contains('\t')) {
          return ConfigValidationResult.failure(
            '配置文件包含 Tab 字符',
            '第 ${i + 1} 行: YAML 不允许使用 Tab 缩进，请使用空格',
          );
        }
      }

      return ConfigValidationResult.success();
    } catch (e) {
      return ConfigValidationResult.failure('YAML 解析失败', e.toString());
    }
  }

  /// 解析错误信息，提取关键内容
  String _parseErrorMessage(String output) {
    // 常见错误模式
    final patterns = [
      RegExp(r'error:\s*(.+)', caseSensitive: false),
      RegExp(r'failed to parse:\s*(.+)', caseSensitive: false),
      RegExp(r'yaml:\s*(.+)', caseSensitive: false),
      RegExp(r'invalid:\s*(.+)', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(output);
      if (match != null) {
        return match.group(1)?.trim() ?? '配置验证失败';
      }
    }

    // 如果没有匹配到特定模式，返回第一行非空内容
    final lines = output.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        // 限制长度
        return trimmed.length > 100
            ? '${trimmed.substring(0, 100)}...'
            : trimmed;
      }
    }

    return '配置验证失败';
  }

  /// 验证并应用配置
  ///
  /// 这是推荐的配置应用方式：
  /// 1. 先验证配置
  /// 2. 验证通过后再应用
  Future<ConfigValidationResult> validateAndApply(
    String configPath, {
    required Future<bool> Function(String) applyCallback,
  }) async {
    // 1. 验证配置
    final validationResult = await validateConfig(configPath);
    if (!validationResult.isValid) {
      return validationResult;
    }

    // 2. 应用配置
    try {
      final applied = await applyCallback(configPath);
      if (applied) {
        return ConfigValidationResult.success();
      } else {
        return ConfigValidationResult.failure('应用配置失败');
      }
    } catch (e) {
      return ConfigValidationResult.failure('应用配置时出错', e.toString());
    }
  }
}
