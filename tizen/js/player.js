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
        onevent: function () {}
      });
      av.prepareAsync(function () {
        if (token !== self._token) return;
        try {
          av.play();
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

  /** Pistas de audio disponibles (solo en el televisor). */
  Player.prototype.audioTracks = function () {
    if (!this.useAvplay) return [];
    try {
      return root.webapis.avplay.getTotalTrackInfo().filter(function (t) { return t.type === 'AUDIO'; });
    } catch (e) {
      return [];
    }
  };

  Player.prototype.nextAudioTrack = function () {
    var tracks = this.audioTracks();
    if (tracks.length < 2) return null;
    this._audioIdx = ((this._audioIdx || 0) + 1) % tracks.length;
    var t = tracks[this._audioIdx];
    try {
      root.webapis.avplay.setSelectTrack('AUDIO', t.index);
    } catch (e) {
      return null;
    }
    var lang = '';
    try { lang = JSON.parse(t.extra_info).language || ''; } catch (e2) { lang = ''; }
    return 'Audio ' + (this._audioIdx + 1) + ' de ' + tracks.length + (lang ? ' (' + lang + ')' : '');
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
