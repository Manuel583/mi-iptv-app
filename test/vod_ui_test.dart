import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_iptv/app_state.dart';
import 'package:mi_iptv/main.dart';
import 'package:mi_iptv/models.dart';
import 'package:mi_iptv/parsers.dart';
import 'package:mi_iptv/ui/folders_page.dart';
import 'package:mi_iptv/ui/series_page.dart';

void main() {
  setUp(() {
    const m3u = '''#EXTM3U
#EXTINF:-1 group-title="ES | Generalistas",La 1 HD
http://srv.com/live/u/p/1.ts
#EXTINF:-1 group-title="ES | Generalistas",Antena 3
http://srv.com/live/u/p/2.ts
#EXTINF:-1 group-title="ES | Deportes",DAZN LaLiga
http://srv.com/live/u/p/3.ts
#EXTINF:-1 group-title="VOD | Acción",Gladiator (2000)
http://srv.com/movie/u/p/4.mkv
#EXTINF:-1 group-title="Series | Drama",Breaking Bad S01E01
http://srv.com/series/u/p/5.mkv
#EXTINF:-1 group-title="Series | Drama",Breaking Bad S02E01
http://srv.com/series/u/p/6.mkv
''';
    final src = PlaylistSource(
      id: 't',
      name: 'Prueba',
      type: SourceType.m3uUrl,
    );
    app.debugSetData(src, parseM3u(m3u, 't').channels);
  });

  for (final size in [const Size(400, 800), const Size(1280, 800)]) {
    testWidgets(
      'Películas, series y carpetas automáticas a ${size.width.toInt()} px',
      (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);

        expect(app.allChannels.length, 3);
        expect(app.allMovies.length, 1);
        expect(app.seriesCount, 1);

        await t.pumpWidget(const MiIptvApp());
        await t.pumpAndSettle();
        // En "Canales" no aparecen las películas ni las series.
        expect(find.text('VOD | Acción'), findsNothing);

        await t.tap(find.byIcon(Icons.movie_outlined).last);
        await t.pumpAndSettle();
        expect(find.text('VOD | Acción'), findsWidgets);

        await t.tap(find.byIcon(Icons.subscriptions_outlined).last);
        await t.pumpAndSettle();
        expect(find.text('Series | Drama'), findsWidgets);

        final smart = app.smartFolders();
        expect(smart[0].channels.map((c) => c.name), ['DAZN LaLiga']);
        expect(smart[1].channels.map((c) => c.name), ['La 1 HD', 'Antena 3']);

        await t.pumpWidget(
          const MaterialApp(home: Scaffold(body: FoldersPage())),
        );
        await t.pumpAndSettle();
        expect(find.text('Fútbol'), findsOneWidget);
        expect(find.text('TDT'), findsOneWidget);
        await t.tap(find.text('TDT'));
        await t.pumpAndSettle();
        expect(find.text('Antena 3'), findsOneWidget);

        final key = app.seriesInGroup('Series | Drama').single.key;
        await t.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            home: SeriesPage(seriesKey: key),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('Temporada 2'), findsOneWidget);
        await t.tap(find.text('Temporada 2'));
        await t.pumpAndSettle();
        expect(find.text('Breaking Bad S02E01'), findsOneWidget);
        await t.pump(const Duration(seconds: 1));
      },
    );
  }
}
