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

  // Initialize logger first (console only)
  VortexLogger.init();

  // Initialize file logging early to catch all errors
  try {
    await VortexLogger.initFileLogging();
    VortexLogger.i('File logging initialized');
  } catch (e) {
    // File logging may fail on some platforms, continue anyway
    VortexLogger.w('File logging initialization failed: $e');
  }

  VortexLogger.i('Starting Vortex app...');

  try {
    // Initialize Hive for local storage
    VortexLogger.i('Initializing Hive...');
    await Hive.initFlutter();
    VortexLogger.i('Hive initialized');

    // Initialize storage service
    VortexLogger.i('Initializing storage service...');
    await StorageService.instance.init();
    VortexLogger.i('Storage service initialized');

    // Load build configuration from assets
    VortexLogger.i('Loading build config...');
    await BuildConfig.load();
    VortexLogger.i(
      'App: ${BuildConfig.instance.appName} (${BuildConfig.instance.panelType.name})',
    );

    // Initialize API manager with config endpoints
    VortexLogger.i('Initializing API manager...');
    ApiManager.instance.init();
    VortexLogger.i('API manager initialized');

    // Initialize window manager for desktop
    if (_isDesktop) {
      VortexLogger.i('Initializing desktop services...');
      await WindowService.instance.init(
        title:
            '${BuildConfig.instance.appName} - ${BuildConfig.instance.appNameCn}',
        minimumSize: const Size(900, 600),
        defaultSize: const Size(1100, 700),
      );

      // Initialize tray service
      await TrayService.instance.init(version: BuildConfig.instance.appVersion);
      VortexLogger.i('Desktop services initialized');
    }

    VortexLogger.i('Running app...');
    runApp(const ProviderScope(child: VortexApp()));
  } catch (e, stack) {
    VortexLogger.e('Fatal error during app initialization', e, stack);
    // Show error screen instead of crashing
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    '应用启动失败',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    e.toString(),
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => exit(1),
                    child: const Text('退出'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool get _isDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;
