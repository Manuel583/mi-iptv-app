// Hercios de la pantalla: saber a cuántos va y, si se puede, igualarlos
// a los fotogramas por segundo del vídeo para que no haya tirones.
//
// Android: lo pide al sistema (modo de pantalla preferido de la ventana).
// Windows: lo lee y lo cambia con las funciones de Windows (user32.dll).
// El cambio en Windows es temporal: se deshace al salir del reproductor
// o al cerrar la app.
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'native.dart';

class DisplayInfo {
  const DisplayInfo(this.hz, this.modes);

  /// Hercios actuales (0 si no se sabe).
  final double hz;

  /// Hercios que admite la pantalla con su resolución actual.
  final List<double> modes;
}

/// Qué tal encajan los fps del vídeo con los hercios de la pantalla.
enum SyncQuality { unknown, perfect, almost, bad }

class SyncResult {
  const SyncResult(
    this.quality,
    this.repeats,
    this.skipEverySeconds, {
    this.highRate = false,
  });
  final SyncQuality quality;

  /// No encaja, pero la pantalla va tan rápida (240 Hz con 25 fps) que el
  /// tirón es muy pequeño.
  final bool highRate;

  /// Cuántas veces se pinta cada fotograma (60 Hz con 30 fps = 2).
  final double repeats;

  /// Cada cuántos segundos hay un pequeño salto (solo si "casi").
  final double skipEverySeconds;
}

/// Compara fps y hercios. 25 fps en 50 Hz encaja; 25 fps en 60 Hz no.
SyncResult syncFor(double fps, double hz) {
  if (fps < 1 || hz < 1) return const SyncResult(SyncQuality.unknown, 0, 0);
  final ratio = hz / fps;
  final n = ratio.round();
  if (n < 1) return SyncResult(SyncQuality.bad, ratio, 0);
  final err = (ratio - n).abs() / n;
  if (err < 0.0005) return SyncResult(SyncQuality.perfect, n.toDouble(), 0);
  // 59,94 Hz con 60 fps (o 23,976 con 24) va casi bien: un saltito cada
  // muchos segundos.
  if (err < 0.012) {
    final drift =
        (hz - fps * n).abs() / n; // fotogramas por segundo de más/menos
    return SyncResult(
      SyncQuality.almost,
      n.toDouble(),
      drift > 0 ? 1 / drift : 0,
    );
  }
  // Con 4,5 o más refrescos por fotograma el desajuste es de menos de una
  // décima parte del fotograma: casi no se nota.
  if (ratio >= 4.5) {
    return SyncResult(SyncQuality.almost, ratio, 0, highRate: true);
  }
  return SyncResult(SyncQuality.bad, ratio, 0);
}

/// Frecuencias de [modes] que encajan con [fps], de mejor a peor.
/// Con [preferHigh] (PC) gana la más alta; si no (móvil), la más baja,
/// que gasta menos batería. La actual siempre va primero si encaja.
List<double> matchingModes(
  double fps,
  List<double> modes,
  double current, {
  bool preferHigh = false,
}) {
  final ok = <(double, double)>[];
  for (final m in modes.toSet()) {
    final ratio = m / fps;
    final n = ratio.round();
    if (n < 1) continue;
    final err = (ratio - n).abs() / n;
    if (err <= 0.012) ok.add((m, err));
  }
  ok.sort((a, b) {
    final ea = (a.$2 * 2000).round(), eb = (b.$2 * 2000).round();
    if (ea != eb) return ea.compareTo(eb);
    final ca = (a.$1 - current).abs() < 0.5, cb = (b.$1 - current).abs() < 0.5;
    if (ca != cb) return ca ? -1 : 1;
    return preferHigh ? b.$1.compareTo(a.$1) : a.$1.compareTo(b.$1);
  });
  return [for (final e in ok) e.$1];
}

/// Mejor frecuencia de [modes] para [fps], o null si ninguna encaja.
double? bestModeFor(double fps, List<double> modes, double current) {
  double? best;
  var bestErr = double.infinity;
  for (final m in modes) {
    final ratio = m / fps;
    final n = ratio.round();
    if (n < 1) continue;
    final err = (ratio - n).abs() / n;
    final tie = (err - bestErr).abs() <= 0.0005;
    if (err < bestErr - 0.0005 ||
        (tie && best != null && ((m - current).abs() < 0.5 || m < best))) {
      best = m;
      bestErr = err;
    }
  }
  return bestErr <= 0.012 ? best : null;
}

class DisplayRate {
  static bool get _isWindows => !kIsWeb && Platform.isWindows;
  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  static bool get canMatch => _isWindows || _isAndroid;

  /// Explicación del último intento de igualar los hercios ('' si fue bien
  /// o no hizo falta).
  static String lastNote = '';

  static Future<DisplayInfo> current() async {
    try {
      if (_isAndroid) {
        final m = await NativeBridge.displayInfo();
        final modes = ((m['modes'] as List?) ?? const [])
            .map((e) => (e as num).toDouble())
            .toList();
        return DisplayInfo(((m['hz'] ?? 0) as num).toDouble(), modes);
      }
      if (_isWindows) return _Win.info();
    } catch (e) {
      debugPrint('Hercios: $e');
    }
    return const DisplayInfo(0, []);
  }

