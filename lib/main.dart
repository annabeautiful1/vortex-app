import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/config/build_config.dart';
import 'core/api/api_manager.dart';
import 'core/utils/logger.dart';
import 'shared/services/storage_service.dart';

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

  runApp(const ProviderScope(child: VortexApp()));
}
