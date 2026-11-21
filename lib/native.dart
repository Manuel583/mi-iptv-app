// Puente con el código nativo de Android (imagen flotante y segundo plano).
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeBridge {
  static const _ch = MethodChannel('mi_iptv/native');

  /// true mientras la app está en modo imagen flotante (PiP).
  static final ValueNotifier<bool> inPip = ValueNotifier(false);

  /// Se llama cuando el usuario pulsa "Detener" en la notificación.
  static VoidCallback? onStopRequested;

  /// Texto de los subtítulos en directo (parcial o definitivo).
  static void Function(String text, bool isFinal)? onCaptionText;

  /// Estado de los subtítulos en directo (listening, downloading, error...).
  static void Function(String status, String? message)? onCaptionStatus;

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
        case 'captionText':
          final m = (call.arguments as Map).cast<String, dynamic>();
          onCaptionText?.call(
            (m['text'] ?? '') as String,
            (m['final'] ?? false) as bool,
          );
          break;
        case 'captionStatus':
          final m = (call.arguments as Map).cast<String, dynamic>();
          onCaptionStatus?.call(
            (m['status'] ?? '') as String,
            m['message'] as String?,
          );
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

  static Future<bool> captionsSupported() async =>
      (await _call<bool>('captionsSupported')) ?? false;

  /// Devuelve "ok", "denied", "unsupported", "cancelled" o "error:...".
  static Future<String> startCaptions(String lang) async =>
      (await _call<String>('startCaptions', {'lang': lang})) ?? 'unsupported';

  static Future<void> stopCaptions() => _call('stopCaptions');
}
