// Guía de programación en rejilla: canales en filas y horas en columnas.
import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../scheduler.dart';
import 'common.dart';
import 'scheduled_page.dart';

const _weekDays = [
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
  'domingo',
];

String dayName(DateTime d, {bool short = false}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Hoy';
  if (diff == 1) return 'Mañana';
  if (diff == -1) return 'Ayer';
  final w = _weekDays[d.weekday - 1];
  final name = short ? w.substring(0, 3) : w;
  return '${name[0].toUpperCase()}${name.substring(1)} ${d.day}/${d.month}';
}

/// Qué canales se muestran en la guía.
String _lastFilter = '';

class GuidePage extends StatefulWidget {
  const GuidePage({super.key});

  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage> {
  static const _rowH = 64.0;
  static const _headerH = 32.0;
  static const _hourW = 240.0;

  final _h = ScrollController();
  final _vNames = ScrollController();
  final _vGrid = ScrollController();
  bool _syncing = false;
  Timer? _tick;

  late String _filter;
  late DateTime _day; // medianoche del día que se muestra

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _day = DateTime(now.year, now.month, now.day);
    _filter = _lastFilter;
    if (_filter.isEmpty) {
      _filter = app.favoriteChannels().isNotEmpty
          ? 'fav'
          : (app.groups().isNotEmpty ? 'g:${app.groups().first.key}' : 'all');
    }
    _vGrid.addListener(() => _sync(_vGrid, _vNames));
    _vNames.addListener(() => _sync(_vNames, _vGrid));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToNow());
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    RecordingScheduler.instance.addListener(_onChange);
  }

  @override
  void dispose() {
    _tick?.cancel();
    RecordingScheduler.instance.removeListener(_onChange);
    _h.dispose();
    _vNames.dispose();
    _vGrid.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _sync(ScrollController from, ScrollController to) {
    if (_syncing || !to.hasClients) return;
    _syncing = true;
    if (to.offset != from.offset) to.jumpTo(from.offset);
    _syncing = false;
  }

  DateTime get _start => _day;
  DateTime get _end => _day.add(const Duration(days: 1));
  double get _totalW => _hourW * 24;

  double _x(DateTime t) => t.difference(_start).inSeconds / 3600 * _hourW;

  void _scrollToNow() {
    if (!_h.hasClients) return;
    final now = DateTime.now();
    final target = now.isAfter(_start) && now.isBefore(_end)
        ? _x(now) - _hourW / 2
        : _x(_start.add(const Duration(hours: 18)));
    _h.jumpTo(target.clamp(0, _h.position.maxScrollExtent));
  }

  List<Channel> _channels() {
    if (_filter == 'fav') return app.favoriteChannels();
    if (_filter == 'all') {
      return app.visibleChannels();
    }
    if (_filter.startsWith('g:')) {
      return app.channelsInGroup(_filter.substring(2));
    }
    if (_filter.startsWith('f:')) {
      final f = app.custom.folders
          .where((f) => f.id == _filter.substring(2))
          .firstOrNull;
      if (f != null) return app.folderChannels(f);
    }
    return const [];
  }

  List<DateTime> _days() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return [for (var i = -1; i < 4; i++) today.add(Duration(days: i))];
  }

  Widget _toolbar() {
    final items = <DropdownMenuItem<String>>[
      if (app.favoriteChannels().isNotEmpty)
        const DropdownMenuItem(value: 'fav', child: Text('Favoritos')),
      for (final f in app.custom.folders)
        DropdownMenuItem(value: 'f:${f.id}', child: Text('Carpeta: ${f.name}')),
      for (final g in app.groups())
        DropdownMenuItem(value: 'g:${g.key}', child: Text(g.name)),
      const DropdownMenuItem(value: 'all', child: Text('Todos los canales')),
    ];
    if (!items.any((i) => i.value == _filter)) _filter = items.first.value!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: [
          Flexible(
            child: DropdownButton<String>(
              value: _filter,
              isExpanded: true,
              items: items,
              onChanged: (v) {
                if (v == null) return;
                setState(() => _filter = _lastFilter = v);
              },
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<DateTime>(
            value: _day,
            items: [
              for (final d in _days())
                DropdownMenuItem(
                  value: d,
                  child: Text(dayName(d, short: true)),
                ),
            ],
            onChanged: (d) {
              if (d == null) return;
              setState(() => _day = d);
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _scrollToNow(),
              );
            },
          ),
          IconButton(
            tooltip: 'Ir a ahora',
            icon: const Icon(Icons.schedule),
            onPressed: () {
              final now = DateTime.now();
              setState(() => _day = DateTime(now.year, now.month, now.day));
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _scrollToNow(),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guía de programación'),
        actions: [
          if (app.epgLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            tooltip: 'Grabaciones programadas',
            icon: const Icon(Icons.event_note_outlined),
            onPressed: () => openScheduledRecordings(context),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final channels = _channels();
          final wide = MediaQuery.sizeOf(context).width >= 720;
          final nameW = wide ? 200.0 : 112.0;
          return Column(
            children: [
              _toolbar(),
              const Divider(height: 1),
              Expanded(
                child: channels.isEmpty
                    ? const Center(child: Text('No hay canales en este grupo'))
                    : Row(
                        children: [
                          SizedBox(
                            width: nameW,
                            child: Column(
                              children: [
                                SizedBox(
                                  height: _headerH,
                                  child: Center(
                                    child: Text(
                                      dayName(_day),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: ListView.builder(
                                    controller: _vNames,
                                    itemExtent: _rowH,
                                    itemCount: channels.length,
                                    itemBuilder: (context, i) => _ChannelCell(
                                      channel: channels[i],
                                      compact: !wide,
                                      onTap: () =>
                                          openPlayer(context, channels, i),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(child: _grid(channels)),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _grid(List<Channel> channels) {
    final now = DateTime.now();
    final nowX = _x(now);
    final showNow = nowX >= 0 && nowX <= _totalW;
    final cs = Theme.of(context).colorScheme;
    return Scrollbar(
      controller: _h,
      child: SingleChildScrollView(
        controller: _h,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: _totalW,
          child: Stack(
            children: [
              Column(
                children: [
                  SizedBox(
                    height: _headerH,
                    child: Stack(
                      children: [
                        for (var h = 0; h < 48; h++)
                          Positioned(
                            left: h * _hourW / 2,
                            top: 0,
                            bottom: 0,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Center(
                                child: Text(
                                  '${(h ~/ 2).toString().padLeft(2, '0')}:${h.isOdd ? '30' : '00'}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: _vGrid,
                      itemExtent: _rowH,
                      itemCount: channels.length,
                      itemBuilder: (context, i) => _row(channels[i], now),
                    ),
                  ),
                ],
              ),
              if (showNow)
                Positioned(
                  left: nowX - 1,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(width: 2, color: cs.error),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(Channel c, DateTime now) {
    app.requestProgrammes(c);
    final all = app.programmesFor(c) ?? const <Programme>[];
    final list = all
        .where((p) => p.stop.isAfter(_start) && p.start.isBefore(_end))
        .toList();
    final cs = Theme.of(context).colorScheme;
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(2),
        child: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
          child: Text(
            app.epgLoading ? 'Cargando…' : 'Sin guía para este canal',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }
    return Stack(
      children: [
        for (final p in list)
          Positioned(
            left: _x(p.start).clamp(0.0, _totalW),
            width:
                (_x(p.stop).clamp(0.0, _totalW) -
                        _x(p.start).clamp(0.0, _totalW))
                    .clamp(4.0, _totalW),
            top: 2,
            bottom: 2,
            child: _ProgrammeCell(channel: c, programme: p, now: now),
          ),
      ],
    );
  }
}

class _ChannelCell extends StatelessWidget {
  const _ChannelCell({
    required this.channel,
    required this.onTap,
    required this.compact,
  });
  final Channel channel;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: () => showChannelActions(context, channel),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            ChannelLogo(channel, size: compact ? 28 : 36),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                app.channelName(channel),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgrammeCell extends StatelessWidget {
  const _ProgrammeCell({
    required this.channel,
    required this.programme,
    required this.now,
  });
  final Channel channel;
  final Programme programme;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = programme;
    final cs = Theme.of(context).colorScheme;
    final live = p.isNow(now);
    final past = !p.stop.isAfter(now);
    final rec = RecordingScheduler.instance.find(channel, p);
    final bg = live
        ? cs.primaryContainer
        : past
        ? cs.surfaceContainerHighest.withValues(alpha: 0.5)
        : cs.surfaceContainerHighest;
    final fg = live ? cs.onPrimaryContainer : cs.onSurface;
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showProgrammeSheet(context, channel, p),
          child: Container(
            decoration: rec == null
                ? null
                : BoxDecoration(
                    border: Border.all(color: cs.error, width: 2),
                    borderRadius: BorderRadius.circular(6),
                  ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Opacity(
              opacity: past ? 0.6 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      if (rec != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.fiber_manual_record,
                            size: 12,
                            color: cs.error,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          p.title.isEmpty ? 'Sin título' : p.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: fg,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${hhmm(p.start)} - ${hhmm(p.stop)}',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(color: fg, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ficha de un programa: ver, grabar o cancelar la grabación.
Future<void> showProgrammeSheet(
  BuildContext context,
  Channel c,
  Programme p,
) async {
  final sched = RecordingScheduler.instance;
  await showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final now = DateTime.now();
      final live = p.isNow(now);
      final ended = !p.stop.isAfter(now);
      final rec = sched.find(c, p);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                p.title.isEmpty ? 'Sin título' : p.title,
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '${app.channelName(c)} | ${dayName(p.start)} | ${hhmm(p.start)} - ${hhmm(p.stop)}',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              if (live) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: p.progress(now)),
              ],
              if (p.desc.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(p.desc),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: Text(live ? 'Ver ahora' : 'Ver el canal'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      openPlayer(context, [c], 0);
                    },
                  ),
                  if (!ended && sched.supported && rec == null)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.fiber_manual_record),
                      label: Text(live ? 'Grabar desde ahora' : 'Grabar'),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final err = await sched.schedule(c, p);
                        if (!context.mounted) return;
                        showMessage(
                          context,
                          err ??
                              (live
                                  ? 'Grabando "${p.title}" hasta las ${hhmm(p.stop)}'
                                  : 'Se grabará "${p.title}" el ${dayName(p.start).toLowerCase()} a las ${hhmm(p.start)}'),
                        );
                      },
                    ),
                  if (rec != null && rec.isActiveOrPending)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.cancel_outlined),
                      label: Text(
                        rec.status == RecStatus.recording
                            ? 'Parar la grabación'
                            : 'Cancelar la grabación',
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await sched.cancel(rec);
                        if (context.mounted) {
                          showMessage(context, 'Grabación cancelada');
                        }
                      },
                    ),
                ],
              ),
              if (!ended && !sched.supported)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'La grabación programada sólo está disponible en Android y Windows.',
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
