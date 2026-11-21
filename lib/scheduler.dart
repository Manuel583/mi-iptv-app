// Grabaciones programadas desde la guía.
//
// | Android: el sistema despierta la app a la hora exacta (alarma) y un
//   servicio con aviso en la barra graba la emisión, aunque la app esté
//   cerrada. Ver RecorderService.kt.
// | Windows: se crea una tarea en el Programador de tareas que abre la app
//   en modo grabación (`--grabar <id>`) a la hora indicada.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';
import 'models.dart';
import 'native.dart';
import 'recordings.dart';

enum RecStatus { pending, recording, done, failed, cancelled }

String recStatusLabel(RecStatus s) => switch (s) {
  RecStatus.pending => 'Programada',
  RecStatus.recording => 'Grabando ahora',
  RecStatus.done => 'Grabada',
  RecStatus.failed => 'No se pudo grabar',
  RecStatus.cancelled => 'Cancelada',
};

class ScheduledRecording {
  ScheduledRecording({
    required this.id,
    required this.channelKey,
    required this.channelName,
    required this.title,
    required this.url,
    required this.programmeStart,
    required this.start,
    required this.stop,
    this.userAgent = '',
    this.referrer = '',
    this.status = RecStatus.pending,
    this.path = '',
    this.error = '',
    this.bytes = 0,
  });

  final String id;
  final String channelKey;
  final String channelName;
  final String title;
  final String url;
  final String userAgent;
  final String referrer;

  /// Hora de inicio del programa en la guía (para reconocerlo).
  final DateTime programmeStart;

  /// Horas reales de grabación (con los márgenes).
  DateTime start;
  final DateTime stop;
  RecStatus status;
  String path;
  String error;
  int bytes;

  bool get isActiveOrPending =>
      status == RecStatus.pending || status == RecStatus.recording;

  Map<String, dynamic> toJson() => {
    'id': id,
    'channelKey': channelKey,
    'channelName': channelName,
    'title': title,
    'url': url,
    'userAgent': userAgent,
    'referrer': referrer,
    'programmeStart': programmeStart.millisecondsSinceEpoch,
    'start': start.millisecondsSinceEpoch,
    'stop': stop.millisecondsSinceEpoch,
    'status': status.name,
    'path': path,
    'error': error,
    'bytes': bytes,
  };

  factory ScheduledRecording.fromJson(Map<String, dynamic> j) {
    DateTime t(String k) =>
        DateTime.fromMillisecondsSinceEpoch((j[k] as num).toInt());
    return ScheduledRecording(
      id: j['id'] as String,
      channelKey: (j['channelKey'] ?? '') as String,
      channelName: (j['channelName'] ?? '') as String,
      title: (j['title'] ?? '') as String,
      url: j['url'] as String,
      userAgent: (j['userAgent'] ?? '') as String,
      referrer: (j['referrer'] ?? '') as String,
      programmeStart: t('programmeStart'),
      start: t('start'),
      stop: t('stop'),
      status: RecStatus.values.firstWhere(
        (s) => s.name == j['status'],
        orElse: () => RecStatus.pending,
      ),
      path: (j['path'] ?? '') as String,
      error: (j['error'] ?? '') as String,
      bytes: ((j['bytes'] ?? 0) as num).toInt(),
    );
  }

  /// Nombre del archivo: "Canal 2026-11-21 21.30 Programa.ts".
  String fileName() {
    String two(int v) => v.toString().padLeft(2, '0');
    final d = programmeStart;
    final stamp =
        '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}.${two(d.minute)}';
    String safe(String s) => s
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    var name = '${safe(channelName)} $stamp ${safe(title)}'.trim();
    if (name.length > 120) name = name.substring(0, 120).trim();
    return '$name.ts';
  }
}

class RecordingScheduler extends ChangeNotifier {
  RecordingScheduler._();
  static final RecordingScheduler instance = RecordingScheduler._();

  final List<ScheduledRecording> items = [];
  Directory? _dir;
  bool _loaded = false;

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isWindows => !kIsWeb && Platform.isWindows;
  bool get supported => isAndroid || isWindows;

  Future<Directory> _folder() async {
    if (_dir != null) return _dir!;
    final d = Directory(
      '${(await getApplicationSupportDirectory()).path}/programadas',
    );
    await d.create(recursive: true);
    return _dir = d;
  }

  Future<File> _listFile() async =>
      File('${(await _folder()).path}/lista.json');

  Future<File> statusFile(String id) async =>
      File('${(await _folder()).path}/$id.estado.json');

