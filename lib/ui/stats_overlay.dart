// Esquina con los datos de la reproducción: fotogramas por segundo del
// vídeo, hercios de la pantalla, si van coordinados y la señal que llega.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:media_kit/media_kit.dart';

import '../display_rate.dart';

/// Lee cada segundo los datos del reproductor y de la pantalla.
class PlaybackStats extends ChangeNotifier {
  PlaybackStats(this.player);

  final Player player;
  Timer? _timer;
  int _ticks = 0;
  bool _disposed = false;

  // Vídeo
  double fps = 0; // fotogramas por segundo del vídeo
  int width = 0;
  int height = 0;
  String codec = '';
  String hwdec = '';
  double videoBitrate = 0; // bits por segundo
  String audioCodec = '';
  int audioChannels = 0;
  int audioRate = 0;

  // Fluidez
  int droppedOutput = 0; // fotogramas que no llegaron a pintarse
  int droppedDecoder = 0; // fotogramas que el decodificador no pudo a tiempo
  double avsync = 0; // desfase entre sonido e imagen (segundos)
  double buffer = 0; // segundos guardados por delante
  double paintFps = 0; // veces por segundo que la app repinta la imagen

  // Pantalla
  double hz = 0;
  List<double> modes = const [];

  int _frames = 0;
  DateTime _framesSince = DateTime.now();

  void start() {
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
    _poll();
  }

  void _onTimings(List<FrameTiming> t) => _frames += t.length;

  Future<String> _get(NativePlayer p, String k) async {
    try {
      return await p.getProperty(k);
    } catch (_) {
      return '';
    }
  }

  Future<void> _poll() async {
    final p = player.platform;
    if (p is! NativePlayer) return;
    double d(String s) => double.tryParse(s) ?? 0;
    int i(String s) => int.tryParse(s) ?? 0;

    final est = d(await _get(p, 'estimated-vf-fps'));
    final cont = d(await _get(p, 'container-fps'));
    // La cifra del contenedor es la oficial; la estimada sirve si falta.
    fps = cont > 0 ? cont : est;
    width = i(await _get(p, 'video-params/w'));
    height = i(await _get(p, 'video-params/h'));
    codec = await _get(p, 'video-format');
    hwdec = await _get(p, 'hwdec-current');
    videoBitrate = d(await _get(p, 'video-bitrate'));
    audioCodec = await _get(p, 'audio-codec-name');
    audioChannels = i(await _get(p, 'audio-params/channel-count'));
    audioRate = i(await _get(p, 'audio-params/samplerate'));
    droppedOutput = i(await _get(p, 'frame-drop-count'));
    droppedDecoder = i(await _get(p, 'decoder-frame-drop-count'));
    avsync = d(await _get(p, 'avsync'));
    buffer = d(await _get(p, 'demuxer-cache-duration'));

    final now = DateTime.now();
    final secs = now.difference(_framesSince).inMilliseconds / 1000;
    if (secs >= 1) {
      paintFps = _frames / secs;
      _frames = 0;
      _framesSince = now;
    }

    if (_ticks++ % 3 == 0) {
      final info = await DisplayRate.current();
      hz = info.hz;
      modes = info.modes;
    }
    if (!_disposed) notifyListeners();
  }

  SyncResult get sync => syncFor(fps, hz);

  Future<void> refreshDisplay() async {
    final info = await DisplayRate.current();
    hz = info.hz;
    modes = info.modes;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }
}

String _num(double v, [int dec = 2]) {
  if (v == v.roundToDouble()) return v.round().toString();
  return v.toStringAsFixed(dec).replaceAll('.', ',');
}

String _resName(int w, int h) {
  if (h >= 4000 || w >= 7000) return '8K';
  if (h >= 2000 || w >= 3500) return '4K';
  if (h >= 1400) return '1440p';
  if (h >= 1000) return '1080p';
  if (h >= 700) return '720p';
  if (h > 0) return '${h}p';
  return '';
}

String _hwName(String h) {
  if (h.isEmpty || h == 'no') return 'por software (procesador)';
  if (h.endsWith('-copy')) return 'por hardware con copia ($h)';
  return 'por hardware directo ($h)';
}

/// La esquinita. Pulsándola se abren o cierran los detalles.
class StatsOverlay extends StatefulWidget {
  const StatsOverlay({
    super.key,
    required this.stats,
    required this.liveDelay,
    this.matchedHz,
  });

  final PlaybackStats stats;

  /// Segundos por detrás del directo (por haber retrocedido o pausado).
  final double Function() liveDelay;

  /// Hercios que la app puso en la pantalla para igualar el vídeo.
  final double? matchedHz;

  @override
  State<StatsOverlay> createState() => _StatsOverlayState();
}

