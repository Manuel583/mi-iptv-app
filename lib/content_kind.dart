// Distingue canales en directo, películas y series, y reconoce los canales
// de fútbol y los de la TDT española para las carpetas automáticas.
//
// Las mismas reglas están traducidas a JavaScript en tizen/js/parsers.js
// para la versión de los televisores Samsung.

import 'parsers.dart' show normalizeText;

enum ContentKind { live, movie, series }

class Classification {
  const Classification(
    this.kind, {
    this.seriesName = '',
    this.season = 0,
    this.episode = 0,
  });
  final ContentKind kind;
  final String seriesName;
  final int season;
  final int episode;
}

final _vodExt = RegExp(
  r'\.(mp4|mkv|avi|mov|wmv|m4v|mpg|mpeg|webm|divx|xvid|3gp|ogv|vob)$',
  caseSensitive: false,
);
// "S01E02", "S01 E02", "s1e2", "S01.E02"
final _sxe = RegExp(r'\bS(\d{1,2})[\s._-]*E(\d{1,3})\b', caseSensitive: false);
// "1x02"
final _nxn = RegExp(r'\b(\d{1,2})x(\d{2,3})\b', caseSensitive: false);
// "Temporada 2 Capítulo 5", "T2 E5", "Temp. 2 Cap. 5"
final _temp = RegExp(
  r'\b(?:temporada|temp\.?|season|t)\s*(\d{1,2})\b[\s.,:_-]*(?:cap[ií]tulo|cap\.?|episodio|ep\.?|episode|e)\s*(\d{1,3})\b',
  caseSensitive: false,
);
final _year = RegExp(
  r'[\(\[]\s*(19[2-9]\d|20[0-4]\d)\s*[\)\]]|[-–|]\s*(19[2-9]\d|20[0-4]\d)\s*$',
);
final _movieGroup = RegExp(
  r'\b(vod|peliculas?|movies?|films?|cine|estrenos)\b',
);
final _seriesGroup = RegExp(r'\b(series?|temporadas?|tv shows?|shows)\b');
final _vodGroup = RegExp(r'\bvod\b');
final _liveGroup = RegExp(r'24\s*/\s*7|\b24h\b|\blive\b|\bdirecto\b');

/// Busca "S01E02" o parecido en el nombre. Devuelve (serie, temporada, capítulo).
(String, int, int)? parseEpisode(String name) {
  for (final re in [_sxe, _temp, _nxn]) {
    final m = re.firstMatch(name);
    if (m == null) continue;
    final season = int.tryParse(m.group(1)!) ?? 0;
    final ep = int.tryParse(m.group(2)!) ?? 0;
    var series = name.substring(0, m.start);
    series = series.replaceAll(RegExp(r'[\s\-–|:.,_(\[]+$'), '').trim();
    if (series.isEmpty) series = name.substring(m.end).trim();
    return (series, season, ep);
  }
  return null;
}

/// Decide si una entrada de una lista M3U es un canal, una película o un
/// capítulo de una serie.
Classification classifyEntry({
  required String url,
  String group = '',
  String name = '',
}) {
  var path = url.toLowerCase();
  final q = path.indexOf('?');
  if (q >= 0) path = path.substring(0, q);
  final g = normalizeText(group);
  final ep = parseEpisode(name);

  Classification series() => ep == null
      ? Classification(ContentKind.series, seriesName: name.trim())
      : Classification(
          ContentKind.series,
          seriesName: ep.$1,
          season: ep.$2,
          episode: ep.$3,
        );

  // 1) La dirección lo dice claramente (listas de servidores Xtream).
  if (path.contains('/series/')) return series();
  if (path.contains('/movie/') || path.contains('/movies/')) {
    return ep != null ? series() : const Classification(ContentKind.movie);
  }
  if (path.contains('/live/')) return const Classification(ContentKind.live);
  // 2) Archivos de vídeo (.mp4, .mkv...): no son emisiones en directo.
  if (_vodExt.hasMatch(path)) {
    return ep != null || _seriesGroup.hasMatch(g)
        ? series()
        : const Classification(ContentKind.movie);
  }
  // 3) Grupos de canales que emiten sin parar ("24/7"): son canales.
  if (_liveGroup.hasMatch(g)) return const Classification(ContentKind.live);
  // 4) "S01E02" en el nombre: capítulo de una serie.
  if (ep != null) return series();
  // 5) Grupo de vídeo bajo demanda o de películas con el año en el nombre.
  //    (Un grupo "Cine" a secas suele tener canales de cine en directo.)
  if (_vodGroup.hasMatch(g)) {
    return _seriesGroup.hasMatch(g)
        ? series()
        : const Classification(ContentKind.movie);
  }
  if (_movieGroup.hasMatch(g) && _year.hasMatch(name)) {
    return const Classification(ContentKind.movie);
  }
  return const Classification(ContentKind.live);
}

