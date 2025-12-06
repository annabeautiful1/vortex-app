import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../shared/themes/app_theme.dart';
import '../../../../core/config/build_config.dart';
import '../../../auth/domain/auth_provider.dart';
import '../../domain/support_provider.dart';

class SupportPage extends ConsumerStatefulWidget {
  const SupportPage({super.key});

  @override
  ConsumerState<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends ConsumerState<SupportPage> {
  WebViewController? _webViewController;
  bool _isWebViewLoading = true;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    // 检查平台是否支持 WebView
    if (!_isWebViewSupported()) {
      return;
    }

    final supportState = ref.read(supportProvider);
    final authState = ref.read(authProvider);

    if (!supportState.isConfigured || supportState.chatUrl == null) {
      return;
    }

    // 获取带用户信息的聊天 URL
    final chatUrl = ref
        .read(supportProvider.notifier)
        .getChatUrlWithUserInfo(
          email: authState.user?.email,
          nickname: authState.user?.username,
          userData: {
            'plan': authState.user?.subscription.planName ?? '未知',
            'expire': authState.user?.subscription.expireAt.toString() ?? '未知',
          },
        );

    if (chatUrl == null) return;

    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isWebViewLoading = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isWebViewLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebView error: ${error.description}');
          },
          onNavigationRequest: (NavigationRequest request) {
            // 允许 Crisp 相关的 URL
            if (request.url.contains('crisp.chat') ||
                request.url.contains('go.crisp.chat')) {
              return NavigationDecision.navigate;
            }
            // 其他外部链接在浏览器中打开
            launchUrl(Uri.parse(request.url));
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(chatUrl));
  }

  bool _isWebViewSupported() {
    // WebView 在桌面平台支持有限
    return Platform.isAndroid || Platform.isIOS;
  }

  @override
  Widget build(BuildContext context) {
    final supportState = ref.watch(supportProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(context, supportState),

            // Content
            Expanded(child: _buildContent(context, supportState)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, SupportState supportState) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.support_agent, color: AppTheme.primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '在线客服',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: supportState.isOnline
                            ? AppTheme.connectedColor
                            : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      supportState.isLoading
                          ? '检查中...'
                          : supportState.isOnline
                          ? '在线'
                          : '离线',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 刷新按钮
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.read(supportProvider.notifier).checkOnlineStatus();
              _webViewController?.reload();
            },
            tooltip: '刷新',
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, SupportState supportState) {
    // 加载中
    if (supportState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 未配置 Crisp
    if (!supportState.isConfigured) {
      return _buildNotConfigured(context);
    }

    // WebView 不支持的平台（桌面）
    if (!_isWebViewSupported()) {
      return _buildDesktopFallback(context, supportState);
    }

    // 显示 WebView
    return Stack(
      children: [
        if (_webViewController != null)
          WebViewWidget(controller: _webViewController!),
        if (_isWebViewLoading) const Center(child: CircularProgressIndicator()),
      ],
    );
  }

  Widget _buildNotConfigured(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.support_agent_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            '客服系统未配置',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            '请联系管理员配置 Crisp 客服系统',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade500),
          ),
          const SizedBox(height: 24),
          // 显示 Telegram 链接（如果有）
          if (BuildConfig.instance.hasTelegram)
            ElevatedButton.icon(
              onPressed: () {
                launchUrl(Uri.parse(BuildConfig.instance.telegramUrl));
              },
              icon: const Icon(Icons.telegram),
              label: const Text('通过 Telegram 联系'),
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopFallback(
    BuildContext context,
    SupportState supportState,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            supportState.welcomeMessage,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              if (supportState.chatUrl != null) {
                launchUrl(Uri.parse(supportState.chatUrl!));
              }
            },
            icon: const Icon(Icons.open_in_browser),
            label: const Text('在浏览器中打开客服'),
          ),
          const SizedBox(height: 12),
          // 显示 Telegram 链接（如果有）
          if (BuildConfig.instance.hasTelegram)
            OutlinedButton.icon(
              onPressed: () {
                launchUrl(Uri.parse(BuildConfig.instance.telegramUrl));
              },
              icon: const Icon(Icons.telegram),
              label: const Text('通过 Telegram 联系'),
            ),
        ],
      ),
    );
  }
}
