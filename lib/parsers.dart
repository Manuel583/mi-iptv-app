// Lectura de listas M3U y de respuestas de Xtream Codes.
import 'dart:convert';

import 'content_kind.dart';
import 'country.dart';
import 'models.dart';

class ParsedPlaylist {
  ParsedPlaylist(this.channels, this.epgUrl);
  final List<Channel> channels;
  final String epgUrl;
}

final _attrRe = RegExp(r'([A-Za-z0-9_\-]+)\s*=\s*"([^"]*)"');

/// Crea claves únicas y estables para cada canal.
class _KeyMaker {
  final _seen = <String, int>{};
  String make(String sourceId, String group, String name) {
    final base = '$sourceId|$group|$name';
    final n = (_seen[base] ?? 0) + 1;
    _seen[base] = n;
    return n == 1 ? base : '$base#$n';
  }
}

/// Lee el texto de una lista M3U / M3U8.
ParsedPlaylist parseM3u(String content, String sourceId) {
  final channels = <Channel>[];
  final keys = _KeyMaker();
  var epgUrl = '';

  Map<String, String> attrs = {};
  String? name;
  String extGroup = '';
  String ua = '';
  String ref = '';

  void reset() {
    attrs = {};
    name = null;
    extGroup = '';
    ua = '';
    ref = '';
  }

  for (var raw in const LineSplitter().convert(content)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTM3U')) {
      for (final m in _attrRe.allMatches(line)) {
        final k = m.group(1)!.toLowerCase();
        if (k == 'url-tvg' || k == 'x-tvg-url' || k == 'tvg-url') {
          epgUrl = m.group(2)!.trim();
        }
      }
      continue;
    }
    if (line.startsWith('#EXTINF')) {
      reset();
      // El nombre va tras la primera coma que esté fuera de comillas.
      var inQuotes = false;
      var comma = -1;
      for (var i = 0; i < line.length; i++) {
        final ch = line[i];
        if (ch == '"') inQuotes = !inQuotes;
        if (ch == ',' && !inQuotes) {
          comma = i;
          break;
        }
      }
      final head = comma >= 0 ? line.substring(0, comma) : line;
      name = comma >= 0 ? line.substring(comma + 1).trim() : '';
      for (final m in _attrRe.allMatches(head)) {
        attrs[m.group(1)!.toLowerCase()] = m.group(2)!.trim();
      }
      continue;
    }
    if (line.startsWith('#EXTGRP:')) {
      extGroup = line.substring(8).trim();
      continue;
    }
    if (line.startsWith('#EXTVLCOPT:')) {
      final opt = line.substring(11);
      if (opt.startsWith('http-user-agent=')) {
        ua = opt.substring(16).trim();
      } else if (opt.startsWith('http-referrer=')) {
        ref = opt.substring(14).trim();
      }
      continue;
    }
    if (line.startsWith('#')) continue;

    // Es una URL.
    final url = line;
    var chName = (name ?? '').trim();
    if (chName.isEmpty) chName = attrs['tvg-name'] ?? '';
    if (chName.isEmpty) chName = url;
    final group = (attrs['group-title'] ?? '').isNotEmpty
        ? attrs['group-title']!
        : extGroup;
    final tvgId = attrs['tvg-id'] ?? '';
    final cls = classifyEntry(url: url, group: group, name: chName);
    channels.add(
      Channel(
        key: keys.make(sourceId, group, chName),
        kind: cls.kind,
        seriesName: cls.seriesName,
        season: cls.season,
        episode: cls.episode,
        sourceId: sourceId,
        name: chName,
        url: url,
        logo: attrs['tvg-logo'] ?? attrs['logo'] ?? '',
        group: group,
        tvgId: tvgId,
        tvgName: attrs['tvg-name'] ?? '',
        country: detectCountry(
          tvgCountry: attrs['tvg-country'] ?? '',
          tvgId: tvgId,
          group: group,
          name: chName,
        ),
        userAgent: ua.isNotEmpty ? ua : (attrs['http-user-agent'] ?? ''),
        referrer: ref.isNotEmpty ? ref : (attrs['http-referrer'] ?? ''),
      ),
    );
    reset();
  }
  return ParsedPlaylist(channels, epgUrl);
}

