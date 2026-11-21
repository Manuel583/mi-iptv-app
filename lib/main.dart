import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'native.dart';
import 'updater.dart';
import 'cloud_sync.dart';
import 'scheduler.dart';
import 'ui/home_page.dart';
import 'ui/recorder_window.dart';

// ignore: unused_element
AppLifecycleListener? _lifecycle;

bool get isWindows => !kIsWeb && Platform.isWindows;
bool get isAndroid => !kIsWeb && Platform.isAndroid;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Windows: el Programador de tareas abre la app así para grabar.
  final rec = args.indexOf('--grabar');
  if (isWindows && rec >= 0 && rec + 1 < args.length) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        title: 'Mi IPTV | Grabando',
        size: Size(440, 220),
        minimumSize: Size(360, 200),
        alwaysOnTop: false,
        skipTaskbar: false,
      ),
      () async {
        await windowManager.show(inactive: true);
        await windowManager.minimize();
      },
    );
    runApp(RecorderApp(id: args[rec + 1]));
    return;
  }
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
  await updater.load();
  unawaited(RecordingScheduler.instance.load());
  unawaited(CloudSync.instance.load());
  runApp(const MiIptvApp());
  // Busca versiones nuevas al arrancar (como mucho una vez al día).
  unawaited(
    Future<void>.delayed(const Duration(seconds: 5), updater.checkOnStartup),
  );
  // Al volver a la app: traer cambios de otros aparatos y ver grabaciones.
  _lifecycle = AppLifecycleListener(
    onResume: () {
      CloudSync.instance.onResume();
      RecordingScheduler.instance.refreshStatuses();
    },
  );
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
          navigatorKey: updater.navigatorKey,
          scaffoldMessengerKey: updater.messengerKey,
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
              seedColor: seed,
              brightness: Brightness.dark,
            ),
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