  Future<File> stopFile(String id) async =>
      File('${(await _folder()).path}/$id.parar');

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _listFile();
      if (await f.exists()) {
        final list = jsonDecode(await f.readAsString()) as List;
        items
          ..clear()
          ..addAll(
            list.map(
              (e) => ScheduledRecording.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            ),
          );
      }
    } catch (e) {
      debugPrint('No se pudieron leer las grabaciones programadas: $e');
    }
    await refreshStatuses();
  }

  Future<void> _save() async {
    try {
      final f = await _listFile();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(
        jsonEncode(items.map((e) => e.toJson()).toList()),
      );
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('No se pudieron guardar las grabaciones programadas: $e');
    }
  }

  ScheduledRecording? find(Channel c, Programme p) {
    for (final r in items) {
      if (r.channelKey == c.key &&
          r.programmeStart == p.start &&
          r.status != RecStatus.cancelled) {
        return r;
      }
    }
    return null;
  }

  List<ScheduledRecording> get upcoming =>
      items.where((r) => r.isActiveOrPending).toList()
        ..sort((a, b) => a.start.compareTo(b.start));

  List<ScheduledRecording> get history =>
      items.where((r) => !r.isActiveOrPending).toList()
        ..sort((a, b) => b.start.compareTo(a.start));

  /// Programa la grabación. Devuelve un mensaje de error o null.
  Future<String?> schedule(Channel c, Programme p) async {
    if (!supported) {
      return 'La grabación programada sólo funciona en Android y Windows.';
    }
    await load();
    final now = DateTime.now();
    if (!p.stop.isAfter(now)) return 'Ese programa ya ha terminado.';
    final s = app.settings;
    var start = p.start.subtract(Duration(minutes: s.recordBeforeMinutes));
    final stop = p.stop.add(Duration(minutes: s.recordAfterMinutes));
    if (start.isBefore(now)) start = now;
    // Dos grabaciones a la vez del mismo proveedor pueden cortarse.
    final overlap = upcoming.where(
      (r) => r.start.isBefore(stop) && r.stop.isAfter(start),
    );
    final r = ScheduledRecording(
      id: '${now.millisecondsSinceEpoch.toRadixString(36)}${c.key.hashCode.toUnsigned(16).toRadixString(36)}',
      channelKey: c.key,
      channelName: app.channelName(c),
      title: p.title.isEmpty ? 'Programa' : p.title,
      url: c.url,
      userAgent: c.userAgent.isEmpty ? app.effectiveUserAgent : c.userAgent,
      referrer: c.referrer,
      programmeStart: p.start,
      start: start,
      stop: stop,
    );
    items.add(r);
    await _save();
    notifyListeners();
    final err = await _arm(r);
    if (err != null) {
      r.status = RecStatus.failed;
      r.error = err;
      await _save();
      notifyListeners();
      return err;
    }
    if (overlap.isNotEmpty) {
      return 'Programada. Ojo: coincide con "${overlap.first.title}". '
          'Si tu proveedor sólo permite una conexión, alguna puede cortarse.';
    }
    return null;
  }

  Future<void> cancel(ScheduledRecording r) async {
    final wasRecording = r.status == RecStatus.recording;
    r.status = wasRecording ? RecStatus.done : RecStatus.cancelled;
    await _save();
    notifyListeners();
    if (isAndroid) {
      await NativeBridge.recorderCancel(r.id);
      await _pushAndroid();
    } else if (isWindows) {
      if (wasRecording) await (await stopFile(r.id)).writeAsString('1');
      await _windowsDeleteTasks([r.id]);
    }
  }

  /// Quita una grabación del historial (no borra el vídeo).
  Future<void> forget(ScheduledRecording r) async {
    items.remove(r);
    await _save();
    notifyListeners();
    try {
      final f = await statusFile(r.id);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<String?> _arm(ScheduledRecording r) async {
    if (isAndroid) {
      final ok = await _pushAndroid();
      if (!ok) return 'No se pudo programar la alarma en el móvil.';
      return null;
    }
    if (isWindows) return _windowsCreateTask(r);
    return 'No disponible en este aparato.';
  }

  // ------------------------------------------------------------- Estados

  /// Lee lo que han ido escribiendo las grabaciones (nativas o de Windows).
  Future<void> refreshStatuses() async {
    if (!supported) return;
    var changed = false;
    Map<String, dynamic> native = {};
    if (isAndroid) native = await NativeBridge.recorderStatuses();
    final now = DateTime.now();
    final finishedTasks = <String>[];
    for (final r in items) {
      if (!r.isActiveOrPending) continue;
      Map<String, dynamic>? st;
      if (isAndroid) {
        final v = native[r.id];
        if (v is Map) st = Map<String, dynamic>.from(v);
      } else {
        try {
          final f = await statusFile(r.id);
          if (await f.exists()) {
            st = Map<String, dynamic>.from(
              jsonDecode(await f.readAsString()) as Map,
            );
          }
        } catch (_) {}
      }
      if (st != null) {
        final s = RecStatus.values.firstWhere(
          (x) => x.name == st!['status'],
          orElse: () => r.status,
        );
        r.path = (st['path'] ?? r.path) as String;
        r.error = (st['error'] ?? r.error) as String;
        r.bytes = ((st['bytes'] ?? r.bytes) as num).toInt();
        if (s != r.status) {
          r.status = s;
          changed = true;
        }
      }
      // Pasó la hora y nadie empezó a grabar.
      if (r.status == RecStatus.pending &&
          now.isAfter(r.stop.add(const Duration(minutes: 2)))) {
        r.status = RecStatus.failed;
        r.error = isWindows
            ? 'El ordenador estaba apagado o la tarea no se ejecutó.'
            : 'El móvil no llegó a empezar la grabación.';
        changed = true;
      }
      // La ventana de grabación se cerró sin avisar.
      if (r.status == RecStatus.recording &&
          now.isAfter(r.stop.add(const Duration(minutes: 5)))) {
        r.status = r.path.isNotEmpty && File(r.path).existsSync()
            ? RecStatus.done
            : RecStatus.failed;
        changed = true;
      }
      if (!r.isActiveOrPending) {
        finishedTasks.add(r.id);
        if (r.status == RecStatus.done && r.path.isNotEmpty) {
          unawaited(Recordings.publish(r.path));
        }
      }
    }
    if (changed) {
      await _save();
      notifyListeners();
    }
    if (isWindows && finishedTasks.isNotEmpty) {
      unawaited(_windowsDeleteTasks(finishedTasks));
    }
  }

  // ------------------------------------------------------------- Android

  Future<bool> _pushAndroid() async {
    final list = [
      for (final r in items)
        if (r.status == RecStatus.pending)
          {
            'id': r.id,
            'url': r.url,
            'userAgent': r.userAgent,
            'referrer': r.referrer,
            'start': r.start.millisecondsSinceEpoch,
            'stop': r.stop.millisecondsSinceEpoch,
            'channel': r.channelName,
            'title': r.title,
            'fileName': r.fileName(),
          },
    ];
    return NativeBridge.recorderSchedule(jsonEncode(list));
  }

  // ------------------------------------------------------------- Windows

  static String _ps(String s) => "'${s.replaceAll("'", "''")}'";

  Future<String?> _windowsCreateTask(ScheduledRecording r) async {
    final exe = Platform.resolvedExecutable;
    final now = DateTime.now();
    if (!r.start.isAfter(now.add(const Duration(seconds: 30)))) {
      // Empieza ya: se abre directamente.
      try {
        await Process.start(exe, [
          '--grabar',
          r.id,
        ], mode: ProcessStartMode.detached);
        return null;
      } catch (e) {
        return 'No se pudo empezar a grabar: $e';
      }
    }
    String two(int v) => v.toString().padLeft(2, '0');
    final t = r.start;
    final when =
        '${t.year}-${two(t.month)}-${two(t.day)}T${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
    final script = [
      r"$ErrorActionPreference = 'Stop'",
      '\$a = New-ScheduledTaskAction -Execute ${_ps(exe)} -Argument ${_ps('--grabar ${r.id}')}',
      "\$t = New-ScheduledTaskTrigger -Once -At ([datetime]::ParseExact(${_ps(when)}, 'yyyy-MM-ddTHH:mm:ss', [Globalization.CultureInfo]::InvariantCulture))",
      r'$s = New-ScheduledTaskSettingsSet -WakeToRun -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 12)',
      "Register-ScheduledTask -TaskName ${_ps('Grabacion ${r.id}')} -TaskPath '\\Mi IPTV\\' -Action \$a -Trigger \$t -Settings \$s -Description ${_ps('Mi IPTV: ${r.channelName} | ${r.title}')} -Force | Out-Null",
    ].join('; ');
    try {
      final res = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ]);
      if (res.exitCode != 0) {
        return 'Windows no dejó crear la tarea: ${'${res.stderr}'.trim()}';
      }
      return null;
    } catch (e) {
      return 'Windows no dejó crear la tarea: $e';
    }
  }

  Future<void> _windowsDeleteTasks(List<String> ids) async {
    if (ids.isEmpty) return;
    final script = ids
        .map(
          (id) =>
              "Unregister-ScheduledTask -TaskName ${_ps('Grabacion $id')} -TaskPath '\\Mi IPTV\\' -Confirm:\$false -ErrorAction SilentlyContinue",
        )
        .join('; ');
    try {
      await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ]);
    } catch (_) {}
  }

  /// Escribe el estado de una grabación (lo usa el proceso que graba).
  Future<void> writeStatus(
    String id,
    RecStatus status, {
    String path = '',
    String error = '',
    int bytes = 0,
  }) async {
    try {
      await (await statusFile(id)).writeAsString(
        jsonEncode({
          'status': status.name,
          'path': path,
          'error': error,
          'bytes': bytes,
        }),
      );
    } catch (_) {}
  }
}
