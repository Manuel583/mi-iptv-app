// Reproductor de vídeo. En el televisor usa el reproductor de Samsung
// (AVPlay), que admite HLS (.m3u8) y MPEG-TS (.ts) por hardware.
// En un navegador normal (para pruebas) usa la etiqueta <video>.
(function (root) {
  'use strict';

  function hasAvplay() {
    return !!(root.webapis && root.webapis.avplay);
  }

  function Player(opts) {
    this.onState = opts.onState || function () {};
    this.onError = opts.onError || function () {};
    this.onSubtitle = opts.onSubtitle || function () {};
    this.preferredAudio = opts.preferredAudio || function () { return ''; };
    this.objectEl = opts.objectEl;
    this.videoEl = opts.videoEl;
    this.useAvplay = hasAvplay();
    this.current = null;
    this.retries = 0;
    this.paused = false;
    this._token = 0;
    if (this.useAvplay) {
      this.objectEl.style.display = 'block';
      this.videoEl.style.display = 'none';
    } else {
      this.objectEl.style.display = 'none';
      this.videoEl.style.display = 'block';
    }
  }

  Player.prototype.play = function (url, opts) {
    opts = opts || {};
    this.current = { url: url, userAgent: opts.userAgent || '', referrer: opts.referrer || '' };
    this.retries = 0;
    this.paused = false;
    this._start();
  };

  Player.prototype._start = function () {
    var self = this;
    var token = ++this._token;
    var cur = this.current;
    if (!cur) return;
    this.onState('loading');
    if (!this.useAvplay) {
      var v = this.videoEl;
      v.onplaying = function () { if (token === self._token) self.onState('playing'); };
      v.onwaiting = function () { if (token === self._token) self.onState('loading'); };
      v.onerror = function () { if (token === self._token) self._failed('El canal no se puede reproducir en este navegador.'); };
      v.src = cur.url;
      var pr = v.play();
      if (pr && pr.catch) pr.catch(function () { /* el error llega por onerror */ });
      return;
    }
    var av = root.webapis.avplay;
    try { av.stop(); } catch (e) { /* no estaba reproduciendo */ }
    try { av.close(); } catch (e2) { /* nada */ }
    try {
      av.open(cur.url);
      var props = [];
      if (cur.userAgent) props.push('User-Agent=' + cur.userAgent);
      if (cur.referrer) props.push('Referer=' + cur.referrer);
      if (props.length) {
        try { av.setStreamingProperty('CUSTOM_MESSAGE', props.join('|')); } catch (e3) { /* modelos antiguos */ }
      }
      av.setDisplayRect(0, 0, 1920, 1080);
      try { av.setDisplayMethod('PLAYER_DISPLAY_MODE_LETTER_BOX'); } catch (e4) { /* nada */ }
      try { av.setTimeoutForBuffering(20); } catch (e5) { /* nada */ }
      av.setListener({
        onbufferingstart: function () { if (token === self._token) self.onState('loading'); },
        onbufferingcomplete: function () { if (token === self._token) self.onState('playing'); },
        onstreamcompleted: function () { if (token === self._token) self._failed('La emisión se ha cortado.'); },
        onerror: function (type) { if (token === self._token) self._failed('Error de reproducción (' + type + ').'); },
        onevent: function () {},
        onsubtitlechange: function (duration, text) {
          if (token === self._token) self.onSubtitle(text || '', Number(duration) || 0);
        }
      });
      av.prepareAsync(function () {
        if (token !== self._token) return;
        try {
          av.play();
          self._applyPreferredAudio();
          self.onState('playing');
        } catch (e6) {
          self._failed('No se pudo empezar a reproducir.');
        }
      }, function (err) {
        if (token !== self._token) return;
        self._failed('El canal no responde' + (err && err.name ? ' (' + err.name + ')' : '') + '.');
      });
    } catch (e7) {
      this._failed('No se pudo abrir el canal: ' + ((e7 && e7.message) || e7));
    }
  };

  // Reintenta hasta 3 veces antes de avisar, como la reconexión de la app del móvil.
  Player.prototype._failed = function (msg) {
    var self = this;
    if (this.retries < 3 && this.current) {
      this.retries++;
      var token = this._token;
      this.onState('retry', this.retries);
      setTimeout(function () {
        if (token === self._token) self._start();
      }, 1500 * this.retries);
      return;
    }
    this.onState('error');
    this.onError(msg);
  };

  Player.prototype.togglePause = function () {
    if (!this.current) return;
    this.paused = !this.paused;
    if (this.useAvplay) {
      try {
        if (this.paused) root.webapis.avplay.pause();
        else root.webapis.avplay.play();
      } catch (e) { /* nada */ }
    } else if (this.paused) this.videoEl.pause();
    else this.videoEl.play();
    this.onState(this.paused ? 'paused' : 'playing');
  };

  Player.prototype.stop = function () {
    this._token++;
    this.current = null;
    if (this.useAvplay) {
      try { root.webapis.avplay.stop(); } catch (e) { /* nada */ }
      try { root.webapis.avplay.close(); } catch (e2) { /* nada */ }
    } else {
      this.videoEl.removeAttribute('src');
      try { this.videoEl.load(); } catch (e3) { /* nada */ }
    }
    this.onState('stopped');
  };

  // Formas en que las emisiones marcan cada idioma (igual que en el móvil).
  var LANGS = {
    es: ['es', 'spa', 'esp', 'cas', 'spanish'],
    en: ['en', 'eng', 'english'],
    ca: ['ca', 'cat', 'catalan'],
    eu: ['eu', 'eus', 'baq', 'basque'],
    gl: ['gl', 'glg', 'galician'],
    fr: ['fr', 'fre', 'fra', 'french'],
    pt: ['pt', 'por', 'portuguese'],
    it: ['it', 'ita', 'italian'],
    de: ['de', 'ger', 'deu', 'german']
  };
  var LANG_NAMES = {
    es: 'Español', en: 'Inglés', ca: 'Catalán', eu: 'Euskera', gl: 'Gallego',
    fr: 'Francés', pt: 'Portugués', it: 'Italiano', de: 'Alemán'
  };

  /** Convierte "spa", "es"… en un código corto ("es"), o '' si no se conoce. */
  function langCode(lang) {
    var l = String(lang || '').toLowerCase();
    for (var k in LANGS) {
      if (LANGS.hasOwnProperty(k) && LANGS[k].indexOf(l) >= 0) return k;
    }
    return '';
  }
  Player.langCode = langCode;
  Player.langName = function (code) { return LANG_NAMES[code] || ''; };

  /**
   * Pistas de audio ('AUDIO') o de subtítulos ('TEXT') de la emisión
   * (solo en el televisor). Cada una: {index, lang, label, selected}.
   */
  Player.prototype.tracks = function (type) {
    if (!this.useAvplay) return [];
    var av = root.webapis.avplay;
    var all;
    try { all = av.getTotalTrackInfo(); } catch (e) { return []; }
    var current = -1;
    try {
      var cur = av.getCurrentStreamInfo();
      for (var c = 0; c < cur.length; c++) {
        if (cur[c].type === type) current = cur[c].index;
      }
    } catch (e2) { /* modelos antiguos */ }
    var out = [];
    var n = 0;
    for (var i = 0; i < all.length; i++) {
      var t = all[i];
      if (t.type !== type) continue;
      n++;
      var info = {};
      try { info = JSON.parse(t.extra_info) || {}; } catch (e3) { info = {}; }
      var lang = info.language || info.track_lang || '';
      var name = LANG_NAMES[langCode(lang)] || (lang ? String(lang).toUpperCase() : 'Pista ' + n);
      if (info.fourCC) name += ' | ' + info.fourCC;
      out.push({ index: t.index, lang: lang, label: name, selected: t.index === current });
    }
    if (type === 'TEXT' && this._subsOff) {
      for (var j = 0; j < out.length; j++) out[j].selected = false;
    }
    return out;
  };

  /** Elige una pista. Para subtítulos, index = -1 los apaga. */
  Player.prototype.selectTrack = function (type, index) {
    if (!this.useAvplay) return false;
    var av = root.webapis.avplay;
    try {
      if (type === 'TEXT') {
        this._subsOff = index < 0;
        av.setSilentSubtitle(index < 0);
        if (index < 0) {
          this.onSubtitle('', 0);
          return true;
        }
      }
      av.setSelectTrack(type, index);
      return true;
    } catch (e) {
      return false;
    }
  };

  Player.prototype._applyPreferredAudio = function () {
    var want = this.preferredAudio();
    this._subsOff = true;
    try { root.webapis.avplay.setSilentSubtitle(true); } catch (e) { /* nada */ }
    if (!want) return;
    var list = this.tracks('AUDIO');
    for (var i = 0; i < list.length; i++) {
      if (langCode(list[i].lang) === want) {
        if (!list[i].selected) this.selectTrack('AUDIO', list[i].index);
        return;
      }
    }
  };

  // Al salir de la app o apagar la pantalla, se para; al volver, se reanuda.
  Player.prototype.suspend = function () {
    if (this.useAvplay) {
      try { root.webapis.avplay.suspend(); } catch (e) { /* nada */ }
    }
  };

  Player.prototype.restore = function () {
    if (this.useAvplay && this.current) {
      try {
        root.webapis.avplay.restore();
      } catch (e) {
        this._start();
      }
    }
  };

  root.MiPlayer = Player;
})(this);
