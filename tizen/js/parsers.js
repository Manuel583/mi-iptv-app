// Lectura de listas M3U y de respuestas de Xtream Codes.
// Es una traducción de lib/parsers.dart: las claves de los canales son las
// mismas que en la app del móvil y del PC, así que los favoritos, nombres y
// canales ocultos de una configuración importada siguen funcionando.
// Escrito en JavaScript sencillo para que funcione también en televisores
// Samsung antiguos (Tizen 3, año 2017).
(function (root) {
  'use strict';

  var ATTR_RE = /([A-Za-z0-9_\-]+)\s*=\s*"([^"]*)"/g;

  function KeyMaker() {
    this.seen = {};
  }
  KeyMaker.prototype.make = function (sourceId, group, name) {
    var base = sourceId + '|' + group + '|' + name;
    var n = (this.seen[base] || 0) + 1;
    this.seen[base] = n;
    return n === 1 ? base : base + '#' + n;
  };

  function readAttrs(text, into) {
    ATTR_RE.lastIndex = 0;
    var m;
    while ((m = ATTR_RE.exec(text)) !== null) {
      into[m[1].toLowerCase()] = m[2].trim();
    }
    return into;
  }

  // ---------------------------------------------- Canales, películas y series
  // Traducción de lib/content_kind.dart: mismas reglas en móvil, PC y tele.

  var VOD_EXT = /\.(mp4|mkv|avi|mov|wmv|m4v|mpg|mpeg|webm|divx|xvid|3gp|ogv|vob)$/i;
  var SXE = /\bS(\d{1,2})[\s._-]*E(\d{1,3})\b/i;
  var NXN = /\b(\d{1,2})x(\d{2,3})\b/i;
  var TEMP = /\b(?:temporada|temp\.?|season|t)\s*(\d{1,2})\b[\s.,:_-]*(?:cap[ií]tulo|cap\.?|episodio|ep\.?|episode|e)\s*(\d{1,3})\b/i;
  var YEAR = /[\(\[]\s*(19[2-9]\d|20[0-4]\d)\s*[\)\]]|[-–|]\s*(19[2-9]\d|20[0-4]\d)\s*$/;
  var MOVIE_GROUP = /\b(vod|peliculas?|movies?|films?|cine|estrenos)\b/;
  var SERIES_GROUP = /\b(series?|temporadas?|tv shows?|shows)\b/;
  var VOD_GROUP = /\bvod\b/;
  var LIVE_GROUP = /24\s*\/\s*7|\b24h\b|\blive\b|\bdirecto\b/;

  /** Busca "S01E02" o parecido. Devuelve {series, season, episode} o null. */
  function parseEpisode(name) {
    var res = [SXE, TEMP, NXN];
    for (var i = 0; i < res.length; i++) {
      var m = res[i].exec(name);
      if (!m) continue;
      var series = name.substring(0, m.index).replace(/[\s\-–|:.,_(\[]+$/, '').trim();
      if (!series) series = name.substring(m.index + m[0].length).trim();
      return { series: series, season: parseInt(m[1], 10) || 0, episode: parseInt(m[2], 10) || 0 };
    }
    return null;
  }

  /** Devuelve {kind: 'live'|'movie'|'series', seriesName, season, episode}. */
  function classifyEntry(url, group, name) {
    var path = String(url || '').toLowerCase();
    var q = path.indexOf('?');
    if (q >= 0) path = path.substring(0, q);
    var g = normalizeText(group || '');
    name = String(name || '');
    var ep = parseEpisode(name);
    function series() {
      return ep
        ? { kind: 'series', seriesName: ep.series, season: ep.season, episode: ep.episode }
        : { kind: 'series', seriesName: name.trim(), season: 0, episode: 0 };
    }
    var live = { kind: 'live' };
    var movie = { kind: 'movie' };
    if (path.indexOf('/series/') >= 0) return series();
    if (path.indexOf('/movie/') >= 0 || path.indexOf('/movies/') >= 0) return ep ? series() : movie;
    if (path.indexOf('/live/') >= 0) return live;
    if (VOD_EXT.test(path)) return ep || SERIES_GROUP.test(g) ? series() : movie;
    if (LIVE_GROUP.test(g)) return live;
    if (ep) return series();
    if (VOD_GROUP.test(g)) return SERIES_GROUP.test(g) ? series() : movie;
    if (MOVIE_GROUP.test(g) && YEAR.test(name)) return movie;
    return live;
  }

  /** Pone en el canal los campos de película o serie (como en Dart). */
  function applyKind(ch, cls) {
    if (cls.kind === 'movie') ch.v = 'm';
    if (cls.kind === 'series') {
      ch.v = 's';
      if (cls.seriesName) ch.sn = cls.seriesName;
      if (cls.season) ch.se = cls.season;
      if (cls.episode) ch.ep = cls.episode;
    }
    return ch;
  }

  // ---------------------------------------------- Carpetas automáticas

  function cleanChannelName(name) {
    var s = normalizeText(name);
    s = s.replace(/[\[\(\{][^\]\)\}]*[\]\)\}]/g, ' ');
    s = s.replace(/^\s*\|?\s*(es|esp|spain|espana)\s*[:|\-]\s*/, ' ');
    s = s.replace(/\|\s*(es|esp)\s*\|/g, ' ');
    s = s.replace(/\b(uhd|fhd|hd|sd|4k|8k|hevc|h\.?265|h\.?264|\d{3,4}p|\d{2}fps|backup|bk|alt|multi(audio)?|vip|plus|opcion \d|op\d|v\d|ott|direct[oa]?|live)\b/g, ' ');
    s = s.replace(/\b(es|esp|spain)\s*$/, ' ');
    return s.replace(/[^a-z0-9+]+/g, ' ').trim();
  }

  function squash(s) { return s.replace(/ /g, ''); }

  var TDT_NAMES = {};
  (
    'la1 tve1 tvela1 rtve1 la2 tve2 tvela2 rtve2 24h 24horas canal24h canal24horas tve24h rtve24h ' +
    'clan clantve teledeporte tdp tvedeporte antena3 a3 lasexta sexta la6 neox nova mega atreseries ' +
    'antena3neox antena3nova telecinco t5 cuatro fdf factoriadeficcion energy divinity bemad bemadtv boing ' +
    'trece 13tv trecetv dmax dkiss paramountnetwork paramount ten tentv realmadridtv rmtv gol golplay goltv ' +
    'disneychannel tv3 3cat tv3cat super3 sx3 33 c33 canal33 esport3 324 telemadrid laotra canalsur canalsur2 ' +
    'canalsurandalucia andaluciatv apunt apuntmedia tvg tvg2 tvgalicia galiciatv crtvg etb1 etb2 etb3 etb4 ' +
    'etbbasque aragontv cmm cmmtv cmmtelevision castillalamanchatv televisioncanaria tvcanaria canariastv ' +
    'ib3 ib3tv ib3global tpa tpa7 tpa8 rtpa 7rm 7regiondemurcia la7 la7tv navarratv canalextremadura ' +
    'extremaduratv cyltv cyl7 cyl8 la8 la8mediterraneo 8tv beteve populartv trecemadrid 101tv tvcantabria ' +
    'popularcantabria tvr televisionlarioja teleasturias telebilbao canal4 fibwi cyltvplay'
  ).split(' ').forEach(function (n) { TDT_NAMES[n] = true; });

  function isTdtChannel(name, country, tvgId) {
    if (country && country !== 'España' && country !== 'Sin país') return false;
    var clean = cleanChannelName(name);
    if (!clean) return false;
    if (TDT_NAMES[squash(clean)]) return true;
    var words = clean.split(' ');
    var regional = { catalunya: 1, cataluna: 1, madrid: 1, andalucia: 1, canarias: 1 };
    if (words.length >= 2) {
      var two = squash(words.slice(0, 2).join(' '));
      var three = words.length >= 3 ? squash(words.slice(0, 3).join(' ')) : '';
      if (words.length === 3 && regional[words[2]] && TDT_NAMES[two]) return true;
      if (three && regional[words[words.length - 1]] && TDT_NAMES[three]) return true;
    }
    var id = String(tvgId || '').toLowerCase();
    if (id.length > 3 && id.substring(id.length - 3) === '.es') {
      if (TDT_NAMES[squash(cleanChannelName(id.substring(0, id.length - 3)))]) return true;
    }
    return false;
  }

  var FOOTBALL_NAME = /\b(futbol|football|soccer|laliga|la liga|liga de campeones|champions|europa league|conference league|uefa|fifa|premier league|bundesliga|serie a|ligue 1|eredivisie|primeira liga|liga portugal|liga hypermotion|hypermotion|copa del rey|supercopa|real madrid tv|rmtv|barca tv|barca one|athletic club tv|sevilla fc tv|betis tv|gol|gol play|goltv|gol tv|mundial)\b/;
  var FOOTBALL_SQUASHED = /(laliga|ligadecampeones|ligacampeones|m\+liga|movistarliga|premierleague|bundesliga|realmadridtv|barcatv|goltv|golplay)/;
  var DAZN = /\bdazn\b/;
  var NOT_FOOTBALL = /\b(f1|formula|motogp|moto gp|nba|acb|basket|baloncesto|tenis|tennis|golf|boxeo|boxing|ufc|nfl|ciclismo|motor|wwe|euroliga|euroleague)\b/;
  var FOOTBALL_GROUP = /\b(futbol|football|soccer|laliga|la liga)\b/;

  function isFootballChannel(name, group) {
    var clean = cleanChannelName(name);
    if (!clean) return false;
    if (NOT_FOOTBALL.test(clean)) return false;
    if (FOOTBALL_NAME.test(clean)) return true;
    if (FOOTBALL_SQUASHED.test(squash(clean))) return true;
    if (DAZN.test(clean)) return true;
    return FOOTBALL_GROUP.test(normalizeText(group || ''));
  }

  /** Lee el texto de una lista M3U / M3U8. Devuelve {channels, epgUrl}. */
  function parseM3u(content, sourceId) {
    var channels = [];
    var keys = new KeyMaker();
    var epgUrl = '';
    var attrs = {};
    var name = null;
    var extGroup = '';
    var ua = '';
    var ref = '';

    function reset() {
      attrs = {};
      name = null;
      extGroup = '';
      ua = '';
      ref = '';
    }

    var lines = String(content || '').split(/\r\n|\r|\n/);
    for (var li = 0; li < lines.length; li++) {
      var line = lines[li].trim();
      if (!line) continue;
      if (line.indexOf('#EXTM3U') === 0) {
        var head0 = readAttrs(line, {});
        epgUrl = head0['url-tvg'] || head0['x-tvg-url'] || head0['tvg-url'] || epgUrl;
        continue;
      }
      if (line.indexOf('#EXTINF') === 0) {
        reset();
        // El nombre va tras la primera coma que esté fuera de comillas.
        var inQuotes = false;
        var comma = -1;
        for (var i = 0; i < line.length; i++) {
          var ch = line.charAt(i);
          if (ch === '"') inQuotes = !inQuotes;
          if (ch === ',' && !inQuotes) {
            comma = i;
            break;
          }
        }
        var head = comma >= 0 ? line.substring(0, comma) : line;
        name = comma >= 0 ? line.substring(comma + 1).trim() : '';
        readAttrs(head, attrs);
        continue;
      }
      if (line.indexOf('#EXTGRP:') === 0) {
        extGroup = line.substring(8).trim();
        continue;
      }
      if (line.indexOf('#EXTVLCOPT:') === 0) {
        var opt = line.substring(11);
        if (opt.indexOf('http-user-agent=') === 0) ua = opt.substring(16).trim();
        else if (opt.indexOf('http-referrer=') === 0) ref = opt.substring(14).trim();
        continue;
      }
      if (line.charAt(0) === '#') continue;

      // Es una URL.
      var url = line;
      var chName = (name || '').trim();
      if (!chName) chName = attrs['tvg-name'] || '';
      if (!chName) chName = url;
      var group = attrs['group-title'] ? attrs['group-title'] : extGroup;
      channels.push(applyKind({
        k: keys.make(sourceId, group, chName),
        s: sourceId,
        n: chName,
        u: url,
        l: attrs['tvg-logo'] || attrs.logo || '',
        g: group,
        i: attrs['tvg-id'] || '',
        a: ua || attrs['http-user-agent'] || '',
        r: ref || attrs['http-referrer'] || ''
      }, classifyEntry(url, group, chName)));
      reset();
    }
    return { channels: channels, epgUrl: epgUrl };
  }

  /** Normaliza la dirección de un servidor Xtream (http://host:puerto). */
  function normalizeServer(server) {
    var s = String(server || '').trim();
    if (!s) return s;
    if (s.indexOf('http://') !== 0 && s.indexOf('https://') !== 0) s = 'http://' + s;
    var m = /^(https?):\/\/([^\/?#:]+)(:\d+)?/i.exec(s);
    if (m) s = m[1].toLowerCase() + '://' + m[2] + (m[3] || '');
    while (s.charAt(s.length - 1) === '/') s = s.substring(0, s.length - 1);
    return s;
  }

  function queryParam(url, key) {
    var m = new RegExp('[?&]' + key + '=([^&#]*)').exec(url);
    if (!m) return null;
    try {
      return decodeURIComponent(m[1].replace(/\+/g, ' '));
    } catch (e) {
      return m[1];
    }
  }

  /** Si se pega un enlace tipo get.php?username=..&password=.., devuelve los datos. */
  function extractXtreamFromUrl(url) {
    var u = queryParam(String(url || ''), 'username');
    var p = queryParam(String(url || ''), 'password');
    if (u === null || p === null) return null;
    return { server: normalizeServer(url), username: u, password: p };
  }

  /** Convierte las respuestas JSON de Xtream (categorías y emisiones) en canales. */
  function parseXtream(opts) {
    var cats = {};
    var decodedCats = typeof opts.categories === 'string' ? JSON.parse(opts.categories) : opts.categories;
    if (decodedCats && decodedCats.length) {
      for (var c = 0; c < decodedCats.length; c++) {
        var cat = decodedCats[c];
        if (cat) cats[String(cat.category_id)] = String(cat.category_name == null ? '' : cat.category_name);
      }
    }
    var streams = typeof opts.streams === 'string' ? JSON.parse(opts.streams) : opts.streams;
    if (!streams || typeof streams.length !== 'number') {
      throw new Error('El servidor no ha devuelto la lista de canales. Revisa usuario y contraseña.');
    }
    var keys = new KeyMaker();
    var out = [];
    var ext = opts.output === 'm3u8' ? 'm3u8' : 'ts';
    var u = encodeURIComponent(opts.username);
    var p = encodeURIComponent(opts.password);
    for (var i = 0; i < streams.length; i++) {
      var s = streams[i];
      if (!s || s.stream_id == null) continue;
      var id = s.stream_id;
      var name = String(s.name == null ? '' : s.name).trim();
      var group = cats[String(s.category_id)] || '';
      var tvgId = String(s.epg_channel_id == null ? '' : s.epg_channel_id).trim();
      out.push({
        k: keys.make(opts.sourceId, group, name),
        s: opts.sourceId,
        n: name || 'Canal ' + id,
        u: opts.server + '/live/' + u + '/' + p + '/' + id + '.' + ext,
        l: String(s.stream_icon == null ? '' : s.stream_icon),
        g: group,
        i: tvgId === 'null' ? '' : tvgId,
        x: String(id)
      });
    }
    return out;
  }

  function str(v) {
    var s = String(v == null ? '' : v).trim();
    return s === 'null' ? '' : s;
  }

  function xtreamCats(json) {
    var cats = {};
    var list = json;
    if (typeof json === 'string') {
      try { list = JSON.parse(json); } catch (e) { list = null; }
    }
    if (list && list.length) {
      for (var c = 0; c < list.length; c++) {
        if (list[c]) cats[String(list[c].category_id)] = str(list[c].category_name);
      }
    }
    return cats;
  }

  function jsonList(v) {
    if (typeof v === 'string') {
      try { v = JSON.parse(v); } catch (e) { return []; }
    }
    return v && typeof v.length === 'number' ? v : [];
  }

  /** Películas de Xtream (get_vod_categories y get_vod_streams). */
  function parseXtreamVod(opts) {
    var cats = xtreamCats(opts.categories);
    var list = jsonList(opts.streams);
    var keys = new KeyMaker();
    var u = encodeURIComponent(opts.username);
    var p = encodeURIComponent(opts.password);
    var out = [];
    for (var i = 0; i < list.length; i++) {
      var s = list[i];
      if (!s || s.stream_id == null) continue;
      var name = str(s.name);
      var group = cats[String(s.category_id)] || '';
      var ext = str(s.container_extension) || 'mp4';
      out.push({
        k: keys.make(opts.sourceId + '|vod', group, name),
        s: opts.sourceId,
        n: name || 'Película ' + s.stream_id,
        u: opts.server + '/movie/' + u + '/' + p + '/' + s.stream_id + '.' + ext,
        l: str(s.stream_icon),
        g: group,
        v: 'm'
      });
    }
    return out;
  }

  /** Series de Xtream (get_series_categories y get_series), sin capítulos. */
  function parseXtreamSeries(opts) {
    var cats = xtreamCats(opts.categories);
    var list = jsonList(opts.series);
    var keys = new KeyMaker();
    var out = [];
    for (var i = 0; i < list.length; i++) {
      var s = list[i];
      if (!s) continue;
      var id = str(s.series_id);
      if (!id) continue;
      var name = str(s.name) || 'Serie ' + id;
      var group = cats[String(s.category_id)] || '';
      out.push({
        k: keys.make(opts.sourceId + '|serie', group, str(s.name)),
        s: opts.sourceId,
        n: name,
        u: '',
        l: str(s.cover),
        g: group,
        v: 's',
        sn: name,
        xs: id
      });
    }
    return out;
  }

  /** Capítulos de una serie de Xtream (get_series_info). */
  function parseXtreamSeriesInfo(json, series, server, username, password) {
    var d = typeof json === 'string' ? JSON.parse(json) : json;
    var out = [];
    if (!d || typeof d !== 'object') return out;
    var u = encodeURIComponent(username);
    var p = encodeURIComponent(password);
    function add(seasonKey, e) {
      if (!e || typeof e !== 'object') return;
      var id = str(e.id);
      if (!id) return;
      var season = parseInt(str(e.season), 10);
      if (isNaN(season)) season = parseInt(seasonKey, 10) || 0;
      var num = parseInt(str(e.episode_num), 10) || 0;
      var ext = str(e.container_extension) || 'mp4';
      var logo = e.info && typeof e.info === 'object' ? str(e.info.movie_image) : '';
      out.push({
        k: series.k + '|' + season + '|' + num + '|' + id,
        s: series.s,
        n: str(e.title) || 'Capítulo ' + num,
        u: server + '/series/' + u + '/' + p + '/' + id + '.' + ext,
        l: logo || series.l || '',
        g: series.g || '',
        v: 's',
        sn: series.sn || series.n,
        se: season,
        ep: num
      });
    }
    var eps = d.episodes;
    if (eps && typeof eps.length === 'number') {
      for (var i = 0; i < eps.length; i++) {
        if (eps[i] && typeof eps[i].length === 'number') {
          for (var j = 0; j < eps[i].length; j++) add(null, eps[i][j]);
        } else add(null, eps[i]);
      }
    } else if (eps && typeof eps === 'object') {
      Object.keys(eps).forEach(function (k) {
        var l = eps[k] || [];
        for (var x = 0; x < l.length; x++) add(k, l[x]);
      });
    }
    out.sort(function (a, b) { return (a.se - b.se) || (a.ep - b.ep); });
    return out;
  }

  /** Quita tildes y pasa a minúsculas para comparar y buscar. */
  var ACCENTS = { 'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a', 'å': 'a', 'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
    'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i', 'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o',
    'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u', 'ñ': 'n', 'ç': 'c' };
  var ACCENT_RE = /[áàäâãåéèëêíìïîóòöôõúùüûñç]/g;
  function normalizeText(s) {
    return String(s || '').toLowerCase().replace(ACCENT_RE, function (ch) { return ACCENTS[ch]; });
  }

  /** Decodifica el texto en base64 que devuelve la guía corta de Xtream. */
  function decodeBase64Utf8(b64) {
    if (!b64) return '';
    try {
      var bin = typeof atob === 'function' ? atob(b64) : Buffer.from(b64, 'base64').toString('binary');
      return decodeURIComponent(escape(bin));
    } catch (e) {
      return String(b64);
    }
  }

  var api = {
    parseM3u: parseM3u,
    parseXtream: parseXtream,
    parseXtreamVod: parseXtreamVod,
    parseXtreamSeries: parseXtreamSeries,
    parseXtreamSeriesInfo: parseXtreamSeriesInfo,
    classifyEntry: classifyEntry,
    parseEpisode: parseEpisode,
    cleanChannelName: cleanChannelName,
    isTdtChannel: isTdtChannel,
    isFootballChannel: isFootballChannel,
    normalizeServer: normalizeServer,
    extractXtreamFromUrl: extractXtreamFromUrl,
    normalizeText: normalizeText,
    decodeBase64Utf8: decodeBase64Utf8
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.MiParsers = api;
})(this);
