import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'native.dart';
import 'ui/home_page.dart';

bool get isWindows => !kIsWeb && Platform.isWindows;
bool get isAndroid => !kIsWeb && Platform.isAndroid;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  NativeBridge.init();
  if (isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        title: 'Mi IPTV',
        minimumSize: Size(400, 300),
        size: Size(1200, 760),
        center: true,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }
  await app.load();
  runApp(const MiIptvApp());
}

class MiIptvApp extends StatelessWidget {
  const MiIptvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final s = app.settings;
        final seed = Color(s.seedColor);
        return MaterialApp(
          title: 'Mi IPTV',
          debugShowCheckedModeBanner: false,
          locale: const Locale('es', 'ES'),
          supportedLocales: const [Locale('es', 'ES'), Locale('es')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          themeMode: switch (s.themeMode) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          },
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: seed),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
                seedColor: seed, brightness: Brightness.dark),
            useMaterial3: true,
          ),
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(s.textScale)),
              child: child!,
            );
          },
          home: const HomePage(),
        );
      },
    );
  }
}
