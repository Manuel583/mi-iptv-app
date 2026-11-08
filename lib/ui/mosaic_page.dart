import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../app_state.dart';
import '../models.dart';
import 'player_page.dart';
import 'search_page.dart';

/// Varios canales a la vez (2 o 4) con el sonido de uno solo.
class MosaicPage extends StatefulWidget {
  const MosaicPage({super.key, required this.initial});
  final List<Channel?> initial;

  @override
  State<MosaicPage> createState() => _MosaicPageState();
}

class _Cell {
  _Cell()
      : player = Player(
            configuration:
                const PlayerConfiguration(bufferSize: 16 * 1024 * 1024)) {
    video = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: app.settings.hardwareDecoding,
      ),
    );
  }

  final Player player;
  late final VideoController video;
  Channel? channel;
  bool ready = false;
  bool reconnecting = false;
  Timer? retry;
  final subs = <StreamSubscription>[];
}

class _MosaicPageState extends State<MosaicPage> {
  late int _count = widget.initial.where((c) => c != null).length > 2 ? 4 : 2;
  final List<_Cell> _cells = [];
  int _active = 0;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 4; i++) {
      final cell = _Cell();
      cell.subs.add(cell.player.stream.error.listen((_) => _retryLater(cell)));
      cell.subs.add(cell.player.stream.completed.listen((d) {
        if (d) _retryLater(cell);
      }));
      cell.subs.add(cell.player.stream.buffering.listen((_) {
        if (mounted) setState(() {});
      }));
      _cells.add(cell);
    }
    _init();
  }

  Future<void> _init() async {
    for (var i = 0; i < 4; i++) {
      await configureLivePlayer(_cells[i].player);
      _cells[i].ready = true;
      await _cells[i].player.setVolume(i == _active ? 100 : 0);
    }
    for (var i = 0; i < widget.initial.length && i < 4; i++) {
      final c = widget.initial[i];
      if (c != null) await _setChannel(i, c);
    }
  }

  @override
  void dispose() {
    for (final c in _cells) {
      c.retry?.cancel();
      for (final s in c.subs) {
        s.cancel();
      }
      c.player.dispose();
    }
    _focus.dispose();
    super.dispose();
  }

  void _retryLater(_Cell cell) {
    if (!app.settings.reconnect || cell.channel == null) return;
    if (cell.retry?.isActive ?? false) return;
    final pos = cell.player.state.position;
    cell.retry = Timer(const Duration(seconds: 4), () async {
      if (!mounted || cell.channel == null) return;
      if (cell.player.state.position != pos) return; // ya se recuperó
      setState(() => cell.reconnecting = true);
      await openChannelIn(cell.player, cell.channel!);
      if (mounted) setState(() => cell.reconnecting = false);
    });
  }

  Future<void> _setChannel(int i, Channel c) async {
    final cell = _cells[i];
    setState(() => cell.channel = c);
    await openChannelIn(cell.player, c);
    await cell.player.setVolume(i == _active ? 100 : 0);
  }

  Future<void> _pick(int i) async {
    final c = await pickChannel(context);
    if (c != null) await _setChannel(i, c);
  }

  void _activate(int i) {
    setState(() => _active = i);
    for (var j = 0; j < _cells.length; j++) {
      _cells[j].player.setVolume(j == i ? 100 : 0);
    }
  }

  void _setCount(int n) {
    setState(() {
      _count = n;
      if (_active >= n) _active = 0;
    });
    // Parar los que quedan fuera para ahorrar datos.
    for (var i = n; i < 4; i++) {
      _cells[i].player.stop();
      _cells[i].channel = null;
    }
    _activate(_active);
  }

  void _openSingle(int i) {
    final c = _cells[i].channel;
    if (c == null) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => PlayerPage(channels: [c], initialIndex: 0),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (node, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        final keys = [
          LogicalKeyboardKey.digit1,
          LogicalKeyboardKey.digit2,
          LogicalKeyboardKey.digit3,
          LogicalKeyboardKey.digit4,
        ];
        final i = keys.indexOf(e.logicalKey);
        if (i >= 0 && i < _count) {
          _activate(i);
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).maybePop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Mosaico'),
          actions: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 2, label: Text('2')),
                ButtonSegment(value: 4, label: Text('4')),
              ],
              selected: {_count},
              onSelectionChanged: (v) => _setCount(v.first),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              final landscape = box.maxWidth >= box.maxHeight;
              if (_count == 2) {
                final children = [
                  Expanded(child: _cell(0)),
                  Expanded(child: _cell(1)),
                ];
                return landscape
                    ? Row(children: children)
                    : Column(children: children);
              }
              return Column(
                children: [
                  Expanded(
                      child: Row(children: [
                    Expanded(child: _cell(0)),
                    Expanded(child: _cell(1)),
                  ])),
                  Expanded(
                      child: Row(children: [
                    Expanded(child: _cell(2)),
                    Expanded(child: _cell(3)),
                  ])),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _cell(int i) {
    final cell = _cells[i];
    final active = i == _active;
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        border: Border.all(
            color: active ? cs.primary : Colors.white12, width: active ? 3 : 1),
      ),
      child: cell.channel == null
          ? Center(
              child: TextButton.icon(
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('Elegir canal',
                    style: TextStyle(color: Colors.white)),
                onPressed: () => _pick(i),
              ),
            )
          : Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _activate(i),
                    onDoubleTap: () => _openSingle(i),
                    child: Video(
                      controller: cell.video,
                      controls: null,
                      fill: Colors.black,
                      pauseUponEnteringBackgroundMode: false,
                    ),
                  ),
                ),
                if (cell.player.state.buffering || cell.reconnecting)
                  const Center(
                      child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white70))),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    color: Colors.black54,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      children: [
                        Icon(active ? Icons.volume_up : Icons.volume_off,
                            size: 16,
                            color: active ? cs.primary : Colors.white54),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${i + 1}. ${app.channelName(cell.channel!)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cambiar canal',
                          iconSize: 18,
                          visualDensity: VisualDensity.compact,
                          color: Colors.white,
                          icon: const Icon(Icons.swap_horiz),
                          onPressed: () => _pick(i),
                        ),
                        IconButton(
                          tooltip: 'Ver en grande',
                          iconSize: 18,
                          visualDensity: VisualDensity.compact,
                          color: Colors.white,
                          icon: const Icon(Icons.open_in_full),
                          onPressed: () => _openSingle(i),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
