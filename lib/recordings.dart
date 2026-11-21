// Grabaciones guardadas en el dispositivo y posición de reproducción recordada.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'native.dart';

class Recordings {
  static Directory? _dir;

  /// Carpeta donde se guardan las grabaciones.
  /// Android: Películas/Mi IPTV | Windows: Vídeos\Mi IPTV.
  static Future<Directory> folder() async {
    if (_dir != null) return _dir!;
    final candidates = <String>[];
    if (!kIsWeb && Platform.isAndroid) {
      candidates.add('/storage/emulated/0/Movies/Mi IPTV');
      final ext = await getExternalStorageDirectory();
      if (ext != null) candidates.add('${ext.path}/Grabaciones');
    } else if (!kIsWeb && Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'];
      if (home != null) candidates.add('$home\\Videos\\Mi IPTV');
    } else {
      final home = Platform.environment['HOME'];
      if (home != null) candidates.add('$home/Videos/Mi IPTV');
    }
    candidates.add(
      '${(await getApplicationDocumentsDirectory()).path}/Grabaciones',
    );
    for (final c in candidates) {
      try {
        final d = Directory(c);
        await d.create(recursive: true);
        final probe = File('${d.path}${Platform.pathSeparator}.prueba.mkv');
        await probe.writeAsString('x');
        await probe.delete();
        return _dir = d;
      } catch (e) {
        debugPrint('No se puede grabar en $c: $e');
      }
    }
    throw const FileSystemException('No hay ninguna carpeta donde grabar');
  }

  static String _safe(String s) => s
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Ruta nueva para grabar el canal [name].
  static Future<String> newPath(String name, {int part = 1}) async {
    final d = await folder();
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${n.year}-${two(n.month)}-${two(n.day)} ${two(n.hour)}.${two(n.minute)}';
    final base = _safe(name).isEmpty ? 'Canal' : _safe(name);
    final suffix = part > 1 ? ' (parte $part)' : '';
    return '${d.path}${Platform.pathSeparator}$base $stamp$suffix.mkv';
  }

  /// Avisa al sistema de que hay un vídeo nuevo (galería de Android).
  static Future<void> publish(String path) => NativeBridge.scanFile(path);

  static Future<List<File>> list() async {
    final d = await folder();
    final files = <File>[];
    await for (final e in d.list()) {
      if (e is File) {
        final n = e.path.toLowerCase();
        if ((n.endsWith('.mkv') || n.endsWith('.ts') || n.endsWith('.mp4')) &&
            !n.contains('.prueba.')) {
          files.add(e);
        }
      }
    }
    files.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    return files;
  }
}

String formatBytes(int b) {
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  if (b < 1024 * 1024 * 1024) {
    return '${(b / 1024 / 1024).toStringAsFixed(0)} MB';
  }
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} GB';
}

String formatDuration(Duration d) {
  final neg = d.isNegative;
  d = d.abs();
  String two(int v) => v.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  final t = h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  return neg ? '-$t' : t;
}

/// Recuerda por dónde ibas en películas, capítulos y grabaciones.
class ResumeStore {
  static Map<String, dynamic>? _data;
  static File? _file;
  static Timer? _timer;

  static Future<void> _load() async {
    if (_data != null) return;
    try {
      final d = await getApplicationSupportDirectory();
      _file = File('${d.path}/posiciones.json');
      _data = await _file!.exists()
          ? (jsonDecode(await _file!.readAsString()) as Map<String, dynamic>)
          : {};
    } catch (_) {
      _data = {};
    }
  }

  static Future<Duration?> get(String key) async {
    await _load();
    final v = _data![key];
    if (v is! Map) return null;
    return Duration(seconds: (v['p'] as num).toInt());
  }

  static Future<void> set(String key, Duration pos, Duration total) async {
    await _load();
    final m = _data!;
    // Al final del vídeo, o al principio, no hace falta recordar nada.
    if (pos.inSeconds < 20 || total - pos < const Duration(seconds: 30)) {
      m.remove(key);
    } else {
      m[key] = {'p': pos.inSeconds, 't': DateTime.now().millisecondsSinceEpoch};
    }
    if (m.length > 300) {
      final keys = m.keys.toList()
        ..sort(
          (a, b) =>
              ((m[a]['t'] ?? 0) as int).compareTo((m[b]['t'] ?? 0) as int),
        );
      for (final k in keys.take(m.length - 300)) {
        m.remove(k);
      }
    }
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () async {
      try {
        await _file?.writeAsString(jsonEncode(m));
      } catch (_) {}
    });
  }
}
