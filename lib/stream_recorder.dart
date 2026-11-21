// Graba una emisión directamente desde Internet a un archivo, sin
// reproducirla. Sirve para enlaces .ts normales y para listas HLS (.m3u8).
// Lo usa la grabación programada de Windows (en Android lo hace el código
// nativo, que sigue igual que este).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

class StreamRecorder {
  StreamRecorder({
    required this.url,
    required this.outPath,
    required this.stopAt,
    this.userAgent = '',
    this.referrer = '',
  });

  final String url;
  final String outPath;
  final DateTime stopAt;
  final String userAgent;
  final String referrer;

  int bytes = 0;
  String lastError = '';
  bool _cancelled = false;
  HttpClient? _client;

  /// Aumenta cada vez que llegan datos (para mostrar el avance).
  final StreamController<int> _progress = StreamController.broadcast();
  Stream<int> get progress => _progress.stream;

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  bool get _done => _cancelled || !DateTime.now().isBefore(stopAt);

  /// Graba hasta [stopAt] o hasta que se cancele. Si se corta la conexión,
  /// vuelve a conectar. Devuelve true si se guardó algo.
  Future<bool> run() async {
    final file = File(outPath);
    await file.parent.create(recursive: true);
    final sink = file.openWrite(mode: FileMode.append);
    try {
      while (!_done) {
        _client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 20)
          ..idleTimeout = const Duration(seconds: 20)
          ..badCertificateCallback = (_, _, _) => true;
        try {
          final resp = await _get(Uri.parse(url));
          final type = resp.headers.contentType?.mimeType ?? '';
          final isHls =
              type.contains('mpegurl') ||
              Uri.parse(url).path.toLowerCase().endsWith('.m3u8');
          if (isHls) {
            var base = Uri.parse(url);
            for (final r in resp.redirects) {
              base = base.resolveUri(r.location);
            }
            await _recordHls(base, await _readText(resp), sink);
          } else {
            await _copy(resp, sink);
          }
        } catch (e) {
          lastError = '$e';
        } finally {
          _client?.close(force: true);
        }
        if (!_done) {
          final left = stopAt.difference(DateTime.now());
          await Future.delayed(
            left < const Duration(seconds: 3)
                ? left
                : const Duration(seconds: 3),
          );
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
      await _progress.close();
    }
    if (bytes == 0) {
      try {
        await file.delete();
      } catch (_) {}
    }
    return bytes > 0;
  }

  Future<HttpClientResponse> _get(Uri uri) async {
    final req = await _client!.getUrl(uri);
    req.headers.set(
      'User-Agent',
      userAgent.isEmpty ? 'VLC/3.0.20 LibVLC/3.0.20' : userAgent,
    );
    if (referrer.isNotEmpty) req.headers.set('Referer', referrer);
    final resp = await req.close().timeout(const Duration(seconds: 30));
    if (resp.statusCode >= 400) {
      await resp.drain<void>();
      throw HttpException('El servidor respondió ${resp.statusCode}');
    }
    return resp;
  }

  Future<String> _readText(HttpClientResponse r) =>
      r.transform(const Utf8Decoder(allowMalformed: true)).join();

  Future<void> _copy(Stream<List<int>> data, IOSink sink) async {
    final done = Completer<void>();
    late StreamSubscription<List<int>> sub;
    Timer? stopper;
    stopper = Timer(stopAt.difference(DateTime.now()), () {
      sub.cancel();
      if (!done.isCompleted) done.complete();
    });
    Timer? idle;
    void resetIdle() {
      idle?.cancel();
      idle = Timer(const Duration(seconds: 20), () {
        lastError = 'La emisión dejó de enviar datos';
        sub.cancel();
        if (!done.isCompleted) done.complete();
      });
    }

    resetIdle();
    sub = data.listen(
      (chunk) {
        if (_cancelled) {
          sub.cancel();
          if (!done.isCompleted) done.complete();
          return;
        }
        sink.add(chunk);
        bytes += chunk.length;
        resetIdle();
        if (!_progress.isClosed) _progress.add(bytes);
      },
      onError: (Object e) {
        lastError = '$e';
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    await done.future;
    stopper.cancel();
    idle?.cancel();
  }

  Future<void> _recordHls(Uri playlist, String text, IOSink sink) async {
    var media = playlist;
    var body = text;
    // Lista maestra: escoger la calidad más alta.
    if (body.contains('#EXT-X-STREAM-INF')) {
      final variant = pickBestVariant(body);
      if (variant == null) throw const FormatException('Lista HLS vacía');
      media = playlist.resolve(variant);
      body = await _readText(await _get(media));
    }
    final seen = <String>{};
    final order = <String>[];
    var initDone = false;
    while (!_done) {
      final pl = parseMediaPlaylist(body);
      if (!initDone && pl.initSegment != null) {
        await _copy(await _get(media.resolve(pl.initSegment!)), sink);
        initDone = true;
      }
      for (final seg in pl.segments) {
        if (_done) break;
        if (seen.contains(seg)) continue;
        seen.add(seg);
        order.add(seg);
        if (order.length > 2000) seen.remove(order.removeAt(0));
        try {
          await _copy(await _get(media.resolve(seg)), sink);
        } catch (e) {
          lastError = '$e';
        }
      }
      if (pl.ended || _done) break;
      await Future.delayed(
        Duration(milliseconds: (pl.targetDuration * 500).clamp(1000, 6000)),
      );
      if (_done) break;
      body = await _readText(await _get(media));
    }
  }
}

/// Escoge la variante con más calidad (BANDWIDTH) de una lista maestra HLS.
String? pickBestVariant(String master) {
  final lines = const LineSplitter().convert(master);
  String? best;
  var bestBw = -1;
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i].trim();
    if (!l.startsWith('#EXT-X-STREAM-INF')) continue;
    final bw =
        int.tryParse(
          RegExp(r'[:,]BANDWIDTH=(\d+)').firstMatch(l)?.group(1) ?? '',
        ) ??
        0;
    for (var j = i + 1; j < lines.length; j++) {
      final u = lines[j].trim();
      if (u.isEmpty || u.startsWith('#')) continue;
      if (bw > bestBw) {
        bestBw = bw;
        best = u;
      }
      break;
    }
  }
  return best;
}

class MediaPlaylist {
  MediaPlaylist(
    this.segments,
    this.targetDuration,
    this.ended,
    this.initSegment,
  );
  final List<String> segments;
  final int targetDuration;
  final bool ended;
  final String? initSegment;
}

MediaPlaylist parseMediaPlaylist(String text) {
  final segs = <String>[];
  var target = 6;
  var ended = false;
  String? init;
  for (final raw in const LineSplitter().convert(text)) {
    final l = raw.trim();
    if (l.isEmpty) continue;
    if (l.startsWith('#EXT-X-TARGETDURATION:')) {
      target = int.tryParse(l.substring(22).trim()) ?? target;
    } else if (l.startsWith('#EXT-X-ENDLIST')) {
      ended = true;
    } else if (l.startsWith('#EXT-X-MAP:')) {
      init = RegExp(r'URI="([^"]+)"').firstMatch(l)?.group(1);
    } else if (!l.startsWith('#')) {
      segs.add(l);
    }
  }
  return MediaPlaylist(segs, target, ended, init);
}
