import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/config/build_config.dart';
import 'core/api/api_manager.dart';
import 'core/utils/logger.dart';
import 'shared/services/storage_service.dart';
import 'shared/services/tray_service.dart';
import 'shared/services/window_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive for local storage
  await Hive.initFlutter();

  // Initialize storage service
  await StorageService.instance.init();

  // Initialize logger
  VortexLogger.init();

  // Load build configuration from assets
  await BuildConfig.load();
  VortexLogger.i(
    'App: ${BuildConfig.instance.appName} (${BuildConfig.instance.panelType.name})',
  );

  // Initialize API manager with config endpoints
  ApiManager.instance.init();

  // Initialize window manager for desktop
  if (_isDesktop) {
    await WindowService.instance.init(
      title:
          '${BuildConfig.instance.appName} - ${BuildConfig.instance.appNameCn}',
      minimumSize: const Size(900, 600),
      defaultSize: const Size(1100, 700),
    );

    // Initialize tray service
    await TrayService.instance.init(version: BuildConfig.instance.appVersion);
  }

  runApp(const ProviderScope(child: VortexApp()));
}

bool get _isDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;
