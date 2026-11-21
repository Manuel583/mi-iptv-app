import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../app_state.dart';
import '../models.dart';
import '../native.dart';
import 'common.dart';
import 'live_captions.dart';
import 'mosaic_page.dart';

bool get _isWindows => !kIsWeb && Platform.isWindows;
bool get _isAndroid => !kIsWeb && Platform.isAndroid;

/// Configura libmpv para emisiones en directo por internet.
Future<void> configureLivePlayer(Player player, {bool muted = false}) async {
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
  await set('demuxer-max-bytes', '64MiB');
  await set('demuxer-max-back-bytes', '16MiB');
  await set('hls-bitrate', 'max');
  await set(
    'stream-lavf-o',
    'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=5',
  );
  await set('user-agent', app.effectiveUserAgent);
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
    _start();
    _scheduleHide();
  }

  Future<void> _start() async {
    await configureLivePlayer(_player);
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
    NativeBridge.inPip.removeListener(_onPipChanged);
    if (NativeBridge.onStopRequested == _stopFromNotification) {
      NativeBridge.onStopRequested = null;
    }
    if (_isAndroid) {
      LiveCaptions.stop();
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
    if (!reconnecting) {
      _attempts = 0;
      _status = null;
      _reconnectTimer?.cancel();
      app.setLastChannel(c);
      _showBanner();
      if (_isAndroid && app.settings.backgroundAudio) {
        NativeBridge.startPlaybackService(app.channelName(c));
      }
    }
    if (mounted) setState(() => _buffering = true);
    try {
      await openChannelIn(_player, c);
    } catch (e) {
      _onError('$e');
    }
  }

  void _onPosition(Duration pos) {
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
    setState(() {
      _index = (_index + delta) % widget.channels.length;
      if (_index < 0) _index += widget.channels.length;
    });
    _open();
  }

  void _jumpTo(int i) {
    setState(() => _index = i);
    _open();
  }

  void _togglePlay() {
    if (_player.state.playing) {
      _userPaused = true;
      _player.pause();
    } else {
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
      _volume = v.clamp(0, 100);
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
      if (!NativeBridge.inPip.value && !app.settings.backgroundAudio) {
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

  Future<void> _toggleLiveCaptions() async {
    final error = await LiveCaptions.toggle();
    if (error != null && mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(error)));
    }
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
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _setVolume(_volume + 10);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _setVolume(_volume - 10);
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
                },
              ),
          ],
        ),
      ),
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
                },
              ),
          ],
        ),
      ),
    );
  }

  void _cycleFit() {
    setState(() {
      _fit = switch (_fit) {
        BoxFit.contain => BoxFit.cover,
        BoxFit.cover => BoxFit.fill,
        _ => BoxFit.contain,
      };
    });
    showMessage(context, switch (_fit) {
      BoxFit.cover => 'Imagen: rellenar (recorta bordes)',
      BoxFit.fill => 'Imagen: estirar',
      _ => 'Imagen: ajustar',
    });
  }

  // ------------------------------------------------------------ Construcción

  @override
  Widget build(BuildContext context) {
    final video = Video(
      controller: _video,
      fit: _fit,
      fill: Colors.black,
      controls: null,
      wakelock: true,
      pauseUponEnteringBackgroundMode: false,
      resumeUponEnteringForegroundMode: false,
    );

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
          if (_buffering && _status == null)
            const Center(
              child: CircularProgressIndicator(color: Colors.white70),
            ),
          if (_status != null) Center(child: _StatusBox(text: _status!)),
          if (liveCaptionsPlatform)
            Positioned.fill(
              child: LiveCaptionOverlay(controlsVisible: _controls),
            ),
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
          if (liveCaptionsPlatform)
            ValueListenableBuilder<bool>(
              valueListenable: LiveCaptions.active,
              builder: (context, on, _) => IconButton(
                tooltip: on
                    ? 'Apagar subtítulos en directo'
                    : 'Subtítulos en directo',
                color: on ? Colors.amber : Colors.white,
                icon: Icon(
                  on ? Icons.closed_caption : Icons.closed_caption_outlined,
                ),
                onPressed: _toggleLiveCaptions,
              ),
            ),
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
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          btn(
            Icons.skip_previous,
            'Canal anterior (↑)',
            widget.channels.length > 1 ? () => _changeChannel(-1) : null,
          ),
          btn(
            _playing ? Icons.pause : Icons.play_arrow,
            _playing ? 'Pausa (Espacio)' : 'Reproducir (Espacio)',
            _togglePlay,
          ),
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
                max: 100,
                onChanged: _setVolume,
              ),
            ),
          btn(
            Icons.audiotrack,
            audioCount > 1 ? 'Audio: $audioCount pistas (A)' : 'Pista de audio',
            _chooseAudio,
            color: audioCount > 1 ? Colors.lightBlueAccent : null,
          ),
          btn(
            Icons.subtitles_outlined,
            subCount > 0 ? 'Subtítulos: $subCount (S)' : 'Subtítulos',
            _chooseSubtitles,
            color: subCount > 0 ? Colors.lightBlueAccent : null,
          ),
          btn(Icons.aspect_ratio, 'Ajuste de imagen', _cycleFit),
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
