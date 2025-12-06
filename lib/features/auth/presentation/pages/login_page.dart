import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/auth_provider.dart';
import '../../../../shared/themes/app_theme.dart';
import '../../../../core/config/build_config.dart';
import '../../../../core/utils/dev_mode.dart';
import '../../../../core/utils/logger.dart';
import '../../../debug/presentation/pages/debug_panel.dart';
import '../../../nodes/domain/nodes_provider.dart';
import '../../../dashboard/domain/connection_provider.dart';

/// 禁止输入空格的 TextInputFormatter
/// 在输入和粘贴时都会移除所有空格
class NoSpaceInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // 移除所有空格（包括普通空格、制表符、换行等）
    final newText = newValue.text.replaceAll(RegExp(r'\s'), '');
    if (newText == newValue.text) {
      return newValue;
    }

    // 计算新光标位置
    // 统计从开始到原光标位置之间移除了多少空格
    int removedBeforeCursor = 0;
    final cursorPos = newValue.selection.baseOffset;
    for (int i = 0; i < cursorPos && i < newValue.text.length; i++) {
      if (RegExp(r'\s').hasMatch(newValue.text[i])) {
        removedBeforeCursor++;
      }
    }

    final newCursorPos = (cursorPos - removedBeforeCursor).clamp(
      0,
      newText.length,
    );

    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursorPos),
    );
  }
}

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
  final _nameController = TextEditingController();

  bool _isLoading = false;
  bool _isRegisterMode = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  GuestConfig? _guestConfig;

  int _countdown = 0;
  Timer? _countdownTimer;
  bool _isSendingCode = false;

  int _logoTapCount = 0;
  DateTime? _lastLogoTap;

  @override
  void initState() {
    super.initState();
    _loadGuestConfig();
  }

  Future<void> _loadGuestConfig() async {
    await ref.read(authProvider.notifier).getGuestConfig();
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

  void _handleLogoTap() {
    final now = DateTime.now();
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

  void _openDebugPanel() {
    DevMode.instance.enable();
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const DebugPanel()));
  }

  Future<void> _fetchNodesAfterLogin() async {
    try {
      final authState = ref.read(authProvider);
      final subscribeUrl = authState.user?.subscription.subscriptionUrl;

      if (subscribeUrl != null && subscribeUrl.isNotEmpty) {
        await ref
            .read(nodesProvider.notifier)
            .refreshNodesFromUrl(subscribeUrl);
        final nodesState = ref.read(nodesProvider);
        if (nodesState.nodes.isNotEmpty) {
          ref.read(connectionProvider.notifier).setNodes(nodesState.nodes);
        }
      }
    } catch (e) {
      VortexLogger.e('Failed to fetch nodes after login', e);
    }
  }

  String? _validateEmailWhitelist(String email) {
    if (_guestConfig?.emailWhitelistSuffix == null) return null;
    final whitelist = _guestConfig!.emailWhitelistSuffix!;
    if (whitelist.isEmpty) return null;

    final domain = email.split('@').last.toLowerCase();
    for (final suffix in whitelist) {
      if (domain == suffix.toLowerCase()) return null;
    }
    return '仅支持以下邮箱: ${whitelist.join(', ')}';
  }

  String? _getEmailHint() {
    if (_guestConfig?.emailWhitelistSuffix == null) return null;
    final whitelist = _guestConfig!.emailWhitelistSuffix!;
    if (whitelist.isEmpty) return null;
    return '支持: ${whitelist.join(', ')}';
  }

  bool get _isEmailVerifyRequired => _guestConfig?.isEmailVerify == true;
  bool get _isInviteForceRequired => _guestConfig?.isInviteForce == true;
  bool get _isSSPanel => BuildConfig.instance.isSSPanel;

  Future<void> _sendEmailCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = '请输入有效的邮箱地址');
      return;
    }

    final whitelistError = _validateEmailWhitelist(email);
    if (whitelistError != null) {
      setState(() => _errorMessage = whitelistError);
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
        setState(() => _countdown = 60);
        _startCountdown();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('验证码已发送，请查收邮件')));
        }
      } else {
        setState(() => _errorMessage = '发送验证码失败，请稍后重试');
      }
    } catch (e) {
      setState(
        () => _errorMessage = e.toString().replaceAll('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _isSendingCode = false);
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        setState(() => _countdown--);
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

      await _fetchNodesAfterLogin();
      if (mounted) context.go('/dashboard');
    } catch (e) {
      setState(
        () => _errorMessage = e.toString().replaceAll('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = BuildConfig.instance;

    return Scaffold(
      body: Stack(
        children: [
          // Background Pattern
          Positioned.fill(
            child: CustomPaint(
              painter: GridPainter(
                color: theme.colorScheme.onSurface.withOpacity(0.03),
                spacing: 40,
              ),
            ),
          ),

          // 整个页面使用 SingleChildScrollView，滚动条在最右边
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 60),
                      // Logo & Header
                      Center(
                        child:
                            GestureDetector(
                              onTap: _handleLogoTap,
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.cyclone,
                                  size: 40,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                            ).animate().scale(
                              duration: 600.ms,
                              curve: Curves.easeOutBack,
                            ),
                      ),

                      const SizedBox(height: 32),

                      Text(
                        _isRegisterMode ? '创建账户' : '欢迎回来',
                        style: GoogleFonts.outfit(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ).animate().fadeIn().slideY(begin: 0.3, end: 0),

                      const SizedBox(height: 8),

                      Text(
                            _isRegisterMode
                                ? '注册以开始使用 ${config.appName}'
                                : '登录以继续使用 ${config.appName}',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.6,
                              ),
                            ),
                            textAlign: TextAlign.center,
                          )
                          .animate()
                          .fadeIn(delay: 100.ms)
                          .slideY(begin: 0.3, end: 0),

                      const SizedBox(height: 48),

                      // Form Card
                      Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: theme.cardTheme.color,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: theme.dividerColor),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (_isRegisterMode && _isSSPanel) ...[
                                    _buildTextField(
                                      controller: _nameController,
                                      label: '用户名',
                                      icon: Icons.person_outline_rounded,
                                      validator: (v) =>
                                          v!.isEmpty ? '请输入用户名' : null,
                                    ),
                                    const SizedBox(height: 20),
                                  ],

                                  _buildTextField(
                                    controller: _emailController,
                                    label: '邮箱',
                                    icon: Icons.email_outlined,
                                    noSpaces: true,
                                    hint: _isRegisterMode
                                        ? _getEmailHint()
                                        : null,
                                    validator: (v) {
                                      if (v!.isEmpty) return '请输入邮箱';
                                      if (!v.contains('@')) return '邮箱格式不正确';
                                      if (_isRegisterMode)
                                        return _validateEmailWhitelist(v);
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 20),

                                  if (_isRegisterMode &&
                                      _isEmailVerifyRequired) ...[
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: _buildTextField(
                                            controller: _emailCodeController,
                                            label: '验证码',
                                            icon: Icons.verified_outlined,
                                            validator: (v) =>
                                                v!.isEmpty ? '请输入验证码' : null,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        SizedBox(
                                          height: 56,
                                          child: OutlinedButton(
                                            onPressed:
                                                (_countdown > 0 ||
                                                    _isSendingCode)
                                                ? null
                                                : _sendEmailCode,
                                            style: OutlinedButton.styleFrom(
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                            ),
                                            child: _isSendingCode
                                                ? const SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  )
                                                : Text(
                                                    _countdown > 0
                                                        ? '${_countdown}s'
                                                        : '发送',
                                                  ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                  ],

                                  _buildTextField(
                                    controller: _passwordController,
                                    label: '密码',
                                    icon: Icons.lock_outline_rounded,
                                    obscureText: _obscurePassword,
                                    noSpaces: true,
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                        color: theme.colorScheme.onSurface
                                            .withOpacity(0.5),
                                      ),
                                      onPressed: () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                    ),
                                    validator: (v) {
                                      if (v!.isEmpty) return '请输入密码';
                                      if (_isRegisterMode && v.length < 6)
                                        return '密码至少6位';
                                      return null;
                                    },
                                  ),

                                  if (_isRegisterMode) ...[
                                    const SizedBox(height: 20),
                                    _buildTextField(
                                      controller: _inviteCodeController,
                                      label: _isInviteForceRequired
                                          ? '邀请码（必填）'
                                          : '邀请码（选填）',
                                      icon: Icons.card_giftcard_outlined,
                                      validator: (v) {
                                        if (_isInviteForceRequired &&
                                            (v == null || v.isEmpty)) {
                                          return '请输入邀请码';
                                        }
                                        return null;
                                      },
                                    ),
                                  ],

                                  if (_errorMessage != null) ...[
                                    const SizedBox(height: 24),
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: AppTheme.errorColor.withOpacity(
                                          0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AppTheme.errorColor
                                              .withOpacity(0.2),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.error_outline_rounded,
                                            color: AppTheme.errorColor,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              _errorMessage!,
                                              style: const TextStyle(
                                                color: AppTheme.errorColor,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ).animate().fadeIn(),
                                  ],

                                  const SizedBox(height: 32),

                                  SizedBox(
                                    height: 56,
                                    child: ElevatedButton(
                                      onPressed: _isLoading
                                          ? null
                                          : _handleSubmit,
                                      child: _isLoading
                                          ? const SizedBox(
                                              height: 24,
                                              width: 24,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                color: Colors.white,
                                              ),
                                            )
                                          : Text(_isRegisterMode ? '注册' : '登录'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .animate()
                          .fadeIn(delay: 200.ms)
                          .slideY(begin: 0.1, end: 0),

                      const SizedBox(height: 24),

                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isRegisterMode = !_isRegisterMode;
                            _errorMessage = null;
                            _emailCodeController.clear();
                          });
                        },
                        child: RichText(
                          text: TextSpan(
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.6,
                              ),
                            ),
                            children: [
                              TextSpan(
                                text: _isRegisterMode ? '已有账户？' : '没有账户？',
                              ),
                              TextSpan(
                                text: _isRegisterMode ? '立即登录' : '立即注册',
                                style: TextStyle(
                                  color: AppTheme.primaryColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ).animate().fadeIn(delay: 300.ms),
                      const SizedBox(height: 60),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    String? hint,
    bool noSpaces = false,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      style: const TextStyle(fontWeight: FontWeight.w500),
      inputFormatters: noSpaces ? [NoSpaceInputFormatter()] : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 22),
        suffixIcon: suffixIcon,
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  final Color color;
  final double spacing;

  GridPainter({required this.color, required this.spacing});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    for (double i = 0; i < size.width; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }

    for (double i = 0; i < size.height; i += spacing) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
