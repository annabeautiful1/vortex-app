import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/auth_provider.dart';
import '../../../../shared/themes/app_theme.dart';
import '../../../../core/config/build_config.dart';
import '../../../../core/utils/dev_mode.dart';
import '../../../../core/utils/logger.dart';
import '../../../debug/presentation/pages/debug_panel.dart';
import '../../../nodes/domain/nodes_provider.dart';
import '../../../dashboard/domain/connection_provider.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  final _emailCodeController = TextEditingController();
  final _nameController = TextEditingController(); // SSPanel 需要用户名

  bool _isLoading = false;
  bool _isRegisterMode = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  GuestConfig? _guestConfig;

  // 验证码倒计时
  int _countdown = 0;
  Timer? _countdownTimer;
  bool _isSendingCode = false;

  // 开发者模式触发
  int _logoTapCount = 0;
  DateTime? _lastLogoTap;

  @override
  void initState() {
    super.initState();
    _loadGuestConfig();
  }

  Future<void> _loadGuestConfig() async {
    // 等待 API 初始化
    await ref.read(authProvider.notifier).getGuestConfig();

    // 从 AuthState 获取 guest config
    final authState = ref.read(authProvider);
    if (mounted && authState.guestConfig != null) {
      setState(() {
        _guestConfig = authState.guestConfig;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _inviteCodeController.dispose();
    _emailCodeController.dispose();
    _nameController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  /// 处理 Logo 点击，连续点击 5 次打开调试面板
  void _handleLogoTap() {
    final now = DateTime.now();

    // 如果超过 2 秒没有点击，重置计数
    if (_lastLogoTap != null && now.difference(_lastLogoTap!).inSeconds > 2) {
      _logoTapCount = 0;
    }

    _lastLogoTap = now;
    _logoTapCount++;

    if (_logoTapCount >= 5) {
      _logoTapCount = 0;
      _openDebugPanel();
    }
  }

  /// 打开调试面板
  void _openDebugPanel() {
    // 启用开发者模式
    DevMode.instance.enable();

    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const DebugPanel()));
  }

  /// 登录成功后获取节点列表
  Future<void> _fetchNodesAfterLogin() async {
    try {
      final authState = ref.read(authProvider);
      final subscribeUrl = authState.user?.subscription.subscriptionUrl;

      if (subscribeUrl != null && subscribeUrl.isNotEmpty) {
        VortexLogger.i('Fetching nodes from subscription: $subscribeUrl');

        // 获取节点列表
        await ref
            .read(nodesProvider.notifier)
            .refreshNodesFromUrl(subscribeUrl);

        // 将节点列表设置到 VPN 服务
        final nodesState = ref.read(nodesProvider);
        if (nodesState.nodes.isNotEmpty) {
          ref.read(connectionProvider.notifier).setNodes(nodesState.nodes);
          VortexLogger.i('Loaded ${nodesState.nodes.length} nodes after login');
        }
      } else {
        VortexLogger.w('No subscription URL available');
      }
    } catch (e) {
      VortexLogger.e('Failed to fetch nodes after login', e);
      // 获取节点失败不阻止登录成功
    }
  }

  /// 检查邮箱是否在白名单中
  String? _validateEmailWhitelist(String email) {
    if (_guestConfig?.emailWhitelistSuffix == null) {
      return null;
    }

    final whitelist = _guestConfig!.emailWhitelistSuffix!;
    if (whitelist.isEmpty) {
      return null;
    }

    final domain = email.split('@').last.toLowerCase();
    for (final suffix in whitelist) {
      if (domain == suffix.toLowerCase()) {
        return null;
      }
    }

    return '仅支持以下邮箱: ${whitelist.join(', ')}';
  }

  /// 获取支持的邮箱后缀提示
  String? _getEmailHint() {
    if (_guestConfig?.emailWhitelistSuffix == null) {
      return null;
    }

    final whitelist = _guestConfig!.emailWhitelistSuffix!;
    if (whitelist.isEmpty) {
      return null;
    }

    return '支持: ${whitelist.join(', ')}';
  }

  /// 是否需要邮箱验证
  bool get _isEmailVerifyRequired {
    return _guestConfig?.isEmailVerify == true;
  }

  /// 是否需要邀请码
  bool get _isInviteForceRequired {
    return _guestConfig?.isInviteForce == true;
  }

  /// 是否是 SSPanel
  bool get _isSSPanel {
    return BuildConfig.instance.isSSPanel;
  }

  /// 发送邮箱验证码
  Future<void> _sendEmailCode() async {
    final email = _emailController.text.trim();

    // 验证邮箱格式
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _errorMessage = '请输入有效的邮箱地址';
      });
      return;
    }

    // 验证白名单
    final whitelistError = _validateEmailWhitelist(email);
    if (whitelistError != null) {
      setState(() {
        _errorMessage = whitelistError;
      });
      return;
    }

    setState(() {
      _isSendingCode = true;
      _errorMessage = null;
    });

    try {
      final success = await ref
          .read(authProvider.notifier)
          .sendEmailVerifyCode(email);

      if (success) {
        // 开始倒计时
        setState(() {
          _countdown = 60;
        });
        _startCountdown();

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('验证码已发送，请查收邮件')));
        }
      } else {
        setState(() {
          _errorMessage = '发送验证码失败，请稍后重试';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSendingCode = false;
        });
      }
    }
  }

  /// 开始倒计时
  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        setState(() {
          _countdown--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_isRegisterMode) {
        await ref
            .read(authProvider.notifier)
            .register(
              email: _emailController.text.trim(),
              password: _passwordController.text,
              name: _isSSPanel ? _nameController.text.trim() : null,
              inviteCode: _inviteCodeController.text.trim().isEmpty
                  ? null
                  : _inviteCodeController.text.trim(),
              emailCode: _emailCodeController.text.trim().isEmpty
                  ? null
                  : _emailCodeController.text.trim(),
            );
      } else {
        await ref
            .read(authProvider.notifier)
            .login(
              email: _emailController.text.trim(),
              password: _passwordController.text,
            );
      }

      // 登录/注册成功后自动获取节点列表
      await _fetchNodesAfterLogin();

      if (mounted) {
        context.go('/dashboard');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final config = BuildConfig.instance;

    return Scaffold(
      body: Row(
        children: [
          // Left side - Branding
          if (size.width > 800)
            Expanded(
              flex: 1,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppTheme.primaryColor, AppTheme.secondaryColor],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo placeholder - 点击 5 次打开调试面板
                    GestureDetector(
                      onTap: _handleLogoTap,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: const Icon(
                          Icons.cyclone,
                          size: 80,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      config.appName,
                      style: theme.textTheme.headlineLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      config.appNameCn,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_guestConfig?.appDescription != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 48),
                        child: Text(
                          _guestConfig!.appDescription!,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
            ),

          // Right side - Login form
          Expanded(
            flex: size.width > 800 ? 1 : 2,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (size.width <= 800) ...[
                          GestureDetector(
                            onTap: _handleLogoTap,
                            child: Icon(
                              Icons.cyclone,
                              size: 64,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            config.appName,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),
                        ],

                        Text(
                          _isRegisterMode ? '创建账号' : '欢迎回来',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isRegisterMode ? '注册新账号开始使用' : '登录您的账号',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Username field (SSPanel only, register mode)
                        if (_isRegisterMode && _isSSPanel) ...[
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: '用户名',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return '请输入用户名';
                              }
                              if (value.length < 2) {
                                return '用户名至少2个字符';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Email field
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: '邮箱',
                            prefixIcon: const Icon(Icons.email_outlined),
                            helperText: _isRegisterMode
                                ? _getEmailHint()
                                : null,
                            helperMaxLines: 2,
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return '请输入邮箱';
                            }
                            if (!value.contains('@')) {
                              return '请输入有效的邮箱地址';
                            }
                            // 注册时检查邮箱白名单
                            if (_isRegisterMode) {
                              final whitelistError = _validateEmailWhitelist(
                                value,
                              );
                              if (whitelistError != null) {
                                return whitelistError;
                              }
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Email verification code (register mode, when required)
                        if (_isRegisterMode && _isEmailVerifyRequired) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _emailCodeController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: '邮箱验证码',
                                    prefixIcon: Icon(Icons.verified_outlined),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return '请输入验证码';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                height: 56,
                                child: OutlinedButton(
                                  onPressed: (_countdown > 0 || _isSendingCode)
                                      ? null
                                      : _sendEmailCode,
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                  ),
                                  child: _isSendingCode
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(
                                          _countdown > 0
                                              ? '${_countdown}s'
                                              : '发送验证码',
                                        ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Password field
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: '密码',
                            prefixIcon: const Icon(Icons.lock_outlined),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return '请输入密码';
                            }
                            if (_isRegisterMode && value.length < 6) {
                              return '密码至少6位';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Invite code (register mode only)
                        if (_isRegisterMode) ...[
                          TextFormField(
                            controller: _inviteCodeController,
                            decoration: InputDecoration(
                              labelText: _isInviteForceRequired
                                  ? '邀请码 (必填)'
                                  : '邀请码 (选填)',
                              prefixIcon: const Icon(
                                Icons.card_giftcard_outlined,
                              ),
                            ),
                            validator: (value) {
                              if (_isInviteForceRequired) {
                                if (value == null || value.isEmpty) {
                                  return '请输入邀请码';
                                }
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Error message
                        if (_errorMessage != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.errorColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: AppTheme.errorColor,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: TextStyle(
                                      color: AppTheme.errorColor,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 24),

                        // Submit button
                        FilledButton(
                          onPressed: _isLoading ? null : _handleSubmit,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _isRegisterMode ? '注册' : '登录',
                                  style: const TextStyle(fontSize: 16),
                                ),
                        ),
                        const SizedBox(height: 16),

                        // Toggle login/register
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isRegisterMode = !_isRegisterMode;
                              _errorMessage = null;
                              _emailCodeController.clear();
                            });
                          },
                          child: Text(
                            _isRegisterMode ? '已有账号？立即登录' : '没有账号？立即注册',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
