// Datos de la aplicación: listas, canales, favoritos y ajustes.
// Usa el mismo formato de configuración que la app del móvil y del PC
// (lib/models.dart), así que se puede importar el archivo exportado allí.
(function (root) {
  'use strict';

  var P = root.MiParsers || (typeof require === 'function' ? require('./parsers.js') : null);

  var CONFIG_KEY = 'mi-iptv-config';
  var CH_PREFIX = 'mi-iptv-ch-';
  var FILE_PREFIX = 'mi-iptv-file-';

  function memoryStorage() {
    var data = {};
    return {
      getItem: function (k) { return Object.prototype.hasOwnProperty.call(data, k) ? data[k] : null; },
      setItem: function (k, v) { data[k] = String(v); },
      removeItem: function (k) { delete data[k]; }
    };
  }

  function emptyCustom() {
    return {
      channelNames: {},
      hiddenChannels: [],
      groupNames: {},
      hiddenGroups: [],
      groupOrder: [],
      channelOrder: {},
      favorites: [],
      folders: []
    };
  }

  function emptySettings() {
    return { userAgent: '', showHidden: false, lastChannelKey: '', autoRefreshHours: 12, lastRefresh: null, audioLanguage: '' };
  }

  function newId() {
    return Date.now().toString(36) + Math.random().toString(36).substring(2, 7);
  }

  /** Descarga un texto. Devuelve una promesa. */
  function httpGetText(url, timeoutMs) {
    return new Promise(function (resolve, reject) {
      var xhr = new XMLHttpRequest();
      xhr.open('GET', url, true);
      xhr.timeout = timeoutMs || 60000;
      xhr.onload = function () {
        if (xhr.status >= 200 && xhr.status < 300) resolve(xhr.responseText);
        else reject(new Error('El servidor respondió con el código ' + xhr.status + '.'));
      };
      xhr.onerror = function () { reject(new Error('No se pudo conectar. Revisa el enlace y la conexión a internet.')); };
      xhr.ontimeout = function () { reject(new Error('El servidor tarda demasiado en responder.')); };
      xhr.send();
    });
  }

  function Store(opts) {
    opts = opts || {};
    this.storage = opts.storage || (function () {
      try {
        if (root.localStorage) return root.localStorage;
      } catch (e) { /* sin almacenamiento */ }
      return memoryStorage();
    })();
    this.getText = opts.getText || httpGetText;
    this.settings = emptySettings();
    this.custom = emptyCustom();
    this.sources = [];
    this.channelsBySource = {};
    this.byKey = {};
    this.groupKeys = [];
    this.groupChannels = {};
  }

  Store.prototype._read = function (k) {
    try {
      var v = this.storage.getItem(k);
      return v == null ? null : JSON.parse(v);
    } catch (e) {
      return null;
    }
  };

  Store.prototype._write = function (k, v) {
    try {
      this.storage.setItem(k, JSON.stringify(v));
      return true;
    } catch (e) {
      // Memoria llena: los canales se volverán a descargar al abrir.
      return false;
    }
  };

  Store.prototype.load = function () {
    var j = this._read(CONFIG_KEY);
    if (j) this._applyConfig(j);
    for (var i = 0; i < this.sources.length; i++) {
      var s = this.sources[i];
      this.channelsBySource[s.id] = this._read(CH_PREFIX + s.id) || [];
    }
    this.rebuild();
  };

  Store.prototype._applyConfig = function (j) {
    var st = emptySettings();
    var js = j.settings || {};
    for (var k in st) if (Object.prototype.hasOwnProperty.call(js, k)) st[k] = js[k];
    this.settings = st;
    var c = emptyCustom();
    var jc = j.custom || {};
    for (var k2 in c) if (jc[k2] != null) c[k2] = jc[k2];
    this.custom = c;
    this.sources = (j.sources || []).map(function (s) {
      return {
        id: String(s.id || newId()),
        name: s.name || 'Lista',
        type: s.type || 'm3uUrl',
        url: s.url || '',
        server: s.server || '',
        username: s.username || '',
        password: s.password || '',
        xtreamOutput: s.xtreamOutput || 'ts',
        enabled: s.enabled !== false,
        lastUpdated: s.lastUpdated || null,
        lastError: s.lastError || null,
        channelCount: s.channelCount || 0
      };
    });
  };

  Store.prototype.configJson = function () {
    return {
      app: 'mi-iptv',
      version: 1,
      settings: this.settings,
      custom: this.custom,
      sources: this.sources
    };
  };

  Store.prototype.save = function () {
    this._write(CONFIG_KEY, this.configJson());
  };

  /** Prepara los grupos y el orden de los canales (como _rebuildIndex en Dart). */
  Store.prototype.rebuild = function () {
    var byKey = {};
    var groups = {};
    var natural = [];
    var movieGroups = {};
    var movieKeys = [];
    var seriesGroups = {};
    var seriesKeys = [];
    var seriesByKey = {};
    var football = [];
    var tdt = [];
    var movieCount = 0;
    var self = this;
    this.xtreamEpisodes = this.xtreamEpisodes || {};
    for (var i = 0; i < this.sources.length; i++) {
      var s = this.sources[i];
      if (!s.enabled) continue;
      var list = this.channelsBySource[s.id] || [];
      for (var j = 0; j < list.length; j++) {
        var ch = list[j];
        if (!ch.xs) byKey[ch.k] = ch;
        var g = ch.g || '';
        if (ch.v === 'm') {
          movieCount++;
          if (!movieGroups[g]) {
            movieGroups[g] = [];
            movieKeys.push(g);
          }
          movieGroups[g].push(ch);
          continue;
        }
        if (ch.v === 's') {
          var sname = ch.sn || ch.n;
          var skey = ch.xs ? ch.k : ch.s + '|serie|' + g + '|' + P.normalizeText(sname);
          var info = seriesByKey[skey];
          if (!info) {
            info = { k: skey, n: sname, l: ch.l || '', g: g, s: ch.s, isSeries: true, xtream: ch.xs ? ch : null, episodes: [] };
            seriesByKey[skey] = info;
            if (!seriesGroups[g]) {
              seriesGroups[g] = [];
              seriesKeys.push(g);
            }
            seriesGroups[g].push(info);
          }
          if (ch.xs) info.episodes = (self.xtreamEpisodes[ch.k] || []).slice();
          else info.episodes.push(ch);
          continue;
        }
        if (P.isFootballChannel(ch.n, g)) football.push(ch);
        if (P.isTdtChannel(ch.n, ch.c || '', ch.i)) tdt.push(ch);
        if (!groups[g]) {
          groups[g] = [];
          natural.push(g);
        }
        groups[g].push(ch);
      }
    }
    var orderSet = {};
    var keys = [];
    var go = this.custom.groupOrder || [];
    for (var a = 0; a < go.length; a++) {
      orderSet[go[a]] = true;
      if (groups[go[a]]) keys.push(go[a]);
    }
    for (var b = 0; b < natural.length; b++) if (!orderSet[natural[b]]) keys.push(natural[b]);

    var co = this.custom.channelOrder || {};
    Object.keys(groups).forEach(function (gk) {
      var order = co[gk];
      if (!order || !order.length) return;
      var pos = {};
      for (var o = 0; o < order.length; o++) pos[order[o]] = o;
      var big = 1 << 30;
      var indexed = groups[gk].map(function (c, idx) { return { c: c, i: idx }; });
      indexed.sort(function (x, y) {
        var px = pos[x.c.k] != null ? pos[x.c.k] : big + x.i;
        var py = pos[y.c.k] != null ? pos[y.c.k] : big + y.i;
        return px - py;
      });
      groups[gk] = indexed.map(function (e) { return e.c; });
    });
    Object.keys(seriesByKey).forEach(function (k) {
      var info = seriesByKey[k];
      if (!info.xtream) info.episodes.sort(function (a, b) { return ((a.se || 0) - (b.se || 0)) || ((a.ep || 0) - (b.ep || 0)); });
      for (var e = 0; e < info.episodes.length; e++) byKey[info.episodes[e].k] = info.episodes[e];
    });
    this.byKey = byKey;
    this.groupKeys = keys;
    this.groupChannels = groups;
    this.movieKeys = movieKeys;
    this.movieGroupsMap = movieGroups;
    this.movieCount = movieCount;
    this.seriesKeys = seriesKeys;
    this.seriesGroupsMap = seriesGroups;
    this.seriesByKey = seriesByKey;
    this.seriesCount = Object.keys(seriesByKey).length;
    this.footballList = football;
    this.tdtList = tdt;
  };

  // ---------------------------------------------------------------- Películas y series

  Store.prototype._groupsOf = function (keys, map, count) {
    var out = [];
    for (var i = 0; i < (keys || []).length; i++) {
      var g = keys[i];
      if (!this.settings.showHidden && this.custom.hiddenGroups.indexOf(g) >= 0) continue;
      var n = count(map[g]);
      if (n > 0) out.push({ key: g, name: this.groupName(g), count: n });
    }
    return out;
  };

  Store.prototype.movieGroups = function () {
    var self = this;
    return this._groupsOf(this.movieKeys, this.movieGroupsMap, function (l) {
      return l.filter(function (c) { return !self._hiddenChannel(c); }).length;
    });
  };

  Store.prototype.moviesInGroup = function (g) {
    var self = this;
    return ((this.movieGroupsMap || {})[g] || []).filter(function (c) { return !self._hiddenChannel(c); });
  };

  Store.prototype.seriesGroups = function () {
    var self = this;
    return this._groupsOf(this.seriesKeys, this.seriesGroupsMap, function (l) {
      return l.filter(function (c) { return !self._hiddenChannel(c); }).length;
    });
  };

  Store.prototype.seriesInGroup = function (g) {
    var self = this;
    return ((this.seriesGroupsMap || {})[g] || []).filter(function (c) { return !self._hiddenChannel(c); });
  };

  /** Temporadas de una serie: [{season, episodes}]. */
  Store.prototype.seasonsOf = function (info) {
    var map = {};
    var keys = [];
    for (var i = 0; i < info.episodes.length; i++) {
      var e = info.episodes[i];
      var n = e.se || 0;
      if (!map[n]) {
        map[n] = [];
        keys.push(n);
      }
      map[n].push(e);
    }
    keys.sort(function (a, b) { return a - b; });
    return keys.map(function (k) { return { season: k, episodes: map[k] }; });
  };

  /** Pide al servidor Xtream los capítulos de una serie. Promesa. */
  Store.prototype.loadSeriesEpisodes = function (info) {
    var self = this;
    var x = info.xtream;
    if (!x || info.episodes.length) return Promise.resolve(info);
    var s = this.sources.filter(function (z) { return z.id === x.s; })[0];
    if (!s) return Promise.reject(new Error('No se encuentra la lista de esta serie.'));
    var server = P.normalizeServer(s.server);
    var url = server + '/player_api.php?username=' + encodeURIComponent(s.username) +
      '&password=' + encodeURIComponent(s.password) + '&action=get_series_info&series_id=' + encodeURIComponent(x.xs);
    return this.getText(url, 60000).then(function (text) {
      var eps = P.parseXtreamSeriesInfo(text, x, server, s.username, s.password);
      if (!eps.length) throw new Error('El servidor no tiene capítulos de esta serie.');
      self.xtreamEpisodes[x.k] = eps;
      info.episodes = eps.slice();
      for (var i = 0; i < eps.length; i++) self.byKey[eps[i].k] = eps[i];
      return info;
    });
  };

  // ---------------------------------------------------------------- Carpetas automáticas

  Store.prototype.smartFolders = function () {
    var self = this;
    function visible(l) { return (l || []).filter(function (c) { return !self._hiddenChannel(c) && !self._hiddenGroup(c); }); }
    return [
      { id: 'futbol', name: 'Fútbol', channels: visible(this.footballList) },
      { id: 'tdt', name: 'TDT', channels: visible(this.tdtList) }
    ];
  };

  Store.prototype._hiddenGroup = function (c) {
    return !this.settings.showHidden && this.custom.hiddenGroups.indexOf(c.g || '') >= 0;
  };

  // ---------------------------------------------------------------- Consultas

  Store.prototype.channelName = function (c) {
    return this.custom.channelNames[c.k] || c.n;
  };

  Store.prototype.groupName = function (g) {
    return this.custom.groupNames[g] || (g ? g : 'Sin grupo');
  };

  Store.prototype.isFavorite = function (c) {
    return this.custom.favorites.indexOf(c.k) >= 0;
  };

  Store.prototype._hiddenChannel = function (c) {
    return !this.settings.showHidden && this.custom.hiddenChannels.indexOf(c.k) >= 0;
  };

  /** Lista de grupos visibles: [{key, name, count}]. */
  Store.prototype.groups = function () {
    var out = [];
    var self = this;
    for (var i = 0; i < this.groupKeys.length; i++) {
      var g = this.groupKeys[i];
      if (!this.settings.showHidden && this.custom.hiddenGroups.indexOf(g) >= 0) continue;
      var n = this.groupChannels[g].filter(function (c) { return !self._hiddenChannel(c); }).length;
      if (n > 0) out.push({ key: g, name: this.groupName(g), count: n });
    }
    return out;
  };

  Store.prototype.channelsInGroup = function (g) {
    var self = this;
    return (this.groupChannels[g] || []).filter(function (c) { return !self._hiddenChannel(c); });
  };

  Store.prototype.allChannels = function () {
    var out = [];
    var gs = this.groups();
    for (var i = 0; i < gs.length; i++) out = out.concat(this.channelsInGroup(gs[i].key));
    return out;
  };

  Store.prototype.favoriteChannels = function () {
    var out = [];
    for (var i = 0; i < this.custom.favorites.length; i++) {
      var c = this.byKey[this.custom.favorites[i]];
      if (c) out.push(c);
    }
    return out;
  };

  Store.prototype.folders = function () {
    return this.custom.folders || [];
  };

  Store.prototype.folderChannels = function (folderId) {
    var f = this.folders().filter(function (x) { return x.id === folderId; })[0];
    if (!f) return [];
    var out = [];
    for (var i = 0; i < f.channels.length; i++) {
      var c = this.byKey[f.channels[i]];
      if (c) out.push(c);
    }
    return out;
  };

  Store.prototype.search = function (query, limit) {
    var q = P.normalizeText(String(query || '').trim());
    if (!q) return [];
    limit = limit || 300;
    var out = [];
    var all = this.allChannels();
    var mg = this.movieGroups();
    for (var m = 0; m < mg.length; m++) all = all.concat(this.moviesInGroup(mg[m].key));
    var self = this;
    Object.keys(this.seriesByKey || {}).forEach(function (k) {
      if (!self._hiddenChannel(self.seriesByKey[k])) all = all.concat(self.seriesByKey[k].episodes);
    });
    for (var i = 0; i < all.length && out.length < limit; i++) {
      if (P.normalizeText(this.channelName(all[i])).indexOf(q) >= 0) out.push(all[i]);
    }
    return out;
  };

  Store.prototype.totalChannels = function () {
    var n = 0;
    var g = this.groupChannels || {};
    Object.keys(g).forEach(function (k) { n += g[k].length; });
    return n;
  };

  // ---------------------------------------------------------------- Cambios

  Store.prototype.toggleFavorite = function (c) {
    var i = this.custom.favorites.indexOf(c.k);
    if (i >= 0) this.custom.favorites.splice(i, 1);
    else this.custom.favorites.push(c.k);
    this.save();
    return i < 0;
  };

  Store.prototype.setLastChannel = function (c) {
    this.settings.lastChannelKey = c.k;
    this.save();
  };

  Store.prototype.addSource = function (src) {
    src.id = src.id || newId();
    src.enabled = src.enabled !== false;
    src.xtreamOutput = src.xtreamOutput || 'ts';
    this.sources.push(src);
    this.channelsBySource[src.id] = [];
    this.save();
    return src;
  };

  Store.prototype.removeSource = function (id) {
    this.sources = this.sources.filter(function (s) { return s.id !== id; });
    delete this.channelsBySource[id];
    try {
      this.storage.removeItem(CH_PREFIX + id);
      this.storage.removeItem(FILE_PREFIX + id);
    } catch (e) { /* nada */ }
    this.save();
    this.rebuild();
  };

  /** Descarga y lee una lista. Devuelve una promesa con el número de canales. */
  Store.prototype.refreshSource = function (s) {
    var self = this;
    var job;
    if (s.type === 'xtream') {
      var server = P.normalizeServer(s.server);
      var base = server + '/player_api.php?username=' + encodeURIComponent(s.username) +
        '&password=' + encodeURIComponent(s.password);
      job = Promise.all([
        self.getText(base + '&action=get_live_categories'),
        self.getText(base + '&action=get_live_streams', 120000)
      ]).then(function (r) {
        var cats;
        var streams;
        try {
          cats = JSON.parse(r[0]);
          streams = JSON.parse(r[1]);
        } catch (e) {
          throw new Error('El servidor no ha devuelto la lista de canales. Revisa usuario y contraseña.');
        }
        var live = P.parseXtream({
          categories: cats,
          streams: streams,
          sourceId: s.id,
          server: server,
          username: s.username,
          password: s.password,
          output: s.xtreamOutput
        });
        // Películas y series: si el servidor no las tiene, se sigue igual.
        function optional(p) { return p.then(function (v) { return v; }, function () { return null; }); }
        return Promise.all([
          optional(self.getText(base + '&action=get_vod_categories')),
          optional(self.getText(base + '&action=get_vod_streams', 120000)),
          optional(self.getText(base + '&action=get_series_categories')),
          optional(self.getText(base + '&action=get_series', 120000))
        ]).then(function (v) {
          var out = live;
          try {
            if (v[1]) out = out.concat(P.parseXtreamVod({ categories: v[0] || '[]', streams: v[1], sourceId: s.id, server: server, username: s.username, password: s.password }));
          } catch (e) { /* sin películas */ }
          try {
            if (v[3]) out = out.concat(P.parseXtreamSeries({ categories: v[2] || '[]', series: v[3], sourceId: s.id }));
          } catch (e2) { /* sin series */ }
          return out;
        });
      });
    } else if (s.type === 'm3uFile') {
      var text = null;
      try { text = self.storage.getItem(FILE_PREFIX + s.id); } catch (e) { text = null; }
      job = text == null
        ? Promise.reject(new Error('Esta lista era un archivo del móvil y no se ha copiado. Vuelve a exportar la configuración.'))
        : Promise.resolve(P.parseM3u(text, s.id).channels);
    } else {
      job = self.getText(s.url, 120000).then(function (t) {
        if (t.indexOf('#EXT') < 0 && t.indexOf('http') < 0) {
          throw new Error('El enlace no contiene una lista M3U.');
        }
        return P.parseM3u(t, s.id).channels;
      });
    }
    return job.then(function (channels) {
      self.channelsBySource[s.id] = channels;
      self._write(CH_PREFIX + s.id, channels);
      s.channelCount = channels.length;
      s.lastUpdated = new Date().toISOString();
      s.lastError = null;
      self.save();
      return channels.length;
    }, function (err) {
      s.lastError = (err && err.message) || String(err);
      self.save();
      throw err;
    });
  };

  /** Actualiza todas las listas activas. Siempre se resuelve (los errores quedan en cada lista). */
  Store.prototype.refreshAll = function () {
    var self = this;
    var jobs = this.sources.filter(function (s) { return s.enabled; }).map(function (s) {
      return self.refreshSource(s).then(function () { return null; }, function (e) { return s.name + ': ' + e.message; });
    });
    return Promise.all(jobs).then(function (errors) {
      self.settings.lastRefresh = new Date().toISOString();
      self.save();
      self.rebuild();
      return errors.filter(function (e) { return e; });
    });
  };

  /** Sustituye la configuración por la exportada desde el móvil o el PC. */
  Store.prototype.importConfig = function (text) {
    var j;
    try {
      j = typeof text === 'string' ? JSON.parse(text) : text;
    } catch (e) {
      throw new Error('El archivo no es una configuración de Mi IPTV.');
    }
    if (!j || j.app !== 'mi-iptv') throw new Error('El archivo no es una configuración de Mi IPTV.');
    for (var i = 0; i < this.sources.length; i++) {
      try {
        this.storage.removeItem(CH_PREFIX + this.sources[i].id);
        this.storage.removeItem(FILE_PREFIX + this.sources[i].id);
      } catch (e) { /* nada */ }
    }
    this.channelsBySource = {};
    this._applyConfig(j);
    var files = j.files || {};
    for (var id in files) {
      if (Object.prototype.hasOwnProperty.call(files, id)) {
        try { this.storage.setItem(FILE_PREFIX + id, String(files[id])); } catch (e) { /* demasiado grande */ }
      }
    }
    this.settings.lastRefresh = null;
    this.save();
    this.rebuild();
  };

  /** Enlace de la guía corta de Xtream para un canal (o null si no es Xtream). */
  Store.prototype.shortEpgUrl = function (c) {
    if (!c.x) return null;
    var s = this.sources.filter(function (x) { return x.id === c.s; })[0];
    if (!s || s.type !== 'xtream') return null;
    return P.normalizeServer(s.server) + '/player_api.php?username=' + encodeURIComponent(s.username) +
      '&password=' + encodeURIComponent(s.password) + '&action=get_short_epg&limit=2&stream_id=' + encodeURIComponent(c.x);
  };

  Store.httpGetText = httpGetText;
  Store.memoryStorage = memoryStorage;

  if (typeof module !== 'undefined' && module.exports) module.exports = Store;
  else root.MiStore = Store;
})(this);
