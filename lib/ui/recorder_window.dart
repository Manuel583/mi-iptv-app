// Ventana pequeña que aparece en Windows cuando el Programador de tareas
// abre la app para una grabación programada (`--grabar <id>`).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../recordings.dart';
import '../scheduler.dart';
import '../stream_recorder.dart';
import 'common.dart' show hhmm;

class RecorderApp extends StatelessWidget {
  const RecorderApp({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mi IPTV | Grabando',
      debugShowCheckedModeBanner: false,
      locale: const Locale('es', 'ES'),
      supportedLocales: const [Locale('es', 'ES'), Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: _RecorderScreen(id: id),
    );
  }
}

class _RecorderScreen extends StatefulWidget {
  const _RecorderScreen({required this.id});
  final String id;

  @override
  State<_RecorderScreen> createState() => _RecorderScreenState();
}

class _RecorderScreenState extends State<_RecorderScreen> {
  final _sched = RecordingScheduler.instance;
  ScheduledRecording? _rec;
  StreamRecorder? _recorder;
  String _message = 'Preparando la grabación…';
  int _bytes = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    await _sched.load();
    final r = _sched.items.where((e) => e.id == widget.id).firstOrNull;
    if (r == null || r.status == RecStatus.cancelled) {
      _finish('Esta grabación ya no está programada.');
      return;
    }
    if (!DateTime.now().isBefore(r.stop)) {
      await _sched.writeStatus(
        r.id,
        RecStatus.failed,
        error: 'Se abrió tarde.',
      );
      _finish('El programa ya ha terminado.');
      return;
    }
    String path;
    try {
      path =
          '${(await Recordings.folder()).path}${Platform.pathSeparator}${r.fileName()}';
    } catch (e) {
      await _sched.writeStatus(r.id, RecStatus.failed, error: '$e');
      _finish('No hay ninguna carpeta donde grabar.');
      return;
    }
    final rec = StreamRecorder(
      url: r.url,
      outPath: path,
      stopAt: r.stop,
      userAgent: r.userAgent,
      referrer: r.referrer,
    );
    setState(() {
      _rec = r;
      _recorder = rec;
      _message = 'Grabando hasta las ${hhmm(r.stop)}';
    });
    await _sched.writeStatus(r.id, RecStatus.recording, path: path);
    var lastWrite = DateTime.now();
    rec.progress.listen((b) {
      if (!mounted) return;
      setState(() => _bytes = b);
      if (DateTime.now().difference(lastWrite).inSeconds > 30) {
        lastWrite = DateTime.now();
        _sched.writeStatus(r.id, RecStatus.recording, path: path, bytes: b);
      }
    });
    // Si se cancela desde la app principal, aparece el archivo ".parar".
    final stop = await _sched.stopFile(r.id);
    _poll = Timer.periodic(const Duration(seconds: 2), (_) {
      if (stop.existsSync()) {
        try {
          stop.deleteSync();
        } catch (_) {}
        rec.cancel();
      }
    });
    final ok = await rec.run();
    _poll?.cancel();
    await _sched.writeStatus(
      r.id,
      ok ? RecStatus.done : RecStatus.failed,
      path: ok ? path : '',
      bytes: rec.bytes,
      error: ok
          ? ''
          : (rec.lastError.isEmpty ? 'No llegó vídeo.' : rec.lastError),
    );
    _finish(
      ok
          ? 'Grabación guardada en ${File(path).parent.path}'
          : 'No se pudo grabar: ${rec.lastError}',
    );
  }

  void _finish(String msg) {
    if (mounted) setState(() => _message = msg);
    Timer(const Duration(seconds: 4), () => exit(0));
  }

  @override
  Widget build(BuildContext context) {
    final r = _rec;
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fiber_manual_record, color: Colors.red.shade400),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    r == null ? 'Mi IPTV' : '${r.channelName} | ${r.title}',
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(_message),
            if (_bytes > 0) Text('Guardado: ${formatBytes(_bytes)}'),
            const Spacer(),
            if (_recorder != null)
              FilledButton.tonalIcon(
                icon: const Icon(Icons.stop),
                label: const Text('Parar y guardar'),
                onPressed: () => _recorder!.cancel(),
              ),
          ],
        ),
      ),
    );
  }
}
