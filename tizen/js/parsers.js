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
      channels.push({
        k: keys.make(sourceId, group, chName),
        s: sourceId,
        n: chName,
        u: url,
        l: attrs['tvg-logo'] || attrs.logo || '',
        g: group,
        i: attrs['tvg-id'] || '',
        a: ua || attrs['http-user-agent'] || '',
        r: ref || attrs['http-referrer'] || ''
      });
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

  /** Quita tildes y pasa a minúsculas para comparar y buscar. */
  function normalizeText(s) {
    var from = 'áàäâãåéèëêíìïîóòöôõúùüûñçÁÀÄÂÃÅÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇ';
    var to = 'aaaaaaeeeeiiiiooooouuuuncaaaaaaeeeeiiiiooooouuuunc';
    var out = '';
    s = String(s || '');
    for (var i = 0; i < s.length; i++) {
      var ch = s.charAt(i);
      var j = from.indexOf(ch);
      out += j >= 0 ? to.charAt(j) : ch;
    }
    return out.toLowerCase();
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
    normalizeServer: normalizeServer,
    extractXtreamFromUrl: extractXtreamFromUrl,
    normalizeText: normalizeText,
    decodeBase64Utf8: decodeBase64Utf8
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.MiParsers = api;
})(this);
