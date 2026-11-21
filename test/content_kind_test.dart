import 'package:flutter_test/flutter_test.dart';
import 'package:mi_iptv/content_kind.dart';
import 'package:mi_iptv/models.dart';
import 'package:mi_iptv/parsers.dart';

void main() {
  test('Separa canales, películas y series en una lista M3U', () {
    const m3u = '''#EXTM3U
#EXTINF:-1 group-title="ES | Generalistas",La 1 HD
http://srv.com/live/u/p/1.ts
#EXTINF:-1 group-title="ES | Cine",Movistar Estrenos
http://srv.com/u/p/2
#EXTINF:-1 group-title="VOD | Acción",Gladiator (2000)
http://srv.com/movie/u/p/3.mkv
#EXTINF:-1 group-title="Películas",Titanic (1997)
http://cdn.com/titanic.mp4
#EXTINF:-1 group-title="Series | Drama",Breaking Bad S01E02
http://srv.com/series/u/p/4.mkv
#EXTINF:-1 group-title="Series | Drama",Breaking Bad S02 E01 - Siete y treinta y siete
http://srv.com/series/u/p/5.mkv
#EXTINF:-1 group-title="Series 24/7",Los Simpson 24/7
http://srv.com/u/p/6.m3u8
#EXTINF:-1 group-title="Comedia",La que se avecina 1x05
http://cdn.com/lqsa.mp4
''';
    final ch = parseM3u(m3u, 's').channels;
    expect(ch.map((c) => c.kind).toList(), [
      ContentKind.live,
      ContentKind.live,
      ContentKind.movie,
      ContentKind.movie,
      ContentKind.series,
      ContentKind.series,
      ContentKind.live,
      ContentKind.series,
    ]);
    expect(ch[4].seriesName, 'Breaking Bad');
    expect(ch[4].season, 1);
    expect(ch[4].episode, 2);
    expect(ch[5].seriesName, 'Breaking Bad');
    expect(ch[5].season, 2);
    expect(ch[7].seriesName, 'La que se avecina');
    expect(ch[7].season, 1);
    expect(ch[7].episode, 5);
    // Se guarda y se recupera igual.
    final back = Channel.fromJson(ch[4].toJson());
    expect(back.kind, ContentKind.series);
    expect(back.seriesName, 'Breaking Bad');
    expect(Channel.fromJson(ch[0].toJson()).kind, ContentKind.live);
  });

  test('Lee películas, series y capítulos de Xtream', () {
    final vod = parseXtreamVod(
      categoriesJson: '[{"category_id":"7","category_name":"Estrenos"}]',
      streamsJson: '[{"stream_id":9,"name":"Dune","category_id":"7","container_extension":"mkv"}]',
      sourceId: 'x',
      server: 'http://srv:80',
      username: 'yo',
      password: 'clave',
    );
    expect(vod.single.url, 'http://srv:80/movie/yo/clave/9.mkv');
    expect(vod.single.kind, ContentKind.movie);
    expect(vod.single.group, 'Estrenos');

    final series = parseXtreamSeries(
      categoriesJson: '[{"category_id":"3","category_name":"Drama"}]',
      seriesJson: '[{"series_id":12,"name":"The Wire","category_id":"3","cover":"http://c/w.jpg"}]',
      sourceId: 'x',
    );
    expect(series.single.seriesId, '12');
    expect(series.single.kind, ContentKind.series);

    final eps = parseXtreamSeriesInfo(
      json: '{"episodes":{"2":[{"id":"101","episode_num":1,"title":"T2 C1","container_extension":"mp4","season":2}],"1":[{"id":"100","episode_num":"1","title":"Piloto","container_extension":"mkv"}]}}',
      series: series.single,
      server: 'http://srv:80',
      username: 'yo',
      password: 'clave',
    );
    expect(eps.length, 2);
    expect(eps.first.season, 1);
    expect(eps.first.url, 'http://srv:80/series/yo/clave/100.mkv');
    expect(eps.last.season, 2);
  });

  test('Reconoce canales de la TDT', () {
    for (final n in [
      'La 1 HD',
      'ES: La 1',
      '|ES| Antena 3 FHD',
      'Cuatro',
      'Telecinco HD',
      'laSexta',
      'La Sexta HD',
      'TV3',
      'Telemadrid',
      'Canal Sur Andalucía',
      'À Punt',
      'ETB 2',
      'Neox',
      'DMAX',
      '24h',
      'Clan TVE',
      'Trece',
      'La 1 Cataluña',
    ]) {
      expect(isTdtChannel(name: n), isTrue, reason: n);
    }
    for (final n in [
      'Antena 3 Internacional',
      'Movistar Plus+',
      'CNN',
      'Cuatro Cosas',
      'DAZN 1',
    ]) {
      expect(isTdtChannel(name: n), isFalse, reason: n);
    }
    expect(isTdtChannel(name: 'Nova', country: 'República Checa'), isFalse);
  });

  test('Reconoce canales de fútbol', () {
    for (final n in [
      'DAZN 1 HD',
      'DAZN LaLiga',
      'M+ LaLiga FHD',
      'Movistar LaLiga',
      'Movistar Liga de Campeones 1',
      'M+ Liga de Campeones 2',
      'LaLiga TV Hypermotion',
      'Gol Play',
      'GOL',
      'Real Madrid TV',
      'Barça TV',
      'Sky Sports Premier League',
    ]) {
      expect(isFootballChannel(name: n), isTrue, reason: n);
    }
    for (final n in [
      'DAZN F1',
      'Movistar Golf',
      'La 1',
      'Eurosport 1',
      'DAZN Baloncesto',
    ]) {
      expect(isFootballChannel(name: n), isFalse, reason: n);
    }
    expect(isFootballChannel(name: 'Canal 5', group: 'ES | FÚTBOL'), isTrue);
  });
}
