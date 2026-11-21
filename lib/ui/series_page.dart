import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'common.dart';

Channel _logoOf(SeriesInfo s) => Channel(
  key: s.key,
  sourceId: s.sourceId,
  name: s.name,
  url: '',
  logo: s.logo,
);

/// Series de un grupo.
class SeriesList extends StatefulWidget {
  const SeriesList({super.key, required this.groupKey, this.embedded = false});
  final String groupKey;
  final bool embedded;

  @override
  State<SeriesList> createState() => _SeriesListState();
}

class _SeriesListState extends State<SeriesList> {
  final _filter = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final q = _filter.text.trim().toLowerCase();
        final all = app.seriesInGroup(widget.groupKey);
        final list = q.isEmpty
            ? all
            : all.where((s) => s.name.toLowerCase().contains(q)).toList();
        final title = app.groupName(widget.groupKey);
        final body = Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _filter,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar serie',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('No hay series'))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final s = list[i];
                        final seasons = s.xtream == null
                            ? s.seasons().length
                            : 0;
                        return ListTile(
                          leading: ChannelLogo(_logoOf(s)),
                          title: Text(
                            s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: s.xtream == null
                              ? Text(
                                  '${seasons == 1 ? '1 temporada' : '$seasons temporadas'} | ${s.episodes.length} capítulos',
                                )
                              : null,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SeriesPage(seriesKey: s.key),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
        if (widget.embedded) {
          return Column(
            children: [
              Material(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$title (${all.length})',
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(child: body),
            ],
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: body,
        );
      },
    );
  }
}

/// Una serie: sus temporadas y capítulos.
class SeriesPage extends StatefulWidget {
  const SeriesPage({super.key, required this.seriesKey});
  final String seriesKey;

  @override
  State<SeriesPage> createState() => _SeriesPageState();
}

class _SeriesPageState extends State<SeriesPage> {
  bool _loading = false;
  String? _error;
  int? _season;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = app.seriesByKey(widget.seriesKey);
    if (s == null || s.xtream == null || s.episodes.isNotEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await app.loadSeriesEpisodes(s);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = err;
    });
  }

  String _seasonLabel(int n) => n == 0 ? 'Capítulos' : 'Temporada $n';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final s = app.seriesByKey(widget.seriesKey);
        if (s == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(
              child: Text('Esta serie ya no está en tus listas'),
            ),
          );
        }
        final seasons = s.seasons();
        final current = seasons.any((x) => x.$1 == _season)
            ? _season
            : (seasons.isNotEmpty ? seasons.first.$1 : null);
        final episodes = current == null
            ? const <Channel>[]
            : seasons.firstWhere((x) => x.$1 == current).$2;
        Widget body;
        if (_loading) {
          body = const Center(child: CircularProgressIndicator());
        } else if (_error != null) {
          body = Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _load,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          );
        } else if (episodes.isEmpty) {
          body = const Center(child: Text('No hay capítulos'));
        } else {
          body = Column(
            children: [
              if (seasons.length > 1)
                SizedBox(
                  height: 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    children: [
                      for (final x in seasons)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(_seasonLabel(x.$1)),
                            selected: x.$1 == current,
                            onSelected: (_) => setState(() => _season = x.$1),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: episodes.length,
                  itemBuilder: (context, i) {
                    final e = episodes[i];
                    return ChannelTile(
                      channel: e,
                      onTap: () => openPlayer(context, episodes, i),
                    );
                  },
                ),
              ),
            ],
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(s.name),
            bottom: seasons.length == 1 && episodes.isNotEmpty
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(22),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(_seasonLabel(seasons.first.$1)),
                    ),
                  )
                : null,
          ),
          body: body,
        );
      },
    );
  }
}
