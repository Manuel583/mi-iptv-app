import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_iptv/app_state.dart';
import 'package:mi_iptv/main.dart';
import 'package:mi_iptv/models.dart';
import 'package:mi_iptv/parsers.dart';
import 'package:mi_iptv/ui/folders_page.dart';
import 'package:mi_iptv/ui/settings_page.dart';
import 'package:mi_iptv/ui/sources_page.dart';

void main() {
  setUp(() {
    final buf = StringBuffer('#EXTM3U\n');
    for (final g in ['ES | Noticias', 'US: News', 'Deportes']) {
      for (var i = 0; i < 15; i++) {
        buf.writeln('#EXTINF:-1 group-title="$g",Canal $g $i');
        buf.writeln('http://example.com/$g/$i.ts');
      }
    }
    final src = PlaylistSource(id: 't', name: 'Prueba', type: SourceType.m3uUrl);
    app.debugSetData(src, parseM3u(buf.toString(), 't').channels);
  });

  for (final size in [const Size(400, 800), const Size(1280, 800)]) {
    testWidgets('Pantallas principales a ${size.width.toInt()} px', (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);

      await t.pumpWidget(const MiIptvApp());
      await t.pumpAndSettle();
      expect(find.text('ES | Noticias'), findsWidgets);

      // Favoritos y carpetas.
      final c = app.allChannels.first;
      app.toggleFavorite(c);
      final f = app.createFolder('Elecciones');
      app.addToFolder(f, c);
      app.renameChannel(c, 'Mi canal');
      app.renameGroup('Deportes', 'Fútbol');
      app.setGroupHidden('US: News', true);
      app.reorderGroups(0, 2);
      await t.pumpAndSettle();
      expect(app.favoriteChannels().single.key, c.key);
      expect(app.groups().map((g) => g.name), isNot(contains('US: News')));

      for (final label in ['Países', 'Favoritos', 'Carpetas', 'Ajustes']) {
        await t.tap(find.text(label).last);
        await t.pumpAndSettle();
      }
      expect(find.text('Mis listas'), findsOneWidget);

      await t.pumpWidget(MaterialApp(home: Scaffold(body: const FavoritesPage())));
      await t.pumpAndSettle();
      expect(find.text('Mi canal'), findsOneWidget);
      await t.pumpWidget(MaterialApp(home: FolderPage(folder: f)));
      await t.pumpAndSettle();
      await t.pumpWidget(const MaterialApp(home: SourcesPage()));
      await t.pumpAndSettle();
      await t.pumpWidget(
          const MaterialApp(home: SourceEditorPage(type: SourceType.xtream)));
      await t.pumpAndSettle();
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: SettingsPage())));
      await t.pumpAndSettle();
      app.deleteFolder(f);
      app.toggleFavorite(c);
      app.setGroupHidden('US: News', false);
      await t.pump(const Duration(seconds: 1));
    });
  }
}
