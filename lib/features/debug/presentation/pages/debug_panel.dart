import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/dev_mode.dart';
import '../../../../core/config/build_config.dart';
import '../../../../core/api/api_manager.dart';

/// 调试面板 - 用于显示配置信息和日志
/// 长按 Logo 5 次可以打开
class DebugPanel extends ConsumerStatefulWidget {
  const DebugPanel({super.key});

  @override
  ConsumerState<DebugPanel> createState() => _DebugPanelState();
}

class _DebugPanelState extends ConsumerState<DebugPanel> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final devMode = ref.watch(devModeProvider);
    final logs = DevMode.instance.logs;
    final config = BuildConfig.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('开发者模式'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: '复制日志',
            onPressed: () {
              final logText = DevMode.instance.exportLogs();
              Clipboard.setData(ClipboardData(text: logText));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('日志已复制到剪贴板')));
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清除日志',
            onPressed: () {
              DevMode.instance.clearLogs();
              setState(() {});
            },
          ),
          Switch(
            value: devMode,
            onChanged: (value) {
              ref.read(devModeProvider.notifier).toggle();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 配置信息卡片
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '构建配置',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Divider(),
                  _buildConfigRow('应用名称', config.appName),
                  _buildConfigRow('中文名称', config.appNameCn),
                  _buildConfigRow('面板类型', config.panelType.name),
                  _buildConfigRow(
                    '订阅类型',
                    config.subscriptionType.isEmpty
                        ? '(默认)'
                        : config.subscriptionType,
                  ),
                  _buildConfigRow('API 端点数量', '${config.apiEndpoints.length}'),
                  if (config.apiEndpoints.isNotEmpty)
                    _buildConfigRow('API 地址', config.apiEndpoints.join('\n')),
                  const Divider(),
                  _buildConfigRow(
                    'ApiManager 端点',
                    '${ApiManager.instance.endpoints.length}',
                  ),
                  _buildConfigRow(
                    '活动端点',
                    ApiManager.instance.activeEndpoint?.url ?? '(无)',
                  ),
                ],
              ),
            ),
          ),

          // 日志列表
          Expanded(
            child: Card(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Text(
                          '调试日志',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${logs.length} 条',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: logs.isEmpty
                        ? const Center(child: Text('暂无日志'))
                        : ListView.builder(
                            itemCount: logs.length,
                            itemBuilder: (context, index) {
                              // 倒序显示，最新的在上面
                              final entry = logs[logs.length - 1 - index];
                              return _buildLogEntry(entry);
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogEntry(DebugLogEntry entry) {
    final time =
        '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}:${entry.timestamp.second.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: entry.isError ? Colors.red.withValues(alpha: 0.1) : null,
        border: Border(
          bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                entry.isError ? Icons.error_outline : Icons.info_outline,
                size: 16,
                color: entry.isError ? Colors.red : Colors.blue,
              ),
              const SizedBox(width: 8),
              Text(
                time,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  entry.tag,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            entry.message,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: entry.isError ? Colors.red : null,
            ),
          ),
          if (entry.detail != null) ...[
            const SizedBox(height: 4),
            SelectableText(
              entry.detail!,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
