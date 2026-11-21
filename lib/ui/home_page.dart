import 'package:flutter/material.dart';

import '../app_state.dart';
import 'browse_page.dart';
import 'guide_page.dart';
import 'common.dart';
import 'folders_page.dart';
import 'recordings_page.dart';
import 'search_page.dart';
import 'settings_page.dart';
import 'sources_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

enum _Section {
  channels,
  movies,
  series,
  countries,
  favorites,
  folders,
  settings,
}

class _HomePageState extends State<HomePage> {
  _Section _current = _Section.channels;

  static const _info = {
    _Section.channels: (Icons.live_tv_outlined, Icons.live_tv, 'Canales'),
    _Section.movies: (Icons.movie_outlined, Icons.movie, 'Películas'),
    _Section.series: (
      Icons.subscriptions_outlined,
      Icons.subscriptions,
      'Series',
    ),
    _Section.countries: (Icons.public_outlined, Icons.public, 'Países'),
    _Section.favorites: (Icons.star_border, Icons.star, 'Favoritos'),
    _Section.folders: (Icons.folder_outlined, Icons.folder, 'Carpetas'),
    _Section.settings: (Icons.settings_outlined, Icons.settings, 'Ajustes'),
  };

  /// Películas y Series sólo aparecen si alguna lista las tiene.
  List<_Section> _sections() => [
    _Section.channels,
    if (app.hasMovies) _Section.movies,
    if (app.hasSeries) _Section.series,
    _Section.countries,
    _Section.favorites,
    _Section.folders,
    _Section.settings,
  ];

  Widget _body() {
    if (app.sources.isEmpty && _current != _Section.settings) {
      return const _Welcome();
    }
    switch (_current) {
      case _Section.channels:
        return const BrowsePage(mode: BrowseMode.groups);
      case _Section.movies:
        return const BrowsePage(mode: BrowseMode.movies);
      case _Section.series:
        return const BrowsePage(mode: BrowseMode.series);
      case _Section.countries:
        return const BrowsePage(mode: BrowseMode.countries);
      case _Section.favorites:
        return const FavoritesPage();
      case _Section.folders:
        return const FoldersPage();
      case _Section.settings:
        return const SettingsPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final sections = _sections();
        if (!sections.contains(_current)) _current = _Section.channels;
        final index = sections.indexOf(_current);
        void select(int i) => setState(() => _current = sections[i]);
        final appBar = AppBar(
          title: Text(_info[_current]!.$3),
          actions: [
            if (app.refreshing || app.epgLoading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            IconButton(
              tooltip: 'Guía de programación',
              icon: const Icon(Icons.view_timeline_outlined),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const GuidePage())),
            ),
            IconButton(
              tooltip: 'Buscar canal',
              icon: const Icon(Icons.search),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const SearchPage())),
            ),
            IconButton(
              tooltip: 'Grabaciones',
              icon: const Icon(Icons.video_library_outlined),
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const RecordingsPage())),
            ),
            IconButton(
              tooltip: 'Mosaico (varios canales a la vez)',
              icon: const Icon(Icons.grid_view),
              onPressed: () => openMosaic(context, [null, null]),
            ),
            IconButton(
              tooltip: 'Actualizar listas y guía',
              icon: const Icon(Icons.refresh),
              onPressed: app.refreshing
                  ? null
                  : () async {
                      await app.refreshAll();
                      if (context.mounted) {
                        final errors = app.sources
                            .where((s) => s.lastError != null)
                            .map((s) => s.name);
                        showMessage(
                          context,
                          errors.isEmpty
                              ? 'Listas actualizadas'
                              : 'No se pudieron actualizar: ${errors.join(', ')}',
                        );
                      }
                    },
            ),
          ],
          bottom: app.refreshStatus.isEmpty
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(22),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      app.refreshStatus,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
        );
        if (wide) {
          return Scaffold(
            appBar: appBar,
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: index,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: select,
                  destinations: [
                    for (final d in sections.map((x) => _info[x]!))
                      NavigationRailDestination(
                        icon: Icon(d.$1),
                        selectedIcon: Icon(d.$2),
                        label: Text(d.$3),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _body()),
              ],
            ),
          );
        }
        return Scaffold(
          appBar: appBar,
          body: _body(),
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: select,
            // Con muchas secciones sólo se ve el nombre de la elegida.
            labelBehavior: sections.length > 5
                ? NavigationDestinationLabelBehavior.onlyShowSelected
                : NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              for (final d in sections.map((x) => _info[x]!))
                NavigationDestination(
                  icon: Icon(d.$1),
                  selectedIcon: Icon(d.$2),
                  label: d.$3,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.live_tv,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Bienvenido a Mi IPTV',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Para empezar, añade tu primera lista de canales: por enlace M3U, '
                'desde un archivo o con los datos de tu servidor (Xtream Codes).\n\n'
                'Si ya tienes la configuración en otro dispositivo, puedes importarla '
                'desde Ajustes.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Añadir una lista'),
                onPressed: () => showAddSourceMenu(context),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Importar configuración'),
                onPressed: () => importConfigFlow(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
