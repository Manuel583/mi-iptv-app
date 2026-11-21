import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_iptv/app_state.dart';
import 'package:mi_iptv/epg.dart';
import 'package:mi_iptv/models.dart';
import 'package:mi_iptv/parsers.dart';
import 'package:mi_iptv/ui/common.dart';
import 'package:mi_iptv/ui/guide_page.dart';

void main() {
  setUp(() {
    final buf = StringBuffer('#EXTM3U\n');
    for (var i = 0; i < 30; i++) {
      buf.writeln('#EXTINF:-1 group-title="Noticias",Canal $i HD');
      buf.writeln('http://example.com/$i.ts');
    }
    final src = PlaylistSource(
      id: 'g',
      name: 'Prueba',
      type: SourceType.m3uUrl,
    );
    app.debugSetData(src, parseM3u(buf.toString(), 'g').channels);
    final now = DateTime.now();
    final base = DateTime(now.year, now.month, now.day, now.hour);
    final programmes = <String, List<Programme>>{};
    final names = <String, String>{};
    for (var i = 0; i < 30; i++) {
      names[epgNameKey('Canal $i')] = 'c$i';
      programmes['c$i'] = [
        for (var h = -3; h < 6; h++)
          Programme(
            base.add(Duration(hours: h)),
            base.add(Duration(hours: h + 1)),
            'Programa $i/$h',
            'Descripción',
          ),
      ];
    }
    app.epg = EpgData(programmes, names);
    app.changed(reindex: true);
  });

  for (final size in [const Size(400, 800), const Size(1280, 800)]) {
    testWidgets('Guía en rejilla a ${size.width.toInt()} px', (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(const MaterialApp(home: GuidePage()));
      await t.pumpAndSettle();
      expect(find.text('Guía de programación'), findsOneWidget);
      // El programa de ahora del primer canal está a la vista.
      expect(find.text('Programa 0/0'), findsOneWidget);
      await t.tap(find.text('Programa 0/0'));
      await t.pumpAndSettle();
      expect(find.text('Ver ahora'), findsOneWidget);
      expect(find.text('Descripción'), findsWidgets);
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('Lista de canales con ahora y después', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChannelListView(channels: app.allChannels)),
      ),
    );
    await t.pumpAndSettle();
    expect(find.textContaining('Programa 0/0'), findsOneWidget);
    expect(find.textContaining('Después: '), findsWidgets);
  });
}
