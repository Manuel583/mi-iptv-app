import 'package:flutter_test/flutter_test.dart';
import 'package:mi_iptv/country.dart';
import 'package:mi_iptv/epg.dart';
import 'package:mi_iptv/parsers.dart';

void main() {
  test('Lee una lista M3U con atributos, grupos y opciones VLC', () {
    const m3u = '''#EXTM3U url-tvg="http://epg.example/guia.xml.gz"
#EXTINF:-1 tvg-id="La1.es" tvg-name="La 1" tvg-logo="http://logo/la1.png" group-title="ES | Generalistas",La 1 HD
http://example.com/la1.m3u8
#EXTINF:-1 tvg-id="CNN.us" group-title="News, World",CNN, International
#EXTVLCOPT:http-user-agent=MiAgente/1.0
http://example.com/cnn.ts
#EXTINF:-1,Sin grupo
#EXTGRP:Radio
http://example.com/radio
#EXTINF:-1 group-title="ES | Generalistas",La 1 HD
http://example.com/la1-backup.m3u8
''';
    final p = parseM3u(m3u, 'src');
    expect(p.epgUrl, 'http://epg.example/guia.xml.gz');
    expect(p.channels.length, 4);
    final la1 = p.channels[0];
    expect(la1.name, 'La 1 HD');
    expect(la1.group, 'ES | Generalistas');
    expect(la1.tvgId, 'La1.es');
    expect(la1.logo, 'http://logo/la1.png');
    expect(la1.country, 'España');
    expect(p.channels[1].name, 'CNN, International');
    expect(p.channels[1].userAgent, 'MiAgente/1.0');
    expect(p.channels[1].country, 'Estados Unidos');
    expect(p.channels[2].group, 'Radio');
    // Claves únicas aunque se repita el nombre.
    expect(p.channels[3].key, isNot(p.channels[0].key));
  });

  test('Detecta países', () {
    expect(detectCountry(group: 'UK: News'), 'Reino Unido');
    expect(detectCountry(group: '|FR| Info'), 'Francia');
    expect(detectCountry(group: 'Spain'), 'España');
    expect(detectCountry(group: 'AR | Noticias'), arabCountries);
    expect(detectCountry(tvgCountry: 'MX'), 'México');
    expect(detectCountry(tvgId: 'AlJazeera.qa@SD'), 'Qatar');
    expect(detectCountry(name: 'AL JAZEERA'), noCountry);
    expect(detectCountry(group: 'Deportes'), noCountry);
  });

  test('Lee respuestas de Xtream Codes', () {
    final list = parseXtream(
      categoriesJson: '[{"category_id":"1","category_name":"USA News"}]',
      streamsJson: '[{"name":"CNN","stream_id":55,"stream_icon":"","epg_channel_id":"cnn.us","category_id":"1"}]',
      sourceId: 'x',
      server: 'http://srv:8080',
      username: 'yo',
      password: 'clave',
      output: 'ts',
    );
    expect(list.single.url, 'http://srv:8080/live/yo/clave/55.ts');
    expect(list.single.group, 'USA News');
    expect(list.single.country, 'Estados Unidos');
    expect(normalizeServer('srv.com:8080/'), 'http://srv.com:8080');
    final x = extractXtreamFromUrl(
      'http://srv.com:8080/get.php?username=a&password=b&type=m3u_plus',
    );
    expect(x, ('http://srv.com:8080', 'a', 'b'));
  });

  test('Lee una guía XMLTV', () async {
    final now = DateTime.now().toUtc();
    String fmt(DateTime d) =>
        '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}'
        '${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}00 +0000';
    final xml =
        '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <channel id="La1.es"><display-name>La 1 HD</display-name></channel>
  <programme start="${fmt(now.subtract(const Duration(minutes: 30)))}" stop="${fmt(now.add(const Duration(minutes: 30)))}" channel="La1.es">
    <title lang="es">Telediario &amp; más</title><desc>Noticias</desc>
  </programme>
  <programme start="${fmt(now.add(const Duration(minutes: 30)))}" stop="${fmt(now.add(const Duration(minutes: 90)))}" channel="La1.es">
    <title><![CDATA[El tiempo]]></title>
  </programme>
  <programme start="20000101000000 +0000" stop="20000101010000 +0000" channel="La1.es"><title>Viejo</title></programme>
</tv>''';
    final data = await parseXmltvStream(
      Stream.value(xml),
      DateTime.now().subtract(const Duration(hours: 3)),
      DateTime.now().add(const Duration(days: 2)),
    );
    final list = data.programmes['la1.es']!;
    expect(list.length, 2);
    final (cur, next) = nowAndNext(list, DateTime.now());
    expect(cur!.title, 'Telediario & más');
    expect(cur.desc, 'Noticias');
    expect(next!.title, 'El tiempo');
    expect(data.nameToId[epgNameKey('La 1')], 'la1.es');
  });
}
