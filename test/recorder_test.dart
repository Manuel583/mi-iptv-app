import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mi_iptv/epg.dart';
import 'package:mi_iptv/stream_recorder.dart';

void main() {
  late HttpServer server;
  late Directory tmp;
  var seq = 0;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('grab');
    seq = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final p = req.uri.path;
      if (p == '/canal.ts') {
        // Emisión continua: 1 KB cada 100 ms.
        req.response.headers.contentType = ContentType('video', 'mp2t');
        for (var i = 0; i < 100; i++) {
          req.response.add(List.filled(1024, 0x47));
          await req.response.flush();
          await Future.delayed(const Duration(milliseconds: 100));
        }
        await req.response.close();
      } else if (p == '/master.m3u8') {
        req.response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
        );
        req.response.write(
          '#EXTM3U\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=800000\nbaja/lista.m3u8\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=5000000\nalta/lista.m3u8\n',
        );
        await req.response.close();
      } else if (p == '/alta/lista.m3u8') {
        seq++;
        req.response.write(
          '#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:$seq\n'
          '#EXTINF:2,\nseg$seq.ts\n#EXTINF:2,\nseg${seq + 1}.ts\n',
        );
        await req.response.close();
      } else if (p.startsWith('/alta/seg')) {
        req.response.add(utf8.encode('[${p.substring(9)}]'));
        await req.response.close();
      } else {
        req.response.statusCode = 404;
        await req.response.close();
      }
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await tmp.delete(recursive: true);
  });

  test('graba un enlace .ts hasta la hora de fin', () async {
    final out = '${tmp.path}/a.ts';
    final r = StreamRecorder(
      url: 'http://127.0.0.1:${server.port}/canal.ts',
      outPath: out,
      stopAt: DateTime.now().add(const Duration(milliseconds: 1200)),
    );
    final sw = Stopwatch()..start();
    expect(await r.run(), isTrue);
    expect(sw.elapsedMilliseconds, lessThan(4000));
    final size = await File(out).length();
    expect(size, greaterThan(5 * 1024));
    expect(size, lessThan(30 * 1024));
  });

  test('graba HLS: elige la mejor calidad y no repite trozos', () async {
    final out = '${tmp.path}/b.ts';
    final r = StreamRecorder(
      url: 'http://127.0.0.1:${server.port}/master.m3u8',
      outPath: out,
      stopAt: DateTime.now().add(const Duration(milliseconds: 3500)),
    );
    expect(await r.run(), isTrue);
    final text = await File(out).readAsString();
    // Cada trozo aparece una sola vez y en orden.
    final segs = RegExp(r'\[(\d+)\.ts\]')
        .allMatches(text)
        .map((m) => int.parse(m.group(1)!))
        .toList();
    expect(segs.length, greaterThanOrEqualTo(3));
    expect(segs.toSet().length, segs.length);
    for (var i = 1; i < segs.length; i++) {
      expect(segs[i], segs[i - 1] + 1);
    }
  });

  test('sin vídeo no deja archivo', () async {
    final out = '${tmp.path}/c.ts';
    final r = StreamRecorder(
      url: 'http://127.0.0.1:${server.port}/no-existe.ts',
      outPath: out,
      stopAt: DateTime.now().add(const Duration(milliseconds: 500)),
    );
    expect(await r.run(), isFalse);
    expect(File(out).existsSync(), isFalse);
  });

  test('guía Xtream en base64 y número de emisión', () {
    String b(String s) => base64.encode(utf8.encode(s));
    final text = jsonEncode({
      'epg_listings': [
        {
          'title': b('Telediario'),
          'description': b('Noticias del día'),
          'start_timestamp': '1763740800',
          'stop_timestamp': '1763744400',
        },
        {
          'title': b('El tiempo'),
          'description': '',
          'start_timestamp': '1763744400',
          'stop_timestamp': '1763745000',
        },
      ],
    });
    final list = parseXtreamEpg(text);
    expect(list.length, 2);
    expect(list.first.title, 'Telediario');
    expect(list.first.desc, 'Noticias del día');
    expect(list.first.stop.difference(list.first.start).inMinutes, 60);
    expect(xtreamStreamId('http://srv:8080/live/u/p/12345.ts'), '12345');
    expect(xtreamStreamId('http://srv/live/u/p/77.m3u8'), '77');
    expect(xtreamStreamId('http://otra.com/canal.m3u8'), isNull);
  });
}