class _StatsOverlayState extends State<StatsOverlay> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.stats,
      builder: (context, _) {
        final s = widget.stats;
        final sync = s.sync;
        final (icon, color) = switch (sync.quality) {
          SyncQuality.perfect => (Icons.check_circle, Colors.greenAccent),
          SyncQuality.almost => (Icons.remove_circle, Colors.amberAccent),
          SyncQuality.bad => (Icons.cancel, Colors.redAccent),
          SyncQuality.unknown => (Icons.help, Colors.white54),
        };
        final fpsText = s.fps > 0 ? '${_num(s.fps)} fps' : '? fps';
        final hzText = s.hz > 0 ? '${_num(s.hz, 1)} Hz' : '? Hz';
        final res = _resName(s.width, s.height);
        const style = TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontFeatures: [FontFeature.tabularFigures()],
        );

        final lines = <String>[];
        if (_open) {
          lines.add('Coordinación: ${_syncText(sync, s)}');
          if (DisplayRate.lastNote.isNotEmpty) {
            lines.add(DisplayRate.lastNote);
          } else if (widget.matchedHz != null && widget.matchedHz! > 0) {
            lines.add(
              'Pantalla puesta a ${_num(widget.matchedHz!, 1)} Hz para este vídeo',
            );
          }
          if (s.modes.isNotEmpty) {
            lines.add(
              'Hercios que admite la pantalla: ${s.modes.map((m) => _num(m, 1)).join(' | ')}',
            );
          }
          lines.add('');
          lines.add('SEÑAL DE ENTRADA');
          if (s.width > 0) {
            lines.add(
              'Imagen: ${s.width}x${s.height} ${res.isEmpty ? '' : '($res)'}',
            );
          }
          if (s.codec.isNotEmpty) {
            lines.add('Vídeo: ${s.codec.toUpperCase()} a ${_num(s.fps)} fps');
          }
          if (s.videoBitrate > 0) {
            lines.add(
              'Calidad de la señal: ${_num(s.videoBitrate / 1e6, 1)} Mbit/s',
            );
          }
          if (s.audioCodec.isNotEmpty) {
            lines.add(
              'Sonido: ${s.audioCodec.toUpperCase()}'
              '${s.audioChannels > 0 ? ' | ${s.audioChannels} canales' : ''}'
              '${s.audioRate > 0 ? ' | ${_num(s.audioRate / 1000, 1)} kHz' : ''}',
            );
          }
          lines.add('Decodificación: ${_hwName(s.hwdec)}');
          lines.add('');
          lines.add('RETRASO Y FLUIDEZ');
          final delay = widget.liveDelay();
          lines.add(
            delay > 1
                ? 'Por detrás del directo: ${_num(delay, 0)} s (has pausado o retrocedido)'
                : 'Por detrás del directo: lo mínimo que permite el canal',
          );
          lines.add('Búfer guardado: ${_num(s.buffer, 1)} s');
          lines.add('Desfase sonido e imagen: ${(s.avsync * 1000).round()} ms');
          lines.add(
            'Fotogramas perdidos: ${s.droppedOutput + s.droppedDecoder}'
            '${s.droppedDecoder > 0 ? ' (${s.droppedDecoder} por el decodificador)' : ''}',
          );
          if (s.paintFps > 0) {
            lines.add(
              'La app repinta: ${_num(s.paintFps, 0)} veces por segundo',
            );
          }
          lines.add('');
          lines.add('El retraso propio de la pantalla (input lag) no');
          lines.add('se puede medir desde la app: activa el modo Juego');
          lines.add('de la tele o el monitor para reducirlo.');
        }

        return GestureDetector(
          onTap: () => setState(() => _open = !_open),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$fpsText | $hzText${res.isEmpty ? '' : ' | $res'}',
                      style: style.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 6),
                    Icon(icon, color: color, size: 14),
                    if (s.droppedDecoder + s.droppedOutput > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${s.droppedDecoder + s.droppedOutput} perdidos',
                        style: style.copyWith(color: Colors.orangeAccent),
                      ),
                    ],
                  ],
                ),
                for (final l in lines)
                  Text(
                    l,
                    style: l == l.toUpperCase() && l.isNotEmpty
                        ? style.copyWith(color: Colors.white60, fontSize: 11)
                        : style,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _syncText(SyncResult r, PlaybackStats s) => switch (r.quality) {
    SyncQuality.perfect =>
      r.repeats == 1
          ? 'sí, un fotograma por cada refresco'
          : 'sí, cada fotograma se muestra ${r.repeats.round()} veces',
    SyncQuality.almost when r.highRate =>
      'casi: ${_num(s.fps)} fps no cabe exacto en ${_num(s.hz, 1)} Hz, '
          'pero con tantos hercios el tirón apenas se nota',
    SyncQuality.almost =>
      'casi${r.skipEverySeconds > 0 ? ', un pequeño salto cada ${_num(r.skipEverySeconds, 0)} s' : ''}',
    SyncQuality.bad =>
      'no: ${_num(s.fps)} fps no cabe en ${_num(s.hz, 1)} Hz, verás pequeños tirones',
    SyncQuality.unknown => 'esperando datos',
  };
}