/// Normaliza la dirección de un servidor Xtream.
String normalizeServer(String server) {
  var s = server.trim();
  if (s.isEmpty) return s;
  if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'http://$s';
  final uri = Uri.tryParse(s);
  if (uri != null && uri.host.isNotEmpty) {
    s = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  }
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// Si el usuario pega un enlace tipo get.php?username=..&password=..,
/// devuelve (servidor, usuario, contraseña).
(String, String, String)? extractXtreamFromUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return null;
  final u = uri.queryParameters['username'];
  final p = uri.queryParameters['password'];
  if (u == null || p == null) return null;
  return (normalizeServer(url), u, p);
}

/// Convierte las respuestas JSON de Xtream (categorías y emisiones) en canales.
List<Channel> parseXtream({
  required String categoriesJson,
  required String streamsJson,
  required String sourceId,
  required String server,
  required String username,
  required String password,
  required String output,
}) {
  final cats = <String, String>{};
  final decodedCats = jsonDecode(categoriesJson);
  if (decodedCats is List) {
    for (final c in decodedCats) {
      if (c is Map) {
        cats['${c['category_id']}'] = '${c['category_name'] ?? ''}';
      }
    }
  }
  final decoded = jsonDecode(streamsJson);
  if (decoded is! List) {
    throw const FormatException(
      'El servidor no ha devuelto la lista de canales. Revisa usuario y contraseña.',
    );
  }
  final keys = _KeyMaker();
  final out = <Channel>[];
  final ext = output == 'm3u8' ? 'm3u8' : 'ts';
  final u = Uri.encodeComponent(username);
  final p = Uri.encodeComponent(password);
  for (final s in decoded) {
    if (s is! Map) continue;
    final id = s['stream_id'];
    if (id == null) continue;
    final name = '${s['name'] ?? ''}'.trim();
    final group = cats['${s['category_id']}'] ?? '';
    final tvgId = '${s['epg_channel_id'] ?? ''}'.trim();
    out.add(
      Channel(
        key: keys.make(sourceId, group, name),
        sourceId: sourceId,
        name: name.isEmpty ? 'Canal $id' : name,
        url: '$server/live/$u/$p/$id.$ext',
        logo: '${s['stream_icon'] ?? ''}',
        group: group,
        tvgId: tvgId == 'null' ? '' : tvgId,
        country: detectCountry(tvgId: tvgId, group: group, name: name),
      ),
    );
  }
  return out;
}

Map<String, String> _xtreamCategories(String json) {
  final cats = <String, String>{};
  try {
    final decoded = jsonDecode(json);
    if (decoded is List) {
      for (final c in decoded) {
        if (c is Map) {
          cats['${c['category_id']}'] = '${c['category_name'] ?? ''}';
        }
      }
    }
  } catch (_) {}
  return cats;
}

String _str(Object? v) {
  final s = '${v ?? ''}'.trim();
  return s == 'null' ? '' : s;
}

/// Películas de un servidor Xtream (get_vod_categories y get_vod_streams).
List<Channel> parseXtreamVod({
  required String categoriesJson,
  required String streamsJson,
  required String sourceId,
  required String server,
  required String username,
  required String password,
}) {
  final cats = _xtreamCategories(categoriesJson);
  final Object? decoded;
  try {
    decoded = jsonDecode(streamsJson);
  } catch (_) {
    return const [];
  }
  if (decoded is! List) return const [];
  final keys = _KeyMaker();
  final out = <Channel>[];
  final u = Uri.encodeComponent(username);
  final p = Uri.encodeComponent(password);
  for (final s in decoded) {
    if (s is! Map) continue;
    final id = s['stream_id'];
    if (id == null) continue;
    final name = _str(s['name']);
    final group = cats['${s['category_id']}'] ?? '';
    var ext = _str(s['container_extension']);
    if (ext.isEmpty) ext = 'mp4';
    out.add(
      Channel(
        key: keys.make('$sourceId|vod', group, name),
        sourceId: sourceId,
        name: name.isEmpty ? 'Película $id' : name,
        url: '$server/movie/$u/$p/$id.$ext',
        logo: _str(s['stream_icon']),
        group: group,
        kind: ContentKind.movie,
      ),
    );
  }
  return out;
}