// ------------------------------------------------------- Carpetas automáticas

/// Deja el nombre del canal "limpio" para compararlo: sin tildes, sin
/// prefijos de país ("ES:", "|ES|"), sin calidad ("HD", "FHD", "1080p")...
String cleanChannelName(String name) {
  var s = normalizeText(name);
  s = s.replaceAll(RegExp(r'[\[\(\{][^\]\)\}]*[\]\)\}]'), ' ');
  s = s.replaceAll(RegExp(r'^\s*\|?\s*(es|esp|spain|espana)\s*[:|\-]\s*'), ' ');
  s = s.replaceAll(RegExp(r'\|\s*(es|esp)\s*\|'), ' ');
  s = s.replaceAll(
    RegExp(
      r'\b(uhd|fhd|hd|sd|4k|8k|hevc|h\.?265|h\.?264|\d{3,4}p|\d{2}fps|backup|bk|alt|multi(audio)?|vip|plus|opcion \d|op\d|v\d|ott|direct[oa]?|live)\b',
    ),
    ' ',
  );
  s = s.replaceAll(RegExp(r'\b(es|esp|spain)\s*$'), ' ');
  s = s.replaceAll(RegExp(r'[^a-z0-9+]+'), ' ').trim();
  return s;
}

String _squash(String s) => s.replaceAll(' ', '');

/// Canales de la TDT española (nacionales y autonómicos), ya "aplastados"
/// (sin espacios ni símbolos) para compararlos con el nombre limpio.
const tdtNames = <String>{
  // RTVE
  'la1', 'tve1', 'tvela1', 'rtve1', 'la2', 'tve2', 'tvela2', 'rtve2',
  '24h', '24horas', 'canal24h', 'canal24horas', 'tve24h', 'rtve24h',
  'clan', 'clantve', 'teledeporte', 'tdp', 'tvedeporte',
  // Atresmedia
  'antena3', 'a3', 'lasexta', 'sexta', 'la6', 'neox', 'nova', 'mega',
  'atreseries', 'antena3neox', 'antena3nova',
  // Mediaset
  'telecinco', 't5', 'cuatro', 'fdf', 'factoriadeficcion', 'energy',
  'divinity', 'bemad', 'bemadtv', 'boing',
  // Otros nacionales
  'trece', '13tv', 'trecetv', 'dmax', 'dkiss', 'paramountnetwork',
  'paramount', 'ten', 'tentv', 'realmadridtv', 'rmtv', 'gol', 'golplay',
  'goltv', 'disneychannel',
  // Autonómicos
  'tv3', '3cat', 'tv3cat', 'super3', 'sx3', '33', 'c33', 'canal33', 'esport3',
  '324', 'telemadrid', 'laotra', 'canalsur', 'canalsur2',
  'canalsurandalucia', 'andaluciatv', 'apunt', 'apuntmedia', 'tvg', 'tvg2',
  'tvgalicia', 'galiciatv', 'crtvg', 'etb1', 'etb2', 'etb3', 'etb4',
  'etbbasque', 'aragontv', 'cmm', 'cmmtv', 'cmmtelevision',
  'castillalamanchatv', 'televisioncanaria', 'tvcanaria', 'canariastv',
  'ib3', 'ib3tv', 'ib3global', 'tpa', 'tpa7', 'tpa8', 'rtpa', '7rm',
  '7regiondemurcia', 'la7', 'la7tv', 'navarratv', 'canalextremadura',
  'extremaduratv', 'cyltv', 'cyl7', 'cyl8', 'la8', 'la8mediterraneo',
  '8tv', 'beteve', 'populartv', 'trecemadrid',
  '101tv', 'tvcantabria', 'popularcantabria', 'tvr',
  'televisionlarioja', 'teleasturias', 'telebilbao', 'canal4', 'fibwi',
  'cyltvplay',
};

