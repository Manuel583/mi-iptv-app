// Puente con el código nativo de Android (imagen flotante y segundo plano).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeBridge {
  static const _ch = MethodChannel('mi_iptv/native');

  /// true mientras la app está en modo imagen flotante (PiP).
  static final ValueNotifier<bool> inPip = ValueNotifier(false);

  /// Se llama cuando el usuario pulsa "Detener" en la notificación.
  static VoidCallback? onStopRequested;

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  static void init() {
    if (!isAndroid) return;
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'pipChanged':
          inPip.value = call.arguments == true;
          break;
        case 'stopPlayback':
          onStopRequested?.call();
          break;
      }
      return null;
    });
  }

  static Future<T?> _call<T>(String method, [Object? args]) async {
    if (!isAndroid) return null;
    try {
      return await _ch.invokeMethod<T>(method, args);
    } catch (e) {
      debugPrint('Error nativo $method: $e');
      return null;
    }
  }

  static Future<bool> isPipSupported() async =>
      (await _call<bool>('isPipSupported')) ?? false;

  static Future<void> setPipEnabled(bool enabled) =>
      _call('setPipEnabled', {'enabled': enabled});

  static Future<bool> enterPip() async =>
      (await _call<bool>('enterPip')) ?? false;

  static Future<void> startPlaybackService(String title) =>
      _call('startService', {'title': title});

  static Future<void> stopPlaybackService() => _call('stopService');

  /// Hace que una grabación aparezca en la galería y en "Archivos".
  static Future<void> scanFile(String path) =>
      _call('scanFile', {'path': path});

  // ------------------------------------------------ Grabación programada

  /// Entrega al sistema la lista de grabaciones pendientes (JSON) para que
  /// programe las alarmas. Devuelve false si algo falló.
  static Future<bool> recorderSchedule(String json) async =>
      (await _call<bool>('recorderSchedule', {'items': json})) ?? false;

  static Future<void> recorderCancel(String id) =>
      _call('recorderCancel', {'id': id});

  /// Estado de cada grabación: {id: {status, path, error, bytes}}.
  static Future<Map<String, dynamic>> recorderStatuses() async {
    final s = await _call<String>('recorderStatuses');
    if (s == null || s.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(s) as Map);
    } catch (_) {
      return {};
    }
  }

  /// true si Android puede limitar la app en segundo plano (ahorro de batería).
  static Future<bool> batteryRestricted() async =>
      (await _call<bool>('batteryRestricted')) ?? false;

  /// Abre el aviso de Android para quitar el ahorro de batería a la app.
  static Future<void> askBatteryExemption() => _call('askBatteryExemption');
}
