// Emitir a televisores: DLNA/UPnP (Samsung, LG, Sony...) y Chromecast.
//
// La tele descarga el canal por su cuenta. Si hace falta, la señal puede pasar
// por este dispositivo (StreamRelay), que añade el User-Agent del canal y los
// permisos (CORS) que pide Chromecast.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import 'models.dart';

enum CastKind { dlna, chromecast }

abstract class CastDevice {
  CastDevice(this.name, this.host);
  final String name;
  final String host;
  CastKind get kind;
  String get id;

  /// Empieza a reproducir [url] en la tele.
  Future<void> play(String url, {required String title, required String mime});

  /// Deja de reproducir en la tele.
  Future<void> stop();

  /// Cierra conexiones abiertas.
  void close() {}
}

/// Tipo de contenido que se le dice a la tele.
String guessMime(String url, CastKind kind) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
  if (path.endsWith('.m3u8') || path.endsWith('.m3u') || url.contains('m3u8')) {
    return kind == CastKind.chromecast
        ? 'application/x-mpegURL'
        : 'application/vnd.apple.mpegurl';
  }
  if (path.endsWith('.mp4') || path.endsWith('.m4v')) return 'video/mp4';
  if (path.endsWith('.mkv')) return 'video/x-matroska';
  if (path.endsWith('.webm')) return 'video/webm';
  if (path.endsWith('.mp3')) return 'audio/mpeg';
  return 'video/mp2t';
}

String _xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

HttpClient _httpClient() => HttpClient()
  ..connectionTimeout = const Duration(seconds: 6)
  ..badCertificateCallback = (_, _, _) => true;

// ======================================================================= DLNA

class DlnaDevice extends CastDevice {
  DlnaDevice(super.name, super.host, this.controlUrl);
  final Uri controlUrl;

  @override
  CastKind get kind => CastKind.dlna;

  @override
  String get id => 'dlna:$controlUrl';

  static String didl(String url, String title, String mime) {
    final dlnaFlags = mime.startsWith('video/mp2t')
        ? 'DLNA.ORG_OP=00;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000'
        : '*';
    return '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
        '<item id="0" parentID="-1" restricted="1">'
        '<dc:title>${_xmlEscape(title)}</dc:title>'
        '<upnp:class>object.item.videoItem</upnp:class>'
        '<res protocolInfo="http-get:*:$mime:$dlnaFlags">${_xmlEscape(url)}</res>'
        '</item></DIDL-Lite>';
  }

  Future<String> _soap(String action, String args) async {
    const ns = 'urn:schemas-upnp-org:service:AVTransport:1';
    final body =
        '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body><u:$action xmlns:u="$ns"><InstanceID>0</InstanceID>$args'
        '</u:$action></s:Body></s:Envelope>';
    final client = _httpClient();
    try {
      final req = await client.postUrl(controlUrl);
      req.headers.set('Content-Type', 'text/xml; charset="utf-8"');
      req.headers.set('SOAPACTION', '"$ns#$action"');
      final bytes = utf8.encode(body);
      req.contentLength = bytes.length;
      req.add(bytes);
      final res = await req.close().timeout(const Duration(seconds: 10));
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode >= 300) {
        throw HttpException(
          'La tele respondió $action ${res.statusCode}: $text',
        );
      }
      return text;
    } finally {
      client.close();
    }
  }

  @override
  Future<void> play(
    String url, {
    required String title,
    required String mime,
  }) async {
    try {
      await _soap('Stop', '');
    } catch (_) {}
    await _soap(
      'SetAVTransportURI',
      '<CurrentURI>${_xmlEscape(url)}</CurrentURI>'
          '<CurrentURIMetaData>${_xmlEscape(didl(url, title, mime))}</CurrentURIMetaData>',
    );
    await _soap('Play', '<Speed>1</Speed>');
  }

  @override
  Future<void> stop() => _soap('Stop', '');
}

