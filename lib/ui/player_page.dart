import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import '../app_state.dart';
import '../cast.dart';
import '../models.dart';
import '../native.dart';
import '../recordings.dart';
import 'cast_sheet.dart';
import 'common.dart';
import 'mosaic_page.dart';

bool get _isWindows => !kIsWeb && Platform.isWindows;
bool get _isAndroid => !kIsWeb && Platform.isAndroid;

/// Configura libmpv para emisiones en directo por internet.
Future<void> configureLivePlayer(
  Player player, {
  bool muted = false,
  bool timeshift = false,
}) async {
  final p = player.platform;
  if (p is! NativePlayer) return;
  Future<void> set(String k, String v) async {
    try {
      await p.setProperty(k, v);
    } catch (e) {
      debugPrint('mpv $k: $e');
    }
  }

  await set('network-timeout', '20');
  await set('tls-verify', 'no');
  await set('cache', 'yes');
  final minutes = timeshift ? app.settings.timeshiftMinutes : 0;
  if (minutes > 0) {
    // Unos 8 Mbit/s: 60 MB por minuto. Se guarda en disco, no en memoria.
    final bytes = minutes * 60 * 1024 * 1024;
    try {
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}${Platform.pathSeparator}directo');
      await dir.create(recursive: true);
      await set('demuxer-cache-dir', dir.path);
      await set('cache-on-disk', 'yes');
    } catch (e) {
      debugPrint('Caché en disco: $e');
    }
    await set('demuxer-max-back-bytes', '$bytes');
    await set('demuxer-max-bytes', '$bytes');
    await set('cache-secs', '${minutes * 60}');
  } else {
    await set('demuxer-max-bytes', '64MiB');
    await set('demuxer-max-back-bytes', '16MiB');
  }
  await set('volume-max', '200');
  await set('hls-bitrate', 'max');
  await set(
    'stream-lavf-o',
    'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=5',
  );
  await set('user-agent', app.effectiveUserAgent);
  // Idiomas preferidos: mpv elige solo la pista que coincida.
  await set('alang', mpvLanguages(app.settings.audioLanguage));
  await set('slang', mpvLanguages(app.settings.subtitleLanguage));
}

/// Idiomas que se pueden elegir como preferidos (código -> nombre).
const preferredLanguages = <String, String>{
  'es': 'Español',
  'en': 'Inglés',
  'ca': 'Catalán',
  'eu': 'Euskera',
  'gl': 'Gallego',
  'fr': 'Francés',
  'pt': 'Portugués',
  'it': 'Italiano',
  'de': 'Alemán',
};

/// Todas las formas en que las emisiones suelen marcar un idioma.
String mpvLanguages(String code) => switch (code) {
  '' => '',
  'es' => 'es,spa,esp,cas,spanish,español',
  'en' => 'en,eng,english',
  'ca' => 'ca,cat,catalan',
  'eu' => 'eu,eus,baq,basque',
  'gl' => 'gl,glg,galician',
  'fr' => 'fr,fre,fra,french',
  'pt' => 'pt,por,portuguese',
  'it' => 'it,ita,italian',
  'de' => 'de,ger,deu,german',
  _ => code,
};

/// Convierte la marca de idioma de una pista (spa, es, cas…) en un código
/// de [preferredLanguages], o '' si no se reconoce.
String preferredCodeFor(String? lang) {
  final l = (lang ?? '').toLowerCase().trim();
  if (l.isEmpty) return '';
  for (final code in preferredLanguages.keys) {
    if (mpvLanguages(code).split(',').contains(l)) return code;
  }
  return '';
}

/// Abre un canal en un reproductor, con su User-Agent y Referer si los tiene.
Future<void> openChannelIn(Player player, Channel c) async {
  final p = player.platform;
  if (p is NativePlayer) {
    try {
      await p.setProperty(
        'user-agent',
        c.userAgent.isNotEmpty ? c.userAgent : app.effectiveUserAgent,
      );
      await p.setProperty('referrer', c.referrer);
    } catch (_) {}
  }
  await player.open(Media(c.url), play: true);
}

String languageName(String? code) {
  const names = {
    'spa': 'Español',
    'es': 'Español',
    'esp': 'Español',
    'eng': 'Inglés',
    'en': 'Inglés',
    'ara': 'Árabe',
    'ar': 'Árabe',
    'fre': 'Francés',
    'fra': 'Francés',
    'fr': 'Francés',
    'ger': 'Alemán',
    'deu': 'Alemán',
    'de': 'Alemán',
    'ita': 'Italiano',
    'it': 'Italiano',
    'por': 'Portugués',
    'pt': 'Portugués',
    'rus': 'Ruso',
    'ru': 'Ruso',
    'tur': 'Turco',
    'tr': 'Turco',
    'heb': 'Hebreo',
    'he': 'Hebreo',
    'per': 'Persa',
    'fas': 'Persa',
    'fa': 'Persa',
    'chi': 'Chino',
    'zho': 'Chino',
    'zh': 'Chino',
    'jpn': 'Japonés',
    'ja': 'Japonés',
    'kor': 'Coreano',
    'ko': 'Coreano',
    'cat': 'Catalán',
    'ca': 'Catalán',
    'baq': 'Euskera',
    'eus': 'Euskera',
    'eu': 'Euskera',
    'glg': 'Gallego',
    'gl': 'Gallego',
    'dut': 'Neerlandés',
    'nld': 'Neerlandés',
    'nl': 'Neerlandés',
    'pol': 'Polaco',
    'pl': 'Polaco',
    'ukr': 'Ucraniano',
    'uk': 'Ucraniano',
    'gre': 'Griego',
    'ell': 'Griego',
    'el': 'Griego',
    'hin': 'Hindi',
    'hi': 'Hindi',
    'urd': 'Urdu',
    'ur': 'Urdu',
    'qaa': 'Versión original',
    'mul': 'Varios idiomas',
    'und': 'Sin especificar',
  };
  if (code == null || code.isEmpty) return '';
  return names[code.toLowerCase()] ?? code.toUpperCase();
}

