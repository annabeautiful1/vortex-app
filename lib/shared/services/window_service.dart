import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/utils/logger.dart';

/// Window service for desktop platforms
class WindowService with WindowListener {
  static final WindowService _instance = WindowService._internal();
  static WindowService get instance => _instance;

  WindowService._internal();

  bool _isInitialized = false;
  bool _preventClose = true;

  /// Initialize window manager
  Future<void> init({
    String title = 'Vortex',
    Size minimumSize = const Size(900, 600),
    Size defaultSize = const Size(1100, 700),
    bool center = true,
  }) async {
    if (_isInitialized) return;
    if (!_isDesktop) return;

    try {
      await windowManager.ensureInitialized();

      WindowOptions windowOptions = WindowOptions(
        size: defaultSize,
        minimumSize: minimumSize,
        center: center,
        backgroundColor: const Color(0x00000000),
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.normal,
        title: title,
      );

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });

      windowManager.addListener(this);
      _isInitialized = true;

      VortexLogger.i('Window service initialized');
    } catch (e) {
      VortexLogger.e('Failed to initialize window service', e);
    }
  }

  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// Set whether to prevent window close (minimize to tray instead)
  void setPreventClose(bool prevent) {
    _preventClose = prevent;
  }

  /// Show window
  Future<void> show() async {
    if (!_isInitialized) return;
    await windowManager.show();
    await windowManager.focus();
  }

  /// Hide window to tray
  Future<void> hide() async {
    if (!_isInitialized) return;
    await windowManager.hide();
  }

  /// Close window
  Future<void> close() async {
    if (!_isInitialized) return;
    _preventClose = false;
    await windowManager.close();
  }

  /// Minimize window
  Future<void> minimize() async {
    if (!_isInitialized) return;
    await windowManager.minimize();
  }

  /// Maximize window
  Future<void> maximize() async {
    if (!_isInitialized) return;
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  /// Set window title
  Future<void> setTitle(String title) async {
    if (!_isInitialized) return;
    await windowManager.setTitle(title);
  }

  @override
  void onWindowClose() async {
    if (_preventClose) {
      // Minimize to tray instead of closing
      await windowManager.hide();
    } else {
      await windowManager.destroy();
    }
  }

  @override
  void onWindowFocus() {
    // Window focused
  }

  @override
  void onWindowBlur() {
    // Window lost focus
  }

  @override
  void onWindowMaximize() {
    // Window maximized
  }

  @override
  void onWindowUnmaximize() {
    // Window unmaximized
  }

  @override
  void onWindowMinimize() {
    // Window minimized
  }

  @override
  void onWindowRestore() {
    // Window restored
  }

  /// Dispose window service
  void dispose() {
    if (!_isInitialized) return;
    windowManager.removeListener(this);
    _isInitialized = false;
  }
}
