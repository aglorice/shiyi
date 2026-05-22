import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';
import 'settings/app_preferences_controller.dart';
import 'theme/app_theme.dart';

class UniYiApp extends ConsumerStatefulWidget {
  const UniYiApp({super.key});

  @override
  ConsumerState<UniYiApp> createState() => _UniYiAppState();
}

class _UniYiAppState extends ConsumerState<UniYiApp> {
  @override
  void initState() {
    super.initState();
    _enableHighRefreshRate();
  }

  Future<void> _enableHighRefreshRate() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } on PlatformException catch (error) {
      debugPrint('Failed to enable high refresh rate: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final preferences = ref.watch(appPreferencesControllerProvider);

    return MaterialApp.router(
      title: '拾邑 | 五邑大学校园助手',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(preferences),
      darkTheme: AppTheme.dark(preferences),
      themeMode: preferences.flutterThemeMode,
      routerConfig: router,
    );
  }
}