String trackLabel(int i, String? lang, String? title, {String? codec}) {
  final parts = <String>[];
  final l = languageName(lang);
  if (l.isNotEmpty) parts.add(l);
  if (title != null && title.isNotEmpty && title != lang) parts.add(title);
  if (parts.isEmpty) parts.add('Pista ${i + 1}');
  if (codec != null && codec.isNotEmpty) parts.add(codec);
  return parts.join(' | ');
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.channels,
    required this.initialIndex,
  });
  final List<Channel> channels;
  final int initialIndex;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  late final Player _player = Player(
    configuration: const PlayerConfiguration(
      title: 'Mi IPTV',
      bufferSize: 32 * 1024 * 1024,
    ),
  );
  late final VideoController _video = VideoController(
    _player,
    configuration: VideoControllerConfiguration(
      enableHardwareAcceleration: app.settings.hardwareDecoding,
    ),
  );

  late int _index = widget.initialIndex.clamp(0, widget.channels.length - 1);
  Channel get _channel => widget.channels[_index];

  final _focus = FocusNode(debugLabel: 'reproductor');
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _subs = <StreamSubscription>[];

  bool _controls = true;
  Timer? _hideTimer;
  bool _banner = true;
  Timer? _bannerTimer;

  String? _status;
  int _attempts = 0;
  Timer? _reconnectTimer;
  Timer? _watchdog;
  DateTime _openedAt = DateTime.now();
  DateTime _lastProgress = DateTime.now();
  Duration _lastPos = Duration.zero;
  bool _userPaused = false;
  bool _pausedByLifecycle = false;

  bool _buffering = true;
  bool _playing = false;
  double _volume = 100;
  bool _muted = false;
  BoxFit _fit = BoxFit.contain;

  // Windows
  bool _mini = false;
  bool _fullscreen = false;
  Rect? _savedBounds;
  bool _wasMaximized = false;

  bool _inPip = false;

  // Retroceder en directo (timeshift) y barra de tiempo
  Timer? _cacheTimer;
  double _cacheStart = 0;
  double _cacheEnd = 0;
  double _posSec = 0;
  double _liveGap = 0;
  bool _shifted = false;
  double? _drag;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _resumeChecked = false;
  DateTime _lastResumeSave = DateTime.now();

  bool get _isLocal => !_channel.url.contains('://');
  bool get _isVod => _duration > Duration.zero;
  bool get _canShift =>
      !_isVod &&
      app.settings.timeshiftMinutes > 0 &&
      _cacheEnd > _cacheStart + 2;
  double get _liveEdge => math.max(_cacheStart, _cacheEnd - _liveGap);
  double get _delay => _shifted ? math.max(0, _liveEdge - _posSec) : 0;

  // Grabación
  String? _recPath;
  int _recPart = 1;
  DateTime? _recSince;
  final _recFiles = <String>[];
  bool get _recording => _recPath != null;

  // Emitir en la tele
  CastDevice? _cast;
  bool _castRelay = false;

  // Imagen y sonido
  double _brightness = 0;
  double _contrast = 0;
  double _saturation = 0;
  double _zoom = 1;
  double? _aspect;
  double _audioDelay = 0;
  bool _normalize = false;
  double _subDelay = 0;
  double _subScale = 1;
  double _rate = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subs.addAll([
      _player.stream.error.listen(_onError),
      _player.stream.completed.listen((done) {
        if (done) _onStreamEnded();
      }),
      _player.stream.position.listen(_onPosition),
      _player.stream.duration.listen(_onDuration),
      _player.stream.buffering.listen((b) {
        if (mounted) setState(() => _buffering = b);
      }),
      _player.stream.playing.listen((p) {
        if (mounted) setState(() => _playing = p);
      }),
      _player.stream.tracks.listen((_) {
        if (mounted) setState(() {});
      }),
      _player.stream.track.listen((_) {
        if (mounted) setState(() {});
      }),
    ]);
    NativeBridge.inPip.addListener(_onPipChanged);
    NativeBridge.onStopRequested = _stopFromNotification;
    if (_isAndroid) {
      NativeBridge.setPipEnabled(app.settings.pipOnLeave);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    _watchdog = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _checkStall(),
    );
    _cacheTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _pollCache(),
    );
    _start();
    _scheduleHide();
  }

  Future<void> _start() async {
    await configureLivePlayer(_player, timeshift: true);
    await _open();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final s in _subs) {
      s.cancel();
    }
    _hideTimer?.cancel();
    _bannerTimer?.cancel();
    _reconnectTimer?.cancel();
    _watchdog?.cancel();
    _cacheTimer?.cancel();
    _saveResume();
    if (_recording) {
      final files = List.of(_recFiles);
      Future.delayed(const Duration(seconds: 2), () {
        for (final f in files) {
          Recordings.publish(f);
        }
      });
    }
    // Si se estaba emitiendo, la tele sigue con el canal.
    _cast?.close();
    NativeBridge.inPip.removeListener(_onPipChanged);
    if (NativeBridge.onStopRequested == _stopFromNotification) {
      NativeBridge.onStopRequested = null;
    }
    if (_isAndroid) {
      NativeBridge.setPipEnabled(false);
      NativeBridge.stopPlaybackService();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    if (_isWindows) {
      if (_mini) _restoreWindow();
      if (_fullscreen) windowManager.setFullScreen(false);
    }
    _player.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ Reproducción

  Future<void> _open({bool reconnecting = false}) async {
    final c = _channel;
    _openedAt = DateTime.now();
    _lastProgress = _openedAt;
    _lastPos = Duration.zero;
    _userPaused = false;
    _shifted = false;
    _liveGap = 0;
    _cacheStart = _cacheEnd = _posSec = 0;
    if (!reconnecting) {
      _attempts = 0;
      _status = null;
      _reconnectTimer?.cancel();
      _resumeChecked = false;
      _duration = Duration.zero;
      _position = Duration.zero;
      if (_recording) await _stopRecording();
      if (!_isLocal) app.setLastChannel(c);
      _showBanner();
      if (_cast != null) {
        _userPaused = true;
        try {
          await _sendToCast(_cast!, c, _castRelay);
        } catch (e) {
          if (mounted) {
            showMessage(context, 'La tele no ha podido abrir el canal: $e');
          }
        }
        if (mounted) setState(() {});
        return;
      }
      if (_isAndroid && app.settings.backgroundAudio) {
        NativeBridge.startPlaybackService(app.channelName(c));
      }
    } else if (_recording) {
      // Tras un corte la grabación continúa en otro archivo.
      _recPart++;
      final path = await Recordings.newPath(app.channelName(c), part: _recPart);
      _recPath = path;
      _recFiles.add(path);
      await _setRecord(path);
    }
    if (mounted) setState(() => _buffering = true);
    try {
      await openChannelIn(_player, c);
    } catch (e) {
      _onError('$e');
    }
  }

  // ------------------------------------------------------------ Tiempo

  void _onDuration(Duration d) {
    if (!mounted) return;
    setState(() => _duration = d);
    if (d > Duration.zero && !_resumeChecked) {
      _resumeChecked = true;
      _tryResume();
    }
  }

  Future<void> _tryResume() async {
    final key = _channel.url;
    final pos = await ResumeStore.get(key);
    if (pos == null || !mounted || _channel.url != key) return;
    await _player.seek(pos);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Continúa donde lo dejaste (${formatDuration(pos)})'),
          action: SnackBarAction(
            label: 'Desde el principio',
            onPressed: () => _player.seek(Duration.zero),
          ),
        ),
      );
  }

  void _saveResume() {
    if (_duration > Duration.zero) {
      ResumeStore.set(_channel.url, _player.state.position, _duration);
    }
  }

  Future<void> _pollCache() async {
    final p = _player.platform;
    if (p is! NativePlayer || _cast != null || _isVod) return;
    if (app.settings.timeshiftMinutes == 0) return;
    try {
      final pos = double.tryParse(await p.getProperty('time-pos'));
      final raw = await p.getProperty('demuxer-cache-state');
      if (pos == null || raw.isEmpty) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      double? start, end;
      for (final r in (j['seekable-ranges'] as List?) ?? const []) {
        final a = (r['start'] as num).toDouble();
        final b = (r['end'] as num).toDouble();
        if (start == null || (pos >= a && pos <= b + 1)) {
          start = a;
          end = b;
        }
      }
      end ??= (j['cache-end'] as num?)?.toDouble();
      if (end == null) return;
      start ??= pos;
      final behind = math.max(0.0, end - pos);
      if (!_shifted && _playing) {
        _liveGap = _liveGap == 0 ? behind : _liveGap * 0.9 + behind * 0.1;
      }
      if (_shifted && _playing && end - _liveGap - pos < 3) _shifted = false;
      if (!mounted) return;
      setState(() {
        _cacheStart = start!;
        _cacheEnd = end!;
        _posSec = pos;
      });
    } catch (_) {}
  }

  Future<void> _seekAbs(double secs) async {
    final p = _player.platform;
    if (p is NativePlayer) {
      await p.command(['seek', secs.toStringAsFixed(2), 'absolute']);
    }
  }

  Future<void> _seekBy(int secs) async {
    _showControls();
    if (_isVod) {
      var t = _player.state.position + Duration(seconds: secs);
      if (t < Duration.zero) t = Duration.zero;
      if (t > _duration) t = _duration;
      await _player.seek(t);
      return;
    }
    if (_cast != null) return;
    if (app.settings.timeshiftMinutes == 0) {
      showMessage(context, 'Activa "Retroceder en directo" en Ajustes');
      return;
    }
    if (!_canShift) {
      showMessage(context, 'Todavía no hay nada guardado de este canal');
      return;
    }
    var target = _posSec + secs;
    if (target >= _liveEdge - 1) {
      await _goLive();
      return;
    }
    if (target < _cacheStart + 1) {
      target = _cacheStart + 1;
      showMessage(context, 'Has llegado al principio de lo guardado');
    }
    setState(() {
      _shifted = true;
      _posSec = target;
    });
    await _seekAbs(target);
  }

  Future<void> _goLive() async {
    _showControls();
    setState(() => _shifted = false);
    if (_cacheEnd > 0) await _seekAbs(_liveEdge);
    if (!_player.state.playing) _togglePlay();
  }

  // ------------------------------------------------------------ Grabar

  Future<void> _setRecord(String path) async {
    final p = _player.platform;
    if (p is NativePlayer) await p.setProperty('stream-record', path);
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      await _stopRecording();
      return;
    }
    if (_isLocal) return;
    if (_cast != null) {
      showMessage(context, 'Deja de emitir para poder grabar');
      return;
    }
    try {
      final path = await Recordings.newPath(app.channelName(_channel));
      await _setRecord(path);
      if (!mounted) return;
      setState(() {
        _recPath = path;
        _recPart = 1;
        _recSince = DateTime.now();
        _recFiles
          ..clear()
          ..add(path);
      });
      if (_isAndroid) {
        NativeBridge.startPlaybackService(
          'Grabando ${app.channelName(_channel)}',
        );
      }
      final folder = (await Recordings.folder()).path;
      if (mounted) showMessage(context, 'Grabando. Se guardará en $folder');
    } catch (e) {
      if (mounted) showMessage(context, 'No se puede grabar: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    await _setRecord('');
    final files = List.of(_recFiles);
    final since = _recSince;
    if (mounted) {
      setState(() {
        _recPath = null;
        _recSince = null;
      });
    }
    await Future.delayed(const Duration(milliseconds: 500));
    for (final f in files) {
      await Recordings.publish(f);
    }
    if (_isAndroid) {
      if (app.settings.backgroundAudio) {
        NativeBridge.startPlaybackService(app.channelName(_channel));
      } else {
        NativeBridge.stopPlaybackService();
      }
    }
    if (mounted) {
      final len = since == null
          ? ''
          : ' (${formatDuration(DateTime.now().difference(since))})';
      showMessage(context, 'Grabación guardada$len. Está en Grabaciones.');
    }
  }

  // ------------------------------------------------------------ Emitir

  Future<void> _sendToCast(CastDevice d, Channel c, bool relay) async {
    final url = relay
        ? await StreamRelay.instance.urlFor(c, d, app.effectiveUserAgent)
        : c.url;
    await d.play(
      url,
      title: app.channelName(c),
      mime: guessMime(c.url, d.kind),
    );
  }

  Future<void> _openCast() async {
    if (_isLocal) {
      showMessage(context, 'Las grabaciones no se pueden emitir todavía');
      return;
    }
    if (_cast != null) {
      final stop = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.cast_connected),
                title: Text('Emitiendo en ${_cast!.name}'),
                subtitle: const Text(
                  'Cambia de canal aquí y la tele lo cambiará también',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.stop_circle_outlined),
                title: const Text('Dejar de emitir y ver aquí'),
                onTap: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ),
      );
      if (stop == true) await _stopCast();
      return;
    }
    final c = _channel;
    final pick = await showModalBottomSheet<(CastDevice, bool)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => CastSheet(
        needsRelay: c.userAgent.isNotEmpty || c.referrer.isNotEmpty,
      ),
    );
    if (pick == null || !mounted) return;
    final (device, relay) = pick;
    setState(() => _status = 'Conectando con ${device.name}…');
    try {
      await _sendToCast(device, c, relay);
      if (_recording) await _stopRecording();
      _userPaused = true;
      _reconnectTimer?.cancel();
      await _player.stop();
      if (!mounted) return;
      setState(() {
        _cast = device;
        _castRelay = relay;
        _status = null;
      });
      showMessage(context, 'Emitiendo en ${device.name}');
    } catch (e) {
      device.close();
      if (!mounted) return;
      setState(() => _status = null);
      showMessage(
        context,
        relay
            ? 'No se ha podido emitir en ${device.name}: $e'
            : 'No se ha podido emitir en ${device.name}. Prueba a activar '
                  '"Pasar la señal por este dispositivo".',
      );
    }
  }

  Future<void> _stopCast() async {
    final d = _cast;
    if (d == null) return;
    setState(() => _cast = null);
    try {
      await d.stop();
    } catch (_) {}
    d.close();
    unawaited(StreamRelay.instance.stop());
    await _open();
  }

  // ------------------------------------------------------------ Imagen y sonido

  List<double> get _colorMatrix {
    final c = 1 + _contrast;
    final sat = 1 + _saturation;
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final off = 128 * (1 - c) + _brightness * 100;
    List<double> row(double r, double g, double b) => [
      c * r,
      c * g,
      c * b,
      0,
      off,
    ];
    return [
      ...row((1 - sat) * lr + sat, (1 - sat) * lg, (1 - sat) * lb),
      ...row((1 - sat) * lr, (1 - sat) * lg + sat, (1 - sat) * lb),
      ...row((1 - sat) * lr, (1 - sat) * lg, (1 - sat) * lb + sat),
      0,
      0,
      0,
      1,
      0,
    ];
  }

  Future<void> _mpv(String k, String v) async {
    final p = _player.platform;
    if (p is NativePlayer) {
      try {
        await p.setProperty(k, v);
      } catch (e) {
        debugPrint('mpv $k: $e');
      }
    }
  }

  Future<void> _openTune() async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void upd(VoidCallback fn) {
            setState(fn);
            setSheet(() {});
          }

          Widget slider(
            String label,
            double value,
            double min,
            double max,
            String text,
            ValueChanged<double> onChanged, {
            int? divisions,
          }) => ListTile(
            dense: true,
            title: Text('$label: $text'),
            subtitle: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          );

          String pct(double v) => '${v >= 0 ? '+' : ''}${(v * 100).round()} %';
          final canRate = _isVod || _shifted;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(title: Text('Sonido')),
                  slider(
                    'Volumen',
                    _muted ? 0 : _volume,
                    0,
                    200,
                    '${(_muted ? 0 : _volume).round()} %',
                    (v) => upd(() => _setVolume(v)),
                    divisions: 40,
                  ),
                  SwitchListTile(
                    dense: true,
                    title: const Text('Igualar volumen'),
                    subtitle: const Text(
                      'Sube lo que se oye bajo y baja lo que se oye muy alto',
                    ),
                    value: _normalize,
                    onChanged: (v) {
                      upd(() => _normalize = v);
                      _mpv(
                        'af',
                        v ? 'lavfi=[dynaudnorm=f=250:g=31:p=0.9]' : '',
                      );
                    },
                  ),
                  slider(
                    'Retraso del sonido',
                    _audioDelay,
                    -3,
                    3,
                    '${_audioDelay.toStringAsFixed(1).replaceAll('.', ',')} s',
                    (v) {
                      upd(() => _audioDelay = (v * 10).round() / 10);
                      _mpv('audio-delay', _audioDelay.toString());
                    },
                    divisions: 60,
                  ),
                  if (canRate)
                    slider(
                      'Velocidad',
                      _rate,
                      0.5,
                      2,
                      '${_rate.toStringAsFixed(2).replaceAll('.', ',')}x',
                      (v) {
                        upd(() => _rate = v);
                        _player.setRate(v);
                      },
                      divisions: 6,
                    ),
                  const Divider(),
                  const ListTile(title: Text('Imagen')),
                  slider(
                    'Brillo',
                    _brightness,
                    -1,
                    1,
                    pct(_brightness),
                    (v) => upd(() => _brightness = v),
                    divisions: 40,
                  ),
                  slider(
                    'Contraste',
                    _contrast,
                    -1,
                    1,
                    pct(_contrast),
                    (v) => upd(() => _contrast = v),
                    divisions: 40,
                  ),
                  slider(
                    'Color',
                    _saturation,
                    -1,
                    1,
                    pct(_saturation),
                    (v) => upd(() => _saturation = v),
                    divisions: 40,
                  ),
                  slider(
                    'Zoom',
                    _zoom,
                    1,
                    2,
                    '${(_zoom * 100).round()} %',
                    (v) => upd(() => _zoom = v),
                    divisions: 20,
                  ),
                  ListTile(
                    dense: true,
                    title: const Text('Formato'),
                    subtitle: Wrap(
                      spacing: 8,
                      children: [
                        for (final (label, value) in const [
                          ('Original', null),
                          ('16:9', 16 / 9),
                          ('4:3', 4 / 3),
                          ('21:9', 21 / 9),
                        ])
                          ChoiceChip(
                            label: Text(label),
                            selected: _aspect == value,
                            onSelected: (_) => upd(() => _aspect = value),
                          ),
                        for (final (label, fit) in const [
                          ('Ajustar', BoxFit.contain),
                          ('Rellenar', BoxFit.cover),
                          ('Estirar', BoxFit.fill),
                        ])
                          ChoiceChip(
                            label: Text(label),
                            selected: _fit == fit,
                            onSelected: (_) => upd(() => _fit = fit),
                          ),
                      ],
                    ),
                  ),
                  if (_subTracks.isNotEmpty) ...[
                    const Divider(),
                    const ListTile(title: Text('Subtítulos')),
                    slider(
                      'Tamaño',
                      _subScale,
                      0.5,
                      2,
                      '${(_subScale * 100).round()} %',
                      (v) {
                        upd(() => _subScale = v);
                        _mpv('sub-scale', v.toStringAsFixed(2));
                      },
                      divisions: 15,
                    ),
                    slider(
                      'Retraso',
                      _subDelay,
                      -5,
                      5,
                      '${_subDelay.toStringAsFixed(1).replaceAll('.', ',')} s',
                      (v) {
                        upd(() => _subDelay = (v * 10).round() / 10);
                        _mpv('sub-delay', _subDelay.toString());
                      },
                      divisions: 100,
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Dejarlo todo como estaba'),
                      onPressed: () {
                        upd(() {
                          _brightness = _contrast = _saturation = 0;
                          _zoom = 1;
                          _aspect = null;
                          _fit = BoxFit.contain;
                          _audioDelay = _subDelay = 0;
                          _subScale = 1;
                          _normalize = false;
                          _rate = 1;
                        });
                        _setVolume(100);
                        _mpv('af', '');
                        _mpv('audio-delay', '0');
                        _mpv('sub-delay', '0');
                        _mpv('sub-scale', '1');
                        _player.setRate(1);
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _onPosition(Duration pos) {
    if (_isVod &&
        mounted &&
        (_controls || _mini) &&
        pos.inSeconds != _position.inSeconds) {
      setState(() => _position = pos);
    } else {
      _position = pos;
    }
    if (_isVod && DateTime.now().difference(_lastResumeSave).inSeconds >= 5) {
      _lastResumeSave = DateTime.now();
      _saveResume();
    }
    if (pos != _lastPos) {
      _lastPos = pos;
      _lastProgress = DateTime.now();
      if (_status != null || _attempts > 0) {
        // Ha vuelto la señal.
        if (DateTime.now().difference(_openedAt).inSeconds > 8) _attempts = 0;
        if (_status != null && mounted) setState(() => _status = null);
      }
    }
  }

  void _onError(String error) {
    debugPrint('Error de reproducción: $error');
    final posAtError = _player.state.position;
    Timer(const Duration(seconds: 4), () {
      if (!mounted || _userPaused) return;
      if (_player.state.position == posAtError) {
        if (app.settings.reconnect) {
          _scheduleReconnect();
        } else {
          setState(() => _status = 'No se puede reproducir este canal');
        }
      }
    });
  }

  void _onStreamEnded() {
    if (!mounted || _userPaused) return;
    if (_isVod || _isLocal) {
      _userPaused = true;
      ResumeStore.set(_channel.url, _duration, _duration);
      setState(() => _status = 'Fin del vídeo');
      return;
    }
    if (app.settings.reconnect) {
      _scheduleReconnect(immediate: true);
    } else {
      setState(() => _status = 'La emisión se ha interrumpido');
    }
  }

  void _checkStall() {
    if (!mounted || _userPaused || !app.settings.reconnect) return;
    if (_reconnectTimer?.isActive ?? false) return;
    final now = DateTime.now();
    if (now.difference(_openedAt).inSeconds < 25) return;
    if (now.difference(_lastProgress).inSeconds >= 15) _scheduleReconnect();
  }

  void _scheduleReconnect({bool immediate = false}) {
    if (_reconnectTimer?.isActive ?? false) return;
    _attempts++;
    if (_attempts > 40) {
      setState(
        () => _status =
            'No se puede conectar con el canal. Prueba con otro o más tarde.',
      );
      return;
    }
    final secs = immediate && _attempts == 1 ? 1 : math.min(2 * _attempts, 15);
    setState(() => _status = 'Reconectando… (intento $_attempts)');
    _reconnectTimer = Timer(
      Duration(seconds: secs),
      () => _open(reconnecting: true),
    );
  }

  void _changeChannel(int delta) {
    if (widget.channels.length < 2) return;
    _saveResume();
    setState(() {
      _index = (_index + delta) % widget.channels.length;
      if (_index < 0) _index += widget.channels.length;
    });
    _open();
  }

  void _jumpTo(int i) {
    _saveResume();
    setState(() => _index = i);
    _open();
  }

  void _togglePlay() {
    if (_cast != null) return;
    if (_player.state.playing) {
      _userPaused = true;
      if (!_isVod && app.settings.timeshiftMinutes > 0) _shifted = true;
      _player.pause();
    } else {
      if (_status == 'Fin del vídeo') {
        _status = null;
        _player.seek(Duration.zero);
      }
      _userPaused = false;
      _lastProgress = DateTime.now();
      _player.play();
    }
  }

  void _stopFromNotification() {
    _userPaused = true;
    _player.pause();
  }

  void _setVolume(double v) {
    setState(() {
      _volume = v.clamp(0, 200);
      _muted = _volume == 0;
    });
    _player.setVolume(_volume);
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _player.setVolume(_muted ? 0 : (_volume == 0 ? 100 : _volume));
  }

  // ------------------------------------------------------------ Ciclo de vida

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isAndroid) return;
    if (state == AppLifecycleState.paused) {
      if (!NativeBridge.inPip.value &&
          !app.settings.backgroundAudio &&
          !_recording) {
        if (_player.state.playing) {
          _pausedByLifecycle = true;
          _player.pause();
        }
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_pausedByLifecycle) {
        _pausedByLifecycle = false;
        _player.play();
      }
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  void _onPipChanged() {
    if (!mounted) return;
    setState(() => _inPip = NativeBridge.inPip.value);
  }

  // ------------------------------------------------------------ Interfaz

  void _showBanner() {
    _bannerTimer?.cancel();
    setState(() => _banner = true);
    _bannerTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _banner = false);
    });
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controls = false);
    });
  }

  void _showControls() {
    if (!_controls) setState(() => _controls = true);
    _scheduleHide();
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  Future<void> _toggleFullscreen() async {
    if (!_isWindows) return;
    if (_mini) await _toggleMini();
    _fullscreen = !_fullscreen;
    await windowManager.setFullScreen(_fullscreen);
    if (mounted) setState(() {});
  }

  Future<void> _toggleMini() async {
    if (!_isWindows) return;
    if (_mini) {
      await _restoreWindow();
      if (mounted) setState(() => _mini = false);
      return;
    }
    if (_fullscreen) {
      _fullscreen = false;
      await windowManager.setFullScreen(false);
    }
    _savedBounds = await windowManager.getBounds();
    _wasMaximized = await windowManager.isMaximized();
    if (_wasMaximized) await windowManager.unmaximize();
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.setMinimumSize(const Size(220, 124));
    await windowManager.setSize(const Size(480, 270));
    await windowManager.setAlignment(Alignment.bottomRight);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setResizable(true);
    if (mounted) setState(() => _mini = true);
  }

  Future<void> _restoreWindow() async {
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setMinimumSize(const Size(400, 300));
    if (_savedBounds != null) await windowManager.setBounds(_savedBounds);
    if (_wasMaximized) await windowManager.maximize();
  }

  Future<void> _enterPip() async {
    final ok = await NativeBridge.enterPip();
    if (!ok && mounted) {
      showMessage(context, 'Este dispositivo no permite la imagen flotante');
    }
  }

  void _openMosaic() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => MosaicPage(initial: [_channel, null])),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    _showControls();
    if (k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.pageDown ||
        k == LogicalKeyboardKey.channelDown) {
      _changeChannel(1);
    } else if (k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.pageUp ||
        k == LogicalKeyboardKey.channelUp) {
      _changeChannel(-1);
    } else if (k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(HardwareKeyboard.instance.isShiftPressed ? 60 : 10);
    } else if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.mediaRewind) {
      _seekBy(HardwareKeyboard.instance.isShiftPressed ? -60 : -10);
    } else if (k == LogicalKeyboardKey.equal ||
        k == LogicalKeyboardKey.add ||
        k == LogicalKeyboardKey.numpadAdd) {
      _setVolume(_volume + 10);
    } else if (k == LogicalKeyboardKey.minus ||
        k == LogicalKeyboardKey.numpadSubtract) {
      _setVolume(_volume - 10);
    } else if (k == LogicalKeyboardKey.keyD) {
      _goLive();
    } else if (k == LogicalKeyboardKey.keyR ||
        k == LogicalKeyboardKey.mediaRecord) {
      _toggleRecord();
    } else if (k == LogicalKeyboardKey.keyC) {
      _openCast();
    } else if (k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.mediaPlayPause) {
      _togglePlay();
    } else if (k == LogicalKeyboardKey.keyF ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.f11) {
      _toggleFullscreen();
    } else if (k == LogicalKeyboardKey.keyM) {
      _toggleMute();
    } else if (k == LogicalKeyboardKey.keyA) {
      _cycleAudio();
    } else if (k == LogicalKeyboardKey.keyS) {
      _cycleSubtitles();
    } else if (k == LogicalKeyboardKey.keyP) {
      _toggleMini();
    } else if (k == LogicalKeyboardKey.keyL) {
      _scaffoldKey.currentState?.openEndDrawer();
    } else if (k == LogicalKeyboardKey.escape) {
      if (_mini) {
        _toggleMini();
      } else if (_fullscreen) {
        _toggleFullscreen();
      } else {
        Navigator.of(context).maybePop();
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  List<AudioTrack> get _audioTracks => _player.state.tracks.audio
      .where((t) => t.id != 'auto' && t.id != 'no')
      .toList();

  List<SubtitleTrack> get _subTracks => _player.state.tracks.subtitle
      .where((t) => t.id != 'auto' && t.id != 'no')
      .toList();

  void _cycleAudio() {
    final list = _audioTracks;
    if (list.length < 2) return;
    final cur = list.indexWhere((t) => t.id == _player.state.track.audio.id);
    final next = list[(cur + 1) % list.length];
    _player.setAudioTrack(next);
    showMessage(
      context,
      'Audio: ${trackLabel(list.indexOf(next), next.language, next.title)}',
    );
  }

  void _cycleSubtitles() {
    final list = [SubtitleTrack.no(), ..._subTracks];
    if (list.length < 2) return;
    final cur = list.indexWhere((t) => t.id == _player.state.track.subtitle.id);
    final next = list[(cur + 1) % list.length];
    _player.setSubtitleTrack(next);
    showMessage(
      context,
      next.id == 'no'
          ? 'Subtítulos desactivados'
          : 'Subtítulos: ${trackLabel(list.indexOf(next) - 1, next.language, next.title)}',
    );
  }

  Future<void> _chooseAudio() async {
    final list = _audioTracks;
    final current = _player.state.track.audio.id;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Pista de audio')),
            if (list.isEmpty)
              const ListTile(
                subtitle: Text('Este canal sólo tiene una pista de audio'),
              ),
            for (var i = 0; i < list.length; i++)
              ListTile(
                leading: Icon(
                  list[i].id == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(
                  trackLabel(
                    i,
                    list[i].language,
                    list[i].title,
                    codec: list[i].codec,
                  ),
                ),
                onTap: () {
                  _player.setAudioTrack(list[i]);
                  Navigator.pop(ctx);
                  _rememberLanguage(list[i].language, audio: true);
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Recuerda el idioma elegido para los próximos canales.
  void _rememberLanguage(String? lang, {required bool audio}) {
    final code = preferredCodeFor(lang);
    if (code.isEmpty) return;
    final s = app.settings;
    if ((audio ? s.audioLanguage : s.subtitleLanguage) == code) return;
    app.updateSettings((s) {
      if (audio) {
        s.audioLanguage = code;
      } else {
        s.subtitleLanguage = code;
      }
    });
    showMessage(
      context,
      '${audio ? 'Audio' : 'Subtítulos'} en ${preferredLanguages[code]!.toLowerCase()} '
      'siempre que el canal lo tenga. Puedes cambiarlo en Ajustes.',
    );
  }

  Future<void> _chooseSubtitles() async {
    final list = _subTracks;
    final current = _player.state.track.subtitle.id;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Subtítulos')),
            ListTile(
              leading: Icon(
                current == 'no' || current == 'auto'
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: const Text('Desactivados'),
              onTap: () {
                _player.setSubtitleTrack(SubtitleTrack.no());
                Navigator.pop(ctx);
                if (app.settings.subtitleLanguage.isNotEmpty) {
                  app.updateSettings((s) => s.subtitleLanguage = '');
                }
              },
            ),
            if (list.isEmpty)
              const ListTile(subtitle: Text('Este canal no emite subtítulos')),
            for (var i = 0; i < list.length; i++)
              ListTile(
                leading: Icon(
                  list[i].id == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(trackLabel(i, list[i].language, list[i].title)),
                onTap: () {
                  _player.setSubtitleTrack(list[i]);
                  Navigator.pop(ctx);
                  _rememberLanguage(list[i].language, audio: false);
                },
              ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ Construcción

  @override
  Widget build(BuildContext context) {
    Widget video = Video(
      controller: _video,
      fit: _fit,
      aspectRatio: _aspect,
      fill: Colors.black,
      controls: null,
      wakelock: true,
      pauseUponEnteringBackgroundMode: false,
      resumeUponEnteringForegroundMode: false,
    );
    if (_brightness != 0 || _contrast != 0 || _saturation != 0) {
      video = ColorFiltered(
        colorFilter: ColorFilter.matrix(_colorMatrix),
        child: video,
      );
    }
    if (_zoom != 1) {
      video = ClipRect(
        child: Transform.scale(scale: _zoom, child: video),
      );
    }
    if (_cast != null) {
      video = ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cast_connected, color: Colors.white70, size: 64),
              const SizedBox(height: 12),
              Text(
                'Emitiendo en ${_cast!.name}',
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
        ),
      );
    }

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.black,
        endDrawer: _inPip || _mini ? null : _channelDrawer(),
        body: _inPip
            ? video
            : _mini
            ? _miniView(video)
            : _fullView(video),
      ),
    );
  }

  Widget _fullView(Widget video) {
    final (now, next) = app.nowNext(_channel);
    return MouseRegion(
      onHover: (_) => _showControls(),
      cursor: _controls ? MouseCursor.defer : SystemMouseCursors.none,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              onDoubleTap: _isWindows ? _toggleFullscreen : null,
              onVerticalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v < -250) {
                  _changeChannel(1);
                } else if (v > 250) {
                  _changeChannel(-1);
                }
              },
              child: video,
            ),
          ),
          if (_buffering && _status == null && _cast == null)
            const Center(
              child: CircularProgressIndicator(color: Colors.white70),
            ),
          if (_recording)
            Positioned(
              right: 16,
              top: MediaQuery.paddingOf(context).top + 72,
              child: _RecBadge(since: _recSince!),
            ),
          if (_status != null) Center(child: _StatusBox(text: _status!)),
          if (_banner || _controls)
            Positioned(top: 0, left: 0, right: 0, child: _topBar(now, next)),
          if (_controls)
            Positioned(left: 0, right: 0, bottom: 0, child: _bottomBar()),
        ],
      ),
    );
  }

  Widget _topBar(Programme? now, Programme? next) {
    final theme = Theme.of(context);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        8,
        MediaQuery.paddingOf(context).top + 8,
        16,
        32,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            tooltip: 'Volver',
            color: Colors.white,
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 8),
          ChannelLogo(_channel, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.channels.length > 1 ? '${_index + 1}. ' : ''}${app.channelName(_channel)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (now != null)
                  Text(
                    'Ahora: ${now.title}  (${hhmm(now.start)}-${hhmm(now.stop)})',
                    style: const TextStyle(color: Colors.white70),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (next != null)
                  Text(
                    'Después: ${hhmm(next.start)} ${next.title}',
                    style: const TextStyle(color: Colors.white54),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (now == null)
                  Text(
                    app.groupName(_channel.group),
                    style: const TextStyle(color: Colors.white54),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (!_isLocal)
            IconButton(
              tooltip: app.isFavorite(_channel)
                  ? 'Quitar de favoritos'
                  : 'Añadir a favoritos',
              color: app.isFavorite(_channel) ? Colors.amber : Colors.white,
              icon: Icon(
                app.isFavorite(_channel) ? Icons.star : Icons.star_border,
              ),
              onPressed: () => setState(() => app.toggleFavorite(_channel)),
            ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final audioCount = _audioTracks.length;
    final subCount = _subTracks.length;
    final wide = MediaQuery.sizeOf(context).width > 640;
    Widget btn(
      IconData icon,
      String tip,
      VoidCallback? onTap, {
      Color? color,
    }) => IconButton(
      tooltip: tip,
      color: color ?? Colors.white,
      disabledColor: Colors.white30,
      icon: Icon(icon),
      onPressed: onTap,
    );
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        8,
        32,
        8,
        MediaQuery.paddingOf(context).bottom + 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_cast == null) _timeline(),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              btn(
                Icons.skip_previous,
                'Canal anterior (↑)',
                widget.channels.length > 1 ? () => _changeChannel(-1) : null,
              ),
              if (_isVod || _canShift)
                btn(Icons.replay_10, 'Atrás 10 s (←)', () => _seekBy(-10)),
              btn(
                _playing ? Icons.pause : Icons.play_arrow,
                _playing ? 'Pausa (Espacio)' : 'Reproducir (Espacio)',
                _cast == null ? _togglePlay : null,
              ),
              if (_isVod || _canShift)
                btn(Icons.forward_10, 'Adelante 10 s (→)', () => _seekBy(10)),
              btn(
                Icons.skip_next,
                'Canal siguiente (↓)',
                widget.channels.length > 1 ? () => _changeChannel(1) : null,
              ),
              btn(
                _muted ? Icons.volume_off : Icons.volume_up,
                'Silencio (M)',
                _toggleMute,
              ),
              if (wide && !_isAndroid)
                SizedBox(
                  width: 120,
                  child: Slider(
                    value: _muted ? 0 : _volume,
                    max: 200,
                    onChanged: _setVolume,
                  ),
                ),
              btn(
                Icons.audiotrack,
                audioCount > 1
                    ? 'Audio: $audioCount pistas (A)'
                    : 'Pista de audio',
                _chooseAudio,
                color: audioCount > 1 ? Colors.lightBlueAccent : null,
              ),
              btn(
                Icons.subtitles_outlined,
                subCount > 0 ? 'Subtítulos: $subCount (S)' : 'Subtítulos',
                _chooseSubtitles,
                color: subCount > 0 ? Colors.lightBlueAccent : null,
              ),
              btn(Icons.tune, 'Imagen, sonido y velocidad', _openTune),
              if (!_isLocal)
                btn(
                  _recording ? Icons.stop_circle : Icons.fiber_manual_record,
                  _recording
                      ? 'Parar y guardar la grabación (R)'
                      : 'Grabar (R)',
                  _toggleRecord,
                  color: Colors.redAccent,
                ),
              if (!_isLocal)
                btn(
                  _cast != null ? Icons.cast_connected : Icons.cast,
                  _cast != null
                      ? 'Emitiendo en ${_cast!.name}'
                      : 'Emitir en la tele (C)',
                  _openCast,
                  color: _cast != null ? Colors.lightBlueAccent : null,
                ),
              btn(Icons.grid_view, 'Mosaico', _openMosaic),
              btn(
                Icons.list,
                'Lista de canales (L)',
                () => _scaffoldKey.currentState?.openEndDrawer(),
              ),
              if (_isAndroid)
                btn(Icons.picture_in_picture_alt, 'Imagen flotante', _enterPip),
              if (_isWindows) ...[
                btn(
                  Icons.picture_in_picture_alt,
                  'Miniventana siempre visible (P)',
                  _toggleMini,
                ),
                btn(
                  _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  'Pantalla completa (F)',
                  _toggleFullscreen,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Barra de tiempo: películas y grabaciones, o lo guardado del directo.
  Widget _timeline() {
    const style = TextStyle(color: Colors.white70, fontSize: 12);
    if (_isVod) {
      final total = _duration.inMilliseconds.toDouble();
      final value = _drag ?? _position.inMilliseconds.toDouble();
      return Row(
        children: [
          const SizedBox(width: 8),
          Text(
            formatDuration(Duration(milliseconds: value.round())),
            style: style,
          ),
          Expanded(
            child: Slider(
              value: value.clamp(0, total),
              max: total,
              onChanged: (v) {
                _showControls();
                setState(() => _drag = v);
              },
              onChangeEnd: (v) {
                _player.seek(Duration(milliseconds: v.round()));
                setState(() {
                  _drag = null;
                  _position = Duration(milliseconds: v.round());
                });
              },
            ),
          ),
          Text(formatDuration(_duration), style: style),
          const SizedBox(width: 8),
        ],
      );
    }
    if (!_canShift) return const SizedBox.shrink();
    final start = _cacheStart;
    final end = math.max(_liveEdge, start + 1);
    final value = (_drag ?? _posSec).clamp(start, end);
    final live = !_shifted;
    return Row(
      children: [
        const SizedBox(width: 8),
        Text(
          '-${formatDuration(Duration(seconds: (end - start).round()))}',
          style: style,
        ),
        Expanded(
          child: Slider(
            value: value,
            min: start,
            max: end,
            onChanged: (v) {
              _showControls();
              setState(() => _drag = v);
            },
            onChangeEnd: (v) async {
              setState(() => _drag = null);
              if (v >= end - 2) {
                await _goLive();
              } else {
                setState(() {
                  _shifted = true;
                  _posSec = v;
                });
                await _seekAbs(v);
              }
            },
          ),
        ),
        ActionChip(
          avatar: Icon(
            Icons.circle,
            size: 10,
            color: live ? Colors.redAccent : Colors.white54,
          ),
          label: Text(
            live
                ? 'DIRECTO'
                : 'Ir al directo (${formatDuration(Duration(seconds: -_delay.round()))})',
          ),
          onPressed: live ? null : _goLive,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _miniView(Widget video) {
    return MouseRegion(
      onHover: (_) => _showControls(),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: _toggleMini,
              onTap: _toggleControls,
              child: video,
            ),
          ),
          if (_buffering && _status == null)
            const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              ),
            ),
          if (_status != null)
            Center(child: _StatusBox(text: _status!, small: true)),
          if (_controls || _banner)
            Positioned(
              left: 8,
              top: 6,
              right: 120,
              child: Text(
                app.channelName(_channel),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                ),
              ),
            ),
          if (_controls)
            Positioned(
              top: 0,
              right: 0,
              child: Row(
                children: [
                  _miniBtn(
                    Icons.skip_previous,
                    'Canal anterior',
                    () => _changeChannel(-1),
                  ),
                  _miniBtn(
                    Icons.skip_next,
                    'Canal siguiente',
                    () => _changeChannel(1),
                  ),
                  _miniBtn(
                    _muted ? Icons.volume_off : Icons.volume_up,
                    'Silencio',
                    _toggleMute,
                  ),
                  _miniBtn(
                    Icons.open_in_full,
                    'Volver a ventana normal',
                    _toggleMini,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _miniBtn(IconData icon, String tip, VoidCallback onTap) => IconButton(
    tooltip: tip,
    iconSize: 18,
    visualDensity: VisualDensity.compact,
    color: Colors.white,
    style: IconButton.styleFrom(backgroundColor: Colors.black45),
    icon: Icon(icon),
    onPressed: onTap,
  );

  Widget _channelDrawer() {
    return Drawer(
      width: 340,
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              title: const Text('Canales'),
              subtitle: Text('${widget.channels.length} en esta lista'),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: widget.channels.length,
                itemBuilder: (context, i) {
                  final c = widget.channels[i];
                  final (now, _) = app.nowNext(c);
                  return ListTile(
                    selected: i == _index,
                    leading: ChannelLogo(c, size: 32),
                    title: Text(
                      app.channelName(c),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: now == null
                        ? null
                        : Text(
                            now.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                    onTap: () {
                      Navigator.pop(context);
                      _jumpTo(i);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBox extends StatelessWidget {
  const _StatusBox({required this.text, this.small = false});
  final String text;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(small ? 8 : 16),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white, fontSize: small ? 12 : 16),
      ),
    );
  }
}

class _RecBadge extends StatefulWidget {
  const _RecBadge({required this.since});
  final DateTime since;

  @override
  State<_RecBadge> createState() => _RecBadgeState();
}

class _RecBadgeState extends State<_RecBadge> {
  late final Timer _t = Timer.periodic(
    const Duration(seconds: 1),
    (_) => setState(() {}),
  );

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = DateTime.now().difference(widget.since);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.fiber_manual_record, color: Colors.white, size: 12),
          const SizedBox(width: 6),
          Text(
            'GRABANDO ${formatDuration(d)}',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