  /// Intenta poner la pantalla a unos hercios que encajen con [fps].
  /// Devuelve los hercios elegidos o 0 si no hay ninguno que encaje.
  static Future<double> match(double fps) async {
    try {
      if (_isAndroid) return await NativeBridge.matchFrameRate(fps);
      if (_isWindows) return _Win.match(fps);
    } catch (e) {
      debugPrint('Igualar hercios: $e');
    }
    return 0;
  }

  /// Devuelve la pantalla a como estaba.
  static Future<void> reset() async {
    try {
      if (_isAndroid) await NativeBridge.resetFrameRate();
      if (_isWindows) _Win.reset();
    } catch (e) {
      debugPrint('Restaurar hercios: $e');
    }
  }
}

// ------------------------------------------------------------------ Windows

// Estructura DEVMODEW de Windows (220 bytes). Solo se usan algunos campos.
const _devModeSize = 220;
const _offSize = 68; // dmSize (WORD)
const _offFields = 72; // dmFields (DWORD)
const _offBits = 168; // dmBitsPerPel
const _offWidth = 172; // dmPelsWidth
const _offHeight = 176; // dmPelsHeight
const _offFreq = 184; // dmDisplayFrequency
const _dmDisplayFrequency = 0x00400000;
const _dmBitsPerPel = 0x00040000;
const _dmPelsWidth = 0x00080000;
const _dmPelsHeight = 0x00100000;
const _enumCurrentSettings = -1;
const _cdsFullscreen = 0x00000004; // cambio temporal
const _dispChangeSuccessful = 0;

typedef _EnumNative = Int32 Function(Pointer<Utf16>, Uint32, Pointer<Uint8>);
typedef _EnumDart = int Function(Pointer<Utf16>, int, Pointer<Uint8>);
typedef _ChangeNative = Int32 Function(
  Pointer<Utf16>,
  Pointer<Uint8>,
  Pointer<Void>,
  Uint32,
  Pointer<Void>,
);
typedef _ChangeDart = int Function(
  Pointer<Utf16>,
  Pointer<Uint8>,
  Pointer<Void>,
  int,
  Pointer<Void>,
);

class _Win {
  static final _user32 = DynamicLibrary.open('user32.dll');
  static final _enum = _user32.lookupFunction<_EnumNative, _EnumDart>(
    'EnumDisplaySettingsW',
  );
  static final _change = _user32.lookupFunction<_ChangeNative, _ChangeDart>(
    'ChangeDisplaySettingsExW',
  );
  static bool _changed = false;

  static ({int w, int h, int bits, int hz})? _read(Pointer<Uint8> dm, int i) {
    for (var k = 0; k < _devModeSize; k++) {
      dm[k] = 0;
    }
    (dm + _offSize).cast<Uint16>().value = _devModeSize;
    if (_enum(nullptr, i, dm) == 0) return null;
    int u32(int off) => (dm + off).cast<Uint32>().value;
    return (
      w: u32(_offWidth),
      h: u32(_offHeight),
      bits: u32(_offBits),
      hz: u32(_offFreq),
    );
  }

  static DisplayInfo info() {
    final dm = calloc<Uint8>(_devModeSize);
    try {
      final cur = _read(dm, _enumCurrentSettings);
      if (cur == null) return const DisplayInfo(0, []);
      final modes = <double>{};
      for (var i = 0; i < 2000; i++) {
        final m = _read(dm, i);
        if (m == null) break;
        if (m.w == cur.w && m.h == cur.h && m.hz > 1) {
          modes.add(m.hz.toDouble());
        }
      }
      final list = modes.toList()..sort();
      return DisplayInfo(cur.hz.toDouble(), list);
    } finally {
      calloc.free(dm);
    }
  }

  static String _list(List<double> l) =>
      l.map((m) => m.round().toString()).join(' | ');

  static double match(double fps) {
    DisplayRate.lastNote = '';
    final i = info();
    final cands = matchingModes(fps, i.modes, i.hz, preferHigh: true);
    if (cands.isEmpty) {
      final want = [for (var n = 1; n * fps <= 500; n++) (n * fps).round()]
          .where((h) => h >= 48)
          .take(4)
          .join(' | ');
      DisplayRate.lastNote =
          'No se ha cambiado: tu pantalla no ofrece $want Hz '
          '(admite ${_list(i.modes)} Hz)';
      return 0;
    }
    if ((cands.first - i.hz).abs() < 0.5) return cands.first;
    final dm = calloc<Uint8>(_devModeSize);
    var lastErr = 0;
    try {
      for (final hz in cands) {
        final cur = _read(dm, _enumCurrentSettings);
        if (cur == null) return 0;
        (dm + _offFreq).cast<Uint32>().value = hz.round();
        // Se indican resolución, colores y frecuencia: algunos drivers no
        // aceptan el cambio si solo se da la frecuencia.
        (dm + _offFields).cast<Uint32>().value =
            _dmDisplayFrequency | _dmPelsWidth | _dmPelsHeight | _dmBitsPerPel;
        final r = _change(nullptr, dm, nullptr, _cdsFullscreen, nullptr);
        if (r == _dispChangeSuccessful) {
          _changed = true;
          return hz;
        }
        lastErr = r;
      }
      DisplayRate.lastNote =
          'Windows no dejó cambiar a ${_list(cands)} Hz (código $lastErr)';
      return 0;
    } finally {
      calloc.free(dm);
    }
  }

  static void reset() {
    if (!_changed) return;
    _change(nullptr, nullptr, nullptr, 0, nullptr);
    _changed = false;
  }
}