/// Lee la descripción de un aparato UPnP y devuelve su nombre y control AVTransport.
(String, Uri)? parseDlnaDescription(String xmlText, Uri location) {
  final doc = XmlDocument.parse(xmlText);
  String text(XmlElement e, String tag) =>
      e.descendants
          .whereType<XmlElement>()
          .where((x) => x.localName == tag)
          .map((x) => x.innerText.trim())
          .firstOrNull ??
      '';
  final root = doc.rootElement;
  final base = text(root, 'URLBase');
  final baseUri = base.isNotEmpty ? Uri.parse(base) : location;
  for (final s in root.descendants.whereType<XmlElement>().where(
    (x) => x.localName == 'service',
  )) {
    if (text(s, 'serviceType').contains('AVTransport')) {
      final control = text(s, 'controlURL');
      if (control.isEmpty) continue;
      var name = text(root, 'friendlyName');
      if (name.isEmpty) name = location.host;
      return (name, baseUri.resolve(control));
    }
  }
  return null;
}

Stream<CastDevice> _discoverDlna(Duration timeout) async* {
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  final seen = <String>{};
  final controller = StreamController<CastDevice>();
  final pending = <Future>[];
  const search = [
    'urn:schemas-upnp-org:service:AVTransport:1',
    'urn:schemas-upnp-org:device:MediaRenderer:1',
  ];
  void send() {
    for (final st in search) {
      final msg =
          'M-SEARCH * HTTP/1.1\r\n'
          'HOST: 239.255.255.250:1900\r\n'
          'MAN: "ssdp:discover"\r\n'
          'MX: 2\r\n'
          'ST: $st\r\n\r\n';
      try {
        socket.send(utf8.encode(msg), InternetAddress('239.255.255.250'), 1900);
      } catch (e) {
        debugPrint('SSDP: $e');
      }
    }
  }

  socket.listen((ev) {
    if (ev != RawSocketEvent.read) return;
    final d = socket.receive();
    if (d == null) return;
    final text = utf8.decode(d.data, allowMalformed: true);
    final m = RegExp(
      r'^location:\s*(\S+)',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(text);
    if (m == null) return;
    final loc = m.group(1)!;
    if (!seen.add(loc)) return;
    pending.add(() async {
      final client = _httpClient();
      try {
        final uri = Uri.parse(loc);
        final req = await client.getUrl(uri);
        final res = await req.close().timeout(const Duration(seconds: 5));
        final body = await res.transform(utf8.decoder).join();
        final r = parseDlnaDescription(body, uri);
        if (r != null && !controller.isClosed) {
          controller.add(DlnaDevice(r.$1, uri.host, r.$2));
        }
      } catch (e) {
        debugPrint('DLNA $loc: $e');
      } finally {
        client.close();
      }
    }());
  });
  send();
  Timer(const Duration(milliseconds: 800), send);
  Timer(timeout, () async {
    socket.close();
    await Future.wait(pending);
    await controller.close();
  });
  yield* controller.stream;
}

// ================================================================= Chromecast

/// Codifica un CastMessage (protobuf) con longitud delante.
Uint8List encodeCastMessage(
  String source,
  String destination,
  String namespace,
  String payload,
) {
  final b = BytesBuilder();
  void varint(int v) {
    while (v >= 0x80) {
      b.addByte((v & 0x7f) | 0x80);
      v >>= 7;
    }
    b.addByte(v);
  }

  void str(int field, String s) {
    final bytes = utf8.encode(s);
    varint((field << 3) | 2);
    varint(bytes.length);
    b.add(bytes);
  }

  varint(1 << 3);
  varint(0);
  str(2, source);
  str(3, destination);
  str(4, namespace);
  varint(5 << 3);
  varint(0);
  str(6, payload);
  final body = b.takeBytes();
  final out = BytesBuilder()
    ..add([
      (body.length >> 24) & 0xff,
      (body.length >> 16) & 0xff,
      (body.length >> 8) & 0xff,
      body.length & 0xff,
    ])
    ..add(body);
  return out.takeBytes();
}

/// Decodifica el cuerpo de un CastMessage (sin la longitud).
({String source, String destination, String namespace, String payload})
decodeCastMessage(Uint8List data) {
  var i = 0;
  int varint() {
    var shift = 0;
    var result = 0;
    while (true) {
      final byte = data[i++];
      result |= (byte & 0x7f) << shift;
      if (byte < 0x80) return result;
      shift += 7;
    }
  }

  final fields = <int, String>{};
  while (i < data.length) {
    final tag = varint();
    final field = tag >> 3;
    switch (tag & 7) {
      case 0:
        varint();
      case 2:
        final len = varint();
        if (field >= 2 && field <= 6) {
          fields[field] = utf8.decode(
            data.sublist(i, i + len),
            allowMalformed: true,
          );
        }
        i += len;
      case 5:
        i += 4;
      case 1:
        i += 8;
      default:
        i = data.length;
    }
  }
  return (
    source: fields[2] ?? '',
    destination: fields[3] ?? '',
    namespace: fields[4] ?? '',
    payload: fields[6] ?? '',
  );
}

class ChromecastDevice extends CastDevice {
  ChromecastDevice(super.name, super.host, this.port);
  final int port;

  static const _nsConn = 'urn:x-cast:com.google.cast.tp.connection';
  static const _nsHeart = 'urn:x-cast:com.google.cast.tp.heartbeat';
  static const _nsRecv = 'urn:x-cast:com.google.cast.receiver';
  static const _nsMedia = 'urn:x-cast:com.google.cast.media';
  static const _appId = 'CC1AD845'; // Receptor multimedia de Google.

  SecureSocket? _socket;
  Timer? _ping;
  int _req = 1;
  String? _transport;
  String? _session;
  final _buffer = BytesBuilder();
  final _waiters = <bool Function(String ns, Map<String, dynamic> j)>[];

  @override
  CastKind get kind => CastKind.chromecast;

  @override
  String get id => 'cast:$host:$port';

  void _send(String dest, String ns, Map<String, dynamic> payload) {
    _socket?.add(encodeCastMessage('sender-0', dest, ns, jsonEncode(payload)));
  }

  void _onData(Uint8List chunk) {
    _buffer.add(chunk);
    var all = _buffer.takeBytes();
    while (all.length >= 4) {
      final len = (all[0] << 24) | (all[1] << 16) | (all[2] << 8) | all[3];
      if (all.length < 4 + len) break;
      final msg = decodeCastMessage(Uint8List.sublistView(all, 4, 4 + len));
      all = Uint8List.sublistView(all, 4 + len);
      Map<String, dynamic> j;
      try {
        j = jsonDecode(msg.payload) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      if (msg.namespace == _nsHeart && j['type'] == 'PING') {
        _send(msg.source, _nsHeart, {'type': 'PONG'});
        continue;
      }
      if (j['type'] == 'CLOSE' && msg.source == _transport) {
        _transport = null;
      }
      _waiters.removeWhere((w) => w(msg.namespace, j));
    }
    _buffer.add(all);
  }

  Future<Map<String, dynamic>> _wait(
    bool Function(String ns, Map<String, dynamic> j) test,
  ) {
    final c = Completer<Map<String, dynamic>>();
    _waiters.add((ns, j) {
      if (!test(ns, j)) return false;
      if (!c.isCompleted) c.complete(j);
      return true;
    });
    return c.future.timeout(const Duration(seconds: 15));
  }

  Future<void> _connect() async {
    if (_socket != null) return;
    final s = await SecureSocket.connect(
      host,
      port,
      onBadCertificate: (_) => true,
      timeout: const Duration(seconds: 6),
    );
    _socket = s;
    s.listen(
      _onData,
      onDone: _reset,
      onError: (_) => _reset(),
      cancelOnError: true,
    );
    _send('receiver-0', _nsConn, {'type': 'CONNECT'});
    _ping = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _send('receiver-0', _nsHeart, {'type': 'PING'}),
    );
  }

  void _reset() {
    _ping?.cancel();
    _ping = null;
    _socket?.destroy();
    _socket = null;
    _transport = null;
  }

  Future<void> _ensureApp() async {
    if (_transport != null) return;
    final id = _req++;
    final status = _wait(
      (ns, j) =>
          ns == _nsRecv &&
          j['type'] == 'RECEIVER_STATUS' &&
          ((j['status']?['applications'] as List?) ?? const []).any(
            (a) => a['appId'] == _appId && a['transportId'] != null,
          ),
    );
    _send('receiver-0', _nsRecv, {
      'type': 'LAUNCH',
      'appId': _appId,
      'requestId': id,
    });
    final j = await status;
    final a = (j['status']['applications'] as List).firstWhere(
      (a) => a['appId'] == _appId,
    );
    _transport = a['transportId'] as String;
    _session = a['sessionId'] as String?;
    _send(_transport!, _nsConn, {'type': 'CONNECT'});
  }

  @override
  Future<void> play(
    String url, {
    required String title,
    required String mime,
  }) async {
    await _connect();
    await _ensureApp();
    final id = _req++;
    final answer = _wait(
      (ns, j) =>
          ns == _nsMedia &&
          (j['requestId'] == id ||
              j['type'] == 'LOAD_FAILED' ||
              j['type'] == 'LOAD_CANCELLED'),
    );
    _send(_transport!, _nsMedia, {
      'type': 'LOAD',
      'requestId': id,
      'autoplay': true,
      'media': {
        'contentId': url,
        'contentUrl': url,
        'streamType': mime.contains('mpegURL') ? 'LIVE' : 'BUFFERED',
        'contentType': mime,
        'metadata': {'metadataType': 0, 'title': title},
      },
    });
    final j = await answer;
    if (j['type'] == 'LOAD_FAILED' || j['type'] == 'LOAD_CANCELLED') {
      throw const HttpException('El Chromecast no ha podido abrir el canal');
    }
  }

  @override
  Future<void> stop() async {
    if (_socket == null) return;
    if (_session != null) {
      _send('receiver-0', _nsRecv, {
        'type': 'STOP',
        'sessionId': _session,
        'requestId': _req++,
      });
    }
    await Future.delayed(const Duration(milliseconds: 300));
    close();
  }

  @override
  void close() => _reset();
}

// ------------------------------------------------------------- mDNS mínimo

/// Pregunta mDNS (respuesta unicast, RFC 6762 §6.7) por un servicio.
Uint8List buildMdnsQuery(String name) {
  final b = BytesBuilder()..add([0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
  for (final part in name.split('.')) {
    if (part.isEmpty) continue;
    final bytes = utf8.encode(part);
    b.addByte(bytes.length);
    b.add(bytes);
  }
  b.add([0, 0, 12, 0, 1]); // fin, tipo PTR, clase IN
  return b.takeBytes();
}

/// Extrae los Chromecast (nombre, ip, puerto) de una respuesta mDNS.
List<(String, String, int)> parseMdnsCast(Uint8List data, String fallbackIp) {
  final bd = ByteData.sublistView(data);
  var i = 12;
  String readName(int pos, [int depth = 0]) {
    final parts = <String>[];
    var p = pos;
    while (p < data.length && depth < 10) {
      final len = data[p];
      if (len == 0) break;
      if (len & 0xc0 == 0xc0) {
        final ptr = ((len & 0x3f) << 8) | data[p + 1];
        parts.add(readName(ptr, depth + 1));
        return parts.where((s) => s.isNotEmpty).join('.');
      }
      parts.add(
        utf8.decode(data.sublist(p + 1, p + 1 + len), allowMalformed: true),
      );
      p += len + 1;
    }
    return parts.join('.');
  }

  int skipName(int pos) {
    var p = pos;
    while (p < data.length) {
      final len = data[p];
      if (len == 0) return p + 1;
      if (len & 0xc0 == 0xc0) return p + 2;
      p += len + 1;
    }
    return p;
  }

  if (data.length < 12) return const [];
  final qd = bd.getUint16(4);
  final total = bd.getUint16(6) + bd.getUint16(8) + bd.getUint16(10);
  for (var q = 0; q < qd; q++) {
    i = skipName(i) + 4;
  }
  final srv = <String, (String, int)>{}; // instancia -> (host, puerto)
  final txt = <String, String>{}; // instancia -> nombre
  final a = <String, String>{}; // host -> ip
  final instances = <String>[];
  for (var r = 0; r < total && i + 10 <= data.length; r++) {
    final name = readName(i);
    i = skipName(i);
    final type = bd.getUint16(i);
    final rdlen = bd.getUint16(i + 8);
    final rd = i + 10;
    if (rd + rdlen > data.length) break;
    switch (type) {
      case 12:
        instances.add(readName(rd));
      case 33:
        srv[name] = (readName(rd + 6), bd.getUint16(rd + 4));
      case 16:
        var p = rd;
        while (p < rd + rdlen) {
          final l = data[p];
          final s = utf8.decode(
            data.sublist(p + 1, p + 1 + l),
            allowMalformed: true,
          );
          if (s.startsWith('fn=')) txt[name] = s.substring(3);
          p += l + 1;
        }
      case 1:
        if (rdlen == 4) a[name] = data.sublist(rd, rd + 4).join('.');
    }
    i = rd + rdlen;
  }
  final out = <(String, String, int)>[];
  for (final inst in {...instances, ...srv.keys}) {
    final s = srv[inst];
    final ip = s == null ? fallbackIp : (a[s.$1] ?? fallbackIp);
    final label = txt[inst] ?? inst.split('._googlecast').first;
    out.add((label, ip, s?.$2 ?? 8009));
  }
  return out;
}

Stream<CastDevice> _discoverCast(Duration timeout) async* {
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  final controller = StreamController<CastDevice>();
  final seen = <String>{};
  final q = buildMdnsQuery('_googlecast._tcp.local');
  void send() {
    try {
      socket.send(q, InternetAddress('224.0.0.251'), 5353);
    } catch (e) {
      debugPrint('mDNS: $e');
    }
  }

  socket.listen((ev) {
    if (ev != RawSocketEvent.read) return;
    final d = socket.receive();
    if (d == null) return;
    try {
      for (final (name, ip, port) in parseMdnsCast(d.data, d.address.address)) {
        if (seen.add('$ip:$port') && !controller.isClosed) {
          controller.add(ChromecastDevice(name, ip, port));
        }
      }
    } catch (e) {
      debugPrint('mDNS respuesta: $e');
    }
  });
  send();
  Timer(const Duration(milliseconds: 900), send);
  Timer(timeout, () {
    socket.close();
    controller.close();
  });
  yield* controller.stream;
}

/// Busca teles en la red de casa durante unos segundos.
Stream<CastDevice> discoverCastDevices({
  Duration timeout = const Duration(seconds: 5),
}) {
  final out = StreamController<CastDevice>();
  var open = 2;
  void done() {
    if (--open == 0) out.close();
  }

  for (final s in [_discoverDlna(timeout), _discoverCast(timeout)]) {
    s.listen(
      out.add,
      onError: (e) => debugPrint('Búsqueda de teles: $e'),
      onDone: done,
      cancelOnError: true,
    );
  }
  return out.stream;
}

// ============================================================ Relé de señal

/// Reescribe una lista HLS para que cada enlace pase por el relé.
String rewriteHls(String body, Uri base, String Function(Uri) wrap) {
  final uriAttr = RegExp(r'URI="([^"]+)"');
  return const LineSplitter()
      .convert(body)
      .map((line) {
        final t = line.trim();
        if (t.isEmpty) return line;
        if (t.startsWith('#')) {
          return line.replaceAllMapped(
            uriAttr,
            (m) => 'URI="${wrap(base.resolve(m.group(1)!))}"',
          );
        }
        return wrap(base.resolve(t));
      })
      .join('\n');
}

/// Pequeño servidor que reenvía el canal a la tele desde este dispositivo.
class StreamRelay {
  StreamRelay._();
  static final StreamRelay instance = StreamRelay._();

  HttpServer? _server;
  String _userAgent = '';
  String _referrer = '';
  String _host = '';

  Future<String> _localIpFor(String target, int port) async {
    try {
      final s = await Socket.connect(
        target,
        port,
        timeout: const Duration(seconds: 2),
      );
      final ip = s.address.address;
      s.destroy();
      return ip;
    } catch (_) {}
    for (final iface in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    )) {
      for (final a in iface.addresses) {
        final ip = a.address;
        if (ip.startsWith('192.168.') ||
            ip.startsWith('10.') ||
            RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip)) {
          return ip;
        }
      }
    }
    return InternetAddress.loopbackIPv4.address;
  }

  /// Devuelve el enlace que debe abrir la tele [device] para el canal [c].
  Future<String> urlFor(Channel c, CastDevice device, String defaultUa) async {
    _userAgent = c.userAgent.isNotEmpty ? c.userAgent : defaultUa;
    _referrer = c.referrer;
    _server ??= await HttpServer.bind(InternetAddress.anyIPv4, 0)
      ..listen(_handle);
    final port = device is DlnaDevice
        ? device.controlUrl.port
        : device is ChromecastDevice
        ? device.port
        : 80;
    _host = '${await _localIpFor(device.host, port)}:${_server!.port}';
    return _wrap(Uri.parse(c.url));
  }

  String _wrap(Uri u) {
    final enc = base64Url.encode(utf8.encode(u.toString())).replaceAll('=', '');
    final path = u.path.toLowerCase();
    final ext = path.endsWith('.m3u8')
        ? '.m3u8'
        : path.endsWith('.ts')
        ? '.ts'
        : '';
    return 'http://$_host/r/$enc$ext';
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers.set('Access-Control-Allow-Origin', '*');
    res.headers.set('Access-Control-Allow-Headers', '*');
    if (req.method == 'OPTIONS') {
      await res.close();
      return;
    }
    final seg = req.uri.pathSegments;
    if (seg.length != 2 || seg[0] != 'r') {
      res.statusCode = 404;
      await res.close();
      return;
    }
    final client = _httpClient()..autoUncompress = true;
    try {
      var enc = seg[1].split('.').first;
      enc += '=' * ((4 - enc.length % 4) % 4);
      final target = Uri.parse(utf8.decode(base64Url.decode(enc)));
      final up = await client.getUrl(target);
      up.headers.set('User-Agent', _userAgent);
      if (_referrer.isNotEmpty) up.headers.set('Referer', _referrer);
      final range = req.headers.value('range');
      if (range != null) up.headers.set('Range', range);
      final upRes = await up.close();
      final type = upRes.headers.contentType?.mimeType ?? '';
      final isHls =
          type.contains('mpegurl') ||
          target.path.toLowerCase().endsWith('.m3u8');
      res.statusCode = upRes.statusCode;
      final finalUri = upRes.redirects.isEmpty
          ? target
          : target.resolveUri(upRes.redirects.last.location);
      if (isHls) {
        final body = await upRes.transform(utf8.decoder).join();
        final out = utf8.encode(rewriteHls(body, finalUri, _wrap));
        res.headers.set('Content-Type', 'application/vnd.apple.mpegurl');
        res.contentLength = out.length;
        if (req.method != 'HEAD') res.add(out);
        await res.close();
      } else {
        res.headers.set(
          'Content-Type',
          type.isEmpty || type == 'application/octet-stream'
              ? 'video/mp2t'
              : upRes.headers.contentType.toString(),
        );
        if (upRes.contentLength >= 0) res.contentLength = upRes.contentLength;
        for (final h in ['content-range', 'accept-ranges']) {
          final v = upRes.headers.value(h);
          if (v != null) res.headers.set(h, v);
        }
        if (req.method == 'HEAD') {
          await res.close();
        } else {
          await res.addStream(upRes);
          await res.close();
        }
      }
    } catch (e) {
      debugPrint('Relé: $e');
      try {
        res.statusCode = 502;
        await res.close();
      } catch (_) {}
    } finally {
      client.close();
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
