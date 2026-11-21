import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mi_iptv/cast.dart';
import 'package:mi_iptv/recordings.dart';

void main() {
  test('Mensaje Chromecast: codificar y decodificar', () {
    final m = encodeCastMessage(
      'sender-0',
      'receiver-0',
      'urn:x-cast:com.google.cast.tp.connection',
      '{"type":"CONNECT"}',
    );
    final len = (m[0] << 24) | (m[1] << 16) | (m[2] << 8) | m[3];
    expect(len, m.length - 4);
    final d = decodeCastMessage(Uint8List.sublistView(m, 4));
    expect(d.source, 'sender-0');
    expect(d.destination, 'receiver-0');
    expect(d.namespace, 'urn:x-cast:com.google.cast.tp.connection');
    expect(d.payload, '{"type":"CONNECT"}');
  });

  test('Lista HLS reescrita para pasar por el relé', () {
    const body =
        '#EXTM3U\n'
        '#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n'
        '#EXTINF:6,\n'
        'seg1.ts\n'
        'http://otro.com/seg2.ts\n';
    final out = rewriteHls(
      body,
      Uri.parse('http://srv.com/live/canal/index.m3u8'),
      (u) => 'R($u)',
    );
    expect(out, contains('URI="R(http://srv.com/live/canal/key.bin)"'));
    expect(out, contains('R(http://srv.com/live/canal/seg1.ts)'));
    expect(out, contains('R(http://otro.com/seg2.ts)'));
    expect(out, contains('#EXTINF:6,'));
  });

  test('Descripción DLNA de una Samsung', () {
    const xml = '''<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
 <device>
  <friendlyName>[TV] Samsung QEF1 50</friendlyName>
  <serviceList>
   <service>
    <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
    <controlURL>/upnp/control/RenderingControl1</controlURL>
   </service>
   <service>
    <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
    <controlURL>/upnp/control/AVTransport1</controlURL>
   </service>
  </serviceList>
 </device>
</root>''';
    final r = parseDlnaDescription(
      xml,
      Uri.parse('http://192.168.1.50:9197/dmr'),
    );
    expect(r, isNotNull);
    expect(r!.$1, '[TV] Samsung QEF1 50');
    expect(
      r.$2.toString(),
      'http://192.168.1.50:9197/upnp/control/AVTransport1',
    );
  });

  test('Respuesta mDNS de un Chromecast', () {
    final b = BytesBuilder();
    void name(String n) {
      for (final p in n.split('.')) {
        b.addByte(p.length);
        b.add(utf8.encode(p));
      }
      b.addByte(0);
    }

    void u16(int v) => b.add([v >> 8, v & 0xff]);
    void rr(String n, int type, List<int> data) {
      name(n);
      u16(type);
      u16(1);
      b.add([0, 0, 0, 120]);
      u16(data.length);
      b.add(data);
    }

    b.add([0, 0, 0x84, 0, 0, 0, 0, 1, 0, 0, 0, 2]);
    final inst = 'Chromecast-abc._googlecast._tcp.local';
    final ptr = BytesBuilder();
    for (final p in inst.split('.')) {
      ptr.addByte(p.length);
      ptr.add(utf8.encode(p));
    }
    ptr.addByte(0);
    rr('_googlecast._tcp.local', 12, ptr.takeBytes());
    final srv = BytesBuilder()..add([0, 0, 0, 0, 0x1f, 0x49]);
    for (final p in 'abc.local'.split('.')) {
      srv.addByte(p.length);
      srv.add(utf8.encode(p));
    }
    srv.addByte(0);
    rr(inst, 33, srv.takeBytes());
    final fn = utf8.encode('fn=Tele salón');
    rr(inst, 16, [fn.length, ...fn]);
    final out = parseMdnsCast(b.takeBytes(), '192.168.1.60');
    expect(out, [('Tele salón', '192.168.1.60', 8009)]);
  });

  test('Tipo de vídeo para la tele', () {
    expect(
      guessMime('http://a/b/index.m3u8?x=1', CastKind.dlna),
      'application/vnd.apple.mpegurl',
    );
    expect(guessMime('http://a/live/u/p/123.ts', CastKind.dlna), 'video/mp2t');
    expect(
      guessMime('http://a/movie/u/p/9.mp4', CastKind.chromecast),
      'video/mp4',
    );
  });

  test('Formato de tiempos y tamaños', () {
    expect(formatDuration(const Duration(minutes: 3, seconds: 5)), '3:05');
    expect(formatDuration(const Duration(hours: 1, minutes: 2)), '1:02:00');
    expect(formatDuration(const Duration(seconds: -75)), '-1:15');
    expect(formatBytes(1536 * 1024 * 1024), '1,5 GB');
  });
}
