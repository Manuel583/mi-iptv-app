// Lista de grabaciones programadas y su resultado.
import 'dart:async';

import 'package:flutter/material.dart';

import '../native.dart';
import '../recordings.dart';
import '../scheduler.dart';
import 'common.dart';
import 'guide_page.dart' show dayName;

Future<void> openScheduledRecordings(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ScheduledPage()));

class ScheduledPage extends StatefulWidget {
  const ScheduledPage({super.key});

  @override
  State<ScheduledPage> createState() => _ScheduledPageState();
}

class _ScheduledPageState extends State<ScheduledPage> {
  final _s = RecordingScheduler.instance;
  Timer? _timer;
  bool _batteryWarn = false;

  @override
  void initState() {
    super.initState();
    _s.load().then((_) => _s.refreshStatuses());
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _s.refreshStatuses(),
    );
    if (RecordingScheduler.isAndroid) {
      NativeBridge.batteryRestricted().then((v) {
        if (mounted) setState(() => _batteryWarn = v);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _when(ScheduledRecording r) =>
      '${dayName(r.start)} | ${hhmm(r.start)} - ${hhmm(r.stop)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Grabaciones programadas')),
      body: ListenableBuilder(
        listenable: _s,
        builder: (context, _) {
          final up = _s.upcoming;
          final past = _s.history;
          if (!_s.supported) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'La grabación programada sólo funciona en Android y Windows.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            children: [
              if (_batteryWarn)
                Card(
                  margin: const EdgeInsets.all(12),
                  child: ListTile(
                    leading: const Icon(Icons.battery_alert_outlined),
                    title: const Text('Quita el ahorro de batería'),
                    subtitle: const Text(
                      'Así Android no cortará las grabaciones cuando el móvil esté en reposo.',
                    ),
                    trailing: FilledButton(
                      onPressed: () async {
                        await NativeBridge.askBatteryExemption();
                        final v = await NativeBridge.batteryRestricted();
                        if (mounted) setState(() => _batteryWarn = v);
                      },
                      child: const Text('Permitir'),
                    ),
                  ),
                ),
              if (up.isEmpty && past.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No hay grabaciones programadas.\n\n'
                    'Abre la guía, toca un programa y pulsa "Grabar".',
                    textAlign: TextAlign.center,
                  ),
                ),
              if (up.isNotEmpty)
                const ListTile(dense: true, title: Text('PRÓXIMAS')),
              for (final r in up)
                ListTile(
                  leading: Icon(
                    r.status == RecStatus.recording
                        ? Icons.fiber_manual_record
                        : Icons.schedule,
                    color: r.status == RecStatus.recording ? Colors.red : null,
                  ),
                  title: Text(r.title),
                  subtitle: Text(
                    '${r.channelName}\n${_when(r)}'
                    '${r.status == RecStatus.recording ? ' | Grabando${r.bytes > 0 ? ' (${formatBytes(r.bytes)})' : ''}' : ''}',
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    tooltip: r.status == RecStatus.recording
                        ? 'Parar y guardar'
                        : 'Cancelar',
                    icon: Icon(
                      r.status == RecStatus.recording
                          ? Icons.stop_circle_outlined
                          : Icons.cancel_outlined,
                    ),
                    onPressed: () => _s.cancel(r),
                  ),
                ),
              if (past.isNotEmpty)
                const ListTile(dense: true, title: Text('ANTERIORES')),
              for (final r in past)
                ListTile(
                  leading: Icon(
                    switch (r.status) {
                      RecStatus.done => Icons.check_circle_outline,
                      RecStatus.failed => Icons.error_outline,
                      _ => Icons.block,
                    },
                    color: r.status == RecStatus.failed
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                  title: Text(r.title),
                  subtitle: Text(
                    '${r.channelName} | ${_when(r)}\n${recStatusLabel(r.status)}'
                    '${r.error.isNotEmpty && r.status == RecStatus.failed ? ': ${r.error}' : ''}',
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    tooltip: 'Quitar de la lista (no borra el vídeo)',
                    icon: const Icon(Icons.close),
                    onPressed: () => _s.forget(r),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 24),
                child: Text(
                  'Para que funcione, el aparato tiene que estar encendido y con Internet a la hora del programa. '
                  'Si tu proveedor sólo permite una conexión, no veas otro canal mientras graba. '
                  'Las grabaciones aparecen en "Grabaciones".',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
