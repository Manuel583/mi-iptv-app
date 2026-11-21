// Sincronización con el Google Drive del usuario (igual que en el móvil y
// el PC). Se entra con un código que se escribe en google.com/device desde
// el móvil, así no hace falta teclear contraseñas con el mando.
(function (root) {
  'use strict';

  // Se rellenan al compilar con los secretos del repositorio de GitHub.
  var BUILT_IN_ID = '__GOOGLE_CLIENT_ID__';
  var BUILT_IN_SECRET = '__GOOGLE_CLIENT_SECRET__';
  var SCOPE = 'https://www.googleapis.com/auth/drive.appdata openid email';
  var FILE_NAME = 'mi-iptv.json';
  var KEY = 'mi-iptv-google';

  // Ajustes que la tele conoce y comparte.
  var TV_SETTINGS = ['userAgent', 'showHidden', 'autoRefreshHours', 'audioLanguage'];
  var LOCAL_SOURCE_FIELDS = ['lastUpdated', 'lastError', 'channelCount', 'detectedEpgUrl'];

  function request(method, url, opts) {
    opts = opts || {};
    return new Promise(function (resolve, reject) {
      var xhr = new XMLHttpRequest();
      xhr.open(method, url, true);
      xhr.timeout = 30000;
      var h = opts.headers || {};
      for (var k in h) if (Object.prototype.hasOwnProperty.call(h, k)) xhr.setRequestHeader(k, h[k]);
      xhr.onload = function () {
        var json = null;
        try { json = JSON.parse(xhr.responseText); } catch (e) { json = null; }
        resolve({ status: xhr.status, json: json, text: xhr.responseText });
      };
      xhr.onerror = function () { reject(new Error('No hay conexión con Google.')); };
      xhr.ontimeout = function () { reject(new Error('Google tarda demasiado en responder.')); };
      xhr.send(opts.body == null ? null : opts.body);
    });
  }

  function form(obj) {
    var parts = [];
    for (var k in obj) if (Object.prototype.hasOwnProperty.call(obj, k)) parts.push(encodeURIComponent(k) + '=' + encodeURIComponent(obj[k]));
    return parts.join('&');
  }

  var FORM = { 'Content-Type': 'application/x-www-form-urlencoded' };

  function googleError(j) {
    var e = (j && j.error) || '';
    if (e === 'access_denied') return 'Has rechazado el permiso en la página de Google.';
    if (e === 'expired_token') return 'El código ha caducado. Vuelve a intentarlo.';
    if (e === 'invalid_client') return 'El permiso de Google de la app no es correcto.';
    if (e === 'invalid_grant') return 'Google ha retirado el permiso. Vuelve a conectar la cuenta.';
    return (j && j.error_description) || e || 'Error de Google.';
  }

  /**
   * Prepara lo que sube la tele: parte de lo último que había en Drive
   * (para no perder datos que la tele no maneja, como las guías) y pone
   * encima los cambios hechos en la tele.
   */
  function mergeForUpload(remote, tv) {
    remote = remote || { app: 'mi-iptv', version: 1, settings: {}, custom: {}, sources: [], files: {} };
    var out = JSON.parse(JSON.stringify(remote));
    out.app = 'mi-iptv';
    out.settings = out.settings || {};
    for (var i = 0; i < TV_SETTINGS.length; i++) {
      var k = TV_SETTINGS[i];
      if (tv.settings && tv.settings[k] !== undefined) out.settings[k] = tv.settings[k];
    }
    out.custom = JSON.parse(JSON.stringify(tv.custom || {}));
    var byId = {};
    (out.sources || []).forEach(function (s) { byId[s.id] = s; });
    out.sources = (tv.sources || []).map(function (s) {
      var merged = JSON.parse(JSON.stringify(byId[s.id] || {}));
      for (var f in s) {
        if (Object.prototype.hasOwnProperty.call(s, f) && LOCAL_SOURCE_FIELDS.indexOf(f) < 0) merged[f] = s[f];
      }
      for (var j = 0; j < LOCAL_SOURCE_FIELDS.length; j++) delete merged[LOCAL_SOURCE_FIELDS[j]];
      return merged;
    });
    var files = {};
    var keep = {};
    out.sources.forEach(function (s) { keep[s.id] = true; });
    var rf = out.files || {};
    for (var id in rf) if (Object.prototype.hasOwnProperty.call(rf, id) && keep[id]) files[id] = rf[id];
    out.files = files;
    return out;
  }

  function Sync(store) {
    this.store = store;
    this.state = {};
    try { this.state = JSON.parse(root.localStorage.getItem(KEY) || '{}') || {}; } catch (e) { this.state = {}; }
    this.token = null;
    this.tokenExpires = 0;
  }

  Sync.mergeForUpload = mergeForUpload;

  Sync.prototype._save = function () {
    try { root.localStorage.setItem(KEY, JSON.stringify(this.state)); } catch (e) { /* nada */ }
  };

  Sync.prototype.clientId = function () {
    var id = this.state.clientId || BUILT_IN_ID;
    return id.indexOf('__') === 0 ? '' : id;
  };
  Sync.prototype.clientSecret = function () {
    var s = this.state.clientSecret || BUILT_IN_SECRET;
    return s.indexOf('__') === 0 ? '' : s;
  };
  Sync.prototype.hasClient = function () { return !!(this.clientId() && this.clientSecret()); };
  Sync.prototype.connected = function () { return !!this.state.refreshToken; };
  Sync.prototype.account = function () { return this.state.account || ''; };

  Sync.prototype.setClient = function (id, secret) {
    this.state.clientId = String(id || '').trim();
    this.state.clientSecret = String(secret || '').trim();
    this._save();
  };

  /** Pide el código. Devuelve {userCode, url, deviceCode, interval, expires}. */
  Sync.prototype.startSignIn = function () {
    var self = this;
    return request('POST', 'https://oauth2.googleapis.com/device/code', {
      headers: FORM,
      body: form({ client_id: self.clientId(), scope: SCOPE })
    }).then(function (r) {
      if (r.status !== 200) throw new Error(googleError(r.json));
      return {
        userCode: r.json.user_code,
        url: r.json.verification_url || r.json.verification_uri || 'https://www.google.com/device',
        deviceCode: r.json.device_code,
        interval: r.json.interval || 5,
        expires: Date.now() + (r.json.expires_in || 1800) * 1000
      };
    });
  };

  /** Espera a que se acepte el permiso. isCancelled() permite abandonar. */
  Sync.prototype.waitForSignIn = function (code, isCancelled) {
    var self = this;
    var interval = code.interval;
    return new Promise(function (resolve, reject) {
      function poll() {
        if (isCancelled && isCancelled()) return resolve(false);
        if (Date.now() > code.expires) return resolve(false);
        request('POST', 'https://oauth2.googleapis.com/token', {
          headers: FORM,
          body: form({
            client_id: self.clientId(),
            client_secret: self.clientSecret(),
            device_code: code.deviceCode,
            grant_type: 'urn:ietf:params:oauth:grant-type:device_code'
          })
        }).then(function (r) {
          if (r.status === 200) {
            self.state.refreshToken = r.json.refresh_token || '';
            self.token = r.json.access_token;
            self.tokenExpires = Date.now() + ((r.json.expires_in || 3600) - 60) * 1000;
            self.state.account = emailFromIdToken(r.json.id_token) || 'tu cuenta de Google';
            self.state.lastSync = 0;
            self.state.remoteId = '';
            self._save();
            return resolve(true);
          }
          var e = r.json && r.json.error;
          if (e === 'authorization_pending') return setTimeout(poll, interval * 1000);
          if (e === 'slow_down') { interval += 5; return setTimeout(poll, interval * 1000); }
          reject(new Error(googleError(r.json)));
        }, function () { setTimeout(poll, interval * 1000); });
      }
      setTimeout(poll, interval * 1000);
    });
  };

  function emailFromIdToken(t) {
    if (!t) return '';
    try {
      var p = t.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
      while (p.length % 4) p += '=';
      return JSON.parse(decodeURIComponent(escape(root.atob(p)))).email || '';
    } catch (e) {
      return '';
    }
  }

  Sync.prototype.signOut = function () {
    var t = this.state.refreshToken;
    this.state = { clientId: this.state.clientId, clientSecret: this.state.clientSecret };
    this.token = null;
    this._save();
    if (t) request('POST', 'https://oauth2.googleapis.com/revoke', { headers: FORM, body: form({ token: t }) }).catch(function () {});
  };

  Sync.prototype._accessToken = function () {
    var self = this;
    if (this.token && Date.now() < this.tokenExpires) return Promise.resolve(this.token);
    return request('POST', 'https://oauth2.googleapis.com/token', {
      headers: FORM,
      body: form({
        client_id: self.clientId(),
        client_secret: self.clientSecret(),
        refresh_token: self.state.refreshToken,
        grant_type: 'refresh_token'
      })
    }).then(function (r) {
      if (r.status !== 200) {
        if (r.json && r.json.error === 'invalid_grant') { self.state.refreshToken = ''; self._save(); }
        throw new Error(googleError(r.json));
      }
      self.token = r.json.access_token;
      self.tokenExpires = Date.now() + ((r.json.expires_in || 3600) - 60) * 1000;
      return self.token;
    });
  };

  Sync.prototype._drive = function (method, url, body, contentType) {
    return this._accessToken().then(function (tok) {
      var h = { Authorization: 'Bearer ' + tok };
      if (contentType) h['Content-Type'] = contentType;
      return request(method, url, { headers: h, body: body });
    }).then(function (r) {
      if (r.status < 200 || r.status >= 300) throw new Error('Google Drive respondió ' + r.status + '.');
      return r;
    });
  };

  Sync.prototype._remoteInfo = function () {
    var q = encodeURIComponent("name = '" + FILE_NAME + "'");
    return this._drive('GET', 'https://www.googleapis.com/drive/v3/files?spaces=appDataFolder&orderBy=modifiedTime%20desc&fields=files(id,modifiedTime)&q=' + q)
      .then(function (r) {
        var f = (r.json && r.json.files) || [];
        return f.length ? { id: f[0].id, modified: Date.parse(f[0].modifiedTime) } : null;
      });
  };

  Sync.prototype._download = function (id) {
    return this._drive('GET', 'https://www.googleapis.com/drive/v3/files/' + id + '?alt=media').then(function (r) { return r.text; });
  };

  Sync.prototype._upload = function (data) {
    var self = this;
    var body = JSON.stringify(data);
    if (this.state.remoteId) {
      return this._drive('PATCH', 'https://www.googleapis.com/upload/drive/v3/files/' + this.state.remoteId + '?uploadType=media', body, 'application/json');
    }
    var b = 'mi-iptv-limite';
    var multi = '--' + b + '\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n' +
      JSON.stringify({ name: FILE_NAME, parents: ['appDataFolder'] }) + '\r\n--' + b +
      '\r\nContent-Type: application/json\r\n\r\n' + body + '\r\n--' + b + '--';
    return this._drive('POST', 'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id', multi, 'multipart/related; boundary=' + b)
      .then(function (r) { self.state.remoteId = r.json.id; self._save(); });
  };

  /**
   * Trae los cambios de Drive. Devuelve true si cambió la configuración
   * (hay que volver a descargar los canales).
   */
  Sync.prototype.pull = function (force) {
    var self = this;
    if (!this.connected()) return Promise.resolve(false);
    return this._remoteInfo().then(function (info) {
      if (!info) {
        // Todavía no hay nada en Drive: subir lo de la tele.
        return self.push().then(function () { return false; });
      }
      self.state.remoteId = info.id;
      if (!force && self.state.lastSync && info.modified <= self.state.lastSync) return false;
      return self._download(info.id).then(function (text) {
        var j = JSON.parse(text);
        if (!j || j.app !== 'mi-iptv') return false;
        var keep = self.store.settings.lastChannelKey;
        self.store.importConfig(text);
        self.store.settings.lastChannelKey = keep;
        self.store.save();
        self.state.lastRemote = j;
        self.state.lastSync = Date.now();
        self._save();
        return true;
      });
    });
  };

  /** Sube los cambios hechos en la tele (favoritos, ocultos, idioma…). */
  Sync.prototype.push = function () {
    var self = this;
    if (!this.connected()) return Promise.resolve();
    var data = mergeForUpload(this.state.lastRemote, this.store.configJson());
    if (this.state.lastRemote) {
      var prev = JSON.parse(JSON.stringify(this.state.lastRemote));
      delete prev.updatedAt;
      delete prev.device;
      if (JSON.stringify(mergeForUpload(prev, this.store.configJson())) === JSON.stringify(prev)) {
        return Promise.resolve();
      }
    }
    data.updatedAt = new Date().toISOString();
    data.device = 'tele';
    return this._upload(data).then(function () {
      self.state.lastRemote = data;
      self.state.lastSync = Date.now();
      self._save();
    });
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = Sync;
  else root.MiSync = Sync;
})(this);