/// Series de un servidor Xtream (get_series_categories y get_series). Los
/// capítulos se piden al abrir cada serie, con [parseXtreamSeriesInfo].
List<Channel> parseXtreamSeries({
  required String categoriesJson,
  required String seriesJson,
  required String sourceId,
}) {
  final cats = _xtreamCategories(categoriesJson);
  final Object? decoded;
  try {
    decoded = jsonDecode(seriesJson);
  } catch (_) {
    return const [];
  }
  if (decoded is! List) return const [];
  final keys = _KeyMaker();
  final out = <Channel>[];
  for (final s in decoded) {
    if (s is! Map) continue;
    final id = _str(s['series_id']);
    if (id.isEmpty) continue;
    final name = _str(s['name']);
    final group = cats['${s['category_id']}'] ?? '';
    out.add(
      Channel(
        key: keys.make('$sourceId|serie', group, name),
        sourceId: sourceId,
        name: name.isEmpty ? 'Serie $id' : name,
        url: '',
        logo: _str(s['cover']),
        group: group,
        kind: ContentKind.series,
        seriesName: name.isEmpty ? 'Serie $id' : name,
        seriesId: id,
      ),
    );
  }
  return out;
}

/// Capítulos de una serie de Xtream (get_series_info).
List<Channel> parseXtreamSeriesInfo({
  required String json,
  required Channel series,
  required String server,
  required String username,
  required String password,
}) {
  final decoded = jsonDecode(json);
  if (decoded is! Map) return const [];
  final eps = decoded['episodes'];
  final out = <Channel>[];
  final u = Uri.encodeComponent(username);
  final p = Uri.encodeComponent(password);
  void add(Object? seasonKey, Object? e) {
    if (e is! Map) return;
    final id = _str(e['id']);
    if (id.isEmpty) return;
    final season =
        int.tryParse(_str(e['season'])) ?? int.tryParse('$seasonKey') ?? 0;
    final epNum = int.tryParse(_str(e['episode_num'])) ?? 0;
    var ext = _str(e['container_extension']);
    if (ext.isEmpty) ext = 'mp4';
    var title = _str(e['title']);
    if (title.isEmpty) title = 'Capítulo $epNum';
    final info = e['info'];
    final logo = info is Map ? _str(info['movie_image']) : '';
    out.add(
      Channel(
        key: '${series.key}|$season|$epNum|$id',
        sourceId: series.sourceId,
        name: title,
        url: '$server/series/$u/$p/$id.$ext',
        logo: logo.isEmpty ? series.logo : logo,
        group: series.group,
        kind: ContentKind.series,
        seriesName: series.seriesName,
        season: season,
        episode: epNum,
      ),
    );
  }

  if (eps is Map) {
    eps.forEach((k, v) {
      if (v is List) {
        for (final e in v) {
          add(k, e);
        }
      }
    });
  } else if (eps is List) {
    for (final v in eps) {
      if (v is List) {
        for (final e in v) {
          add(null, e);
        }
      } else {
        add(null, v);
      }
    }
  }
  out.sort((a, b) {
    final c = a.season.compareTo(b.season);
    return c != 0 ? c : a.episode.compareTo(b.episode);
  });
  return out;
}

/// Quita tildes y pasa a minúsculas para comparar y buscar.
String normalizeText(String s) {
  final lower = s.toLowerCase();
  // Camino rápido: sin letras especiales no hay nada que cambiar.
  var plain = true;
  for (var i = 0; i < lower.length; i++) {
    if (lower.codeUnitAt(i) > 127) {
      plain = false;
      break;
    }
  }
  if (plain) return lower;
  final units = List<int>.of(lower.codeUnits);
  for (var i = 0; i < units.length; i++) {
    final r = _accentMap[units[i]];
    if (r != null) units[i] = r;
  }
  return String.fromCharCodes(units);
}

/// Letras con tilde (ya en minúscula) -> letra sin tilde.
final Map<int, int> _accentMap = () {
  const from = 'áàäâãåéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaaeeeeiiiiooooouuuunc';
  return {
    for (var i = 0; i < from.length; i++) from.codeUnitAt(i): to.codeUnitAt(i),
  };
}();