/// Canales que no son de España aunque se llamen igual (p. ej. "Nova" checa).
bool _maybeSpain(String country) =>
    country.isEmpty || country == 'España' || country == 'Sin país';

/// ¿Es un canal de la TDT española?
bool isTdtChannel({
  required String name,
  String country = '',
  String tvgId = '',
}) {
  if (!_maybeSpain(country)) return false;
  final clean = cleanChannelName(name);
  if (clean.isEmpty) return false;
  final squashed = _squash(clean);
  if (tdtNames.contains(squashed)) return true;
  // "La 1 Cataluña", "TVE La 1 HD 50fps"... sólo con la primera palabra
  // (o las dos primeras) para no confundir "Antena 3 Internacional".
  final words = clean.split(' ');
  if (words.length >= 2) {
    final two = _squash(words.take(2).join(' '));
    final three = words.length >= 3 ? _squash(words.take(3).join(' ')) : '';
    const regional = {
      'catalunya',
      'cataluna',
      'madrid',
      'andalucia',
      'canarias',
    };
    if (words.length == 3 &&
        regional.contains(words[2]) &&
        tdtNames.contains(two)) {
      return true;
    }
    if (three.isNotEmpty &&
        regional.contains(words.last) &&
        tdtNames.contains(three)) {
      return true;
    }
  }
  // Identificador de la guía tipo "La1.es", "Antena3.es".
  if (tvgId.toLowerCase().endsWith('.es')) {
    final id = _squash(cleanChannelName(tvgId.substring(0, tvgId.length - 3)));
    if (tdtNames.contains(id)) return true;
  }
  return false;
}

final _footballName = RegExp(
  r'\b(futbol|football|soccer|laliga|la liga|liga de campeones|champions|europa league|conference league|uefa|fifa|premier league|bundesliga|serie a|ligue 1|eredivisie|primeira liga|liga portugal|liga hypermotion|hypermotion|copa del rey|supercopa|real madrid tv|rmtv|barca tv|barca one|athletic club tv|sevilla fc tv|betis tv|gol|gol play|goltv|gol tv|mundial)\b',
);
final _footballSquashed = RegExp(
  r'(laliga|ligadecampeones|ligacampeones|m\+liga|movistarliga|premierleague|bundesliga|realmadridtv|barcatv|goltv|golplay)',
);
final _dazn = RegExp(r'\bdazn\b');
final _notFootball = RegExp(
  r'\b(f1|formula|motogp|moto gp|nba|acb|basket|baloncesto|tenis|tennis|golf|boxeo|boxing|ufc|nfl|ciclismo|motor|wwe|euroliga|euroleague)\b',
);
final _footballGroup = RegExp(r'\b(futbol|football|soccer|laliga|la liga)\b');

/// ¿Es un canal de fútbol?
bool isFootballChannel({required String name, String group = ''}) {
  final clean = cleanChannelName(name);
  if (clean.isEmpty) return false;
  if (_notFootball.hasMatch(clean)) return false;
  if (_footballName.hasMatch(clean)) return true;
  if (_footballSquashed.hasMatch(_squash(clean))) return true;
  // DAZN 1, DAZN 2, DAZN LaLiga... (pero no DAZN F1 ni DAZN Baloncesto).
  if (_dazn.hasMatch(clean)) return true;
  if (_footballGroup.hasMatch(normalizeText(group))) return true;
  return false;
}
