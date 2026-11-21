// Interfaz para el televisor: todo se maneja con el mando a distancia
// (flechas, OK, Volver, botones de colores, CH+ / CH- y números).
(function (root) {
  'use strict';

  var P = root.MiParsers;
  var store = new root.MiStore();
  var VERSION = '1.0.0';

  // ------------------------------------------------------------ Utilidades

  function $(id) { return document.getElementById(id); }

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function pad2(n) { return (n < 10 ? '0' : '') + n; }
  function hhmm(d) { return pad2(d.getHours()) + ':' + pad2(d.getMinutes()); }

  var toastTimer = null;
  function toast(msg, ms) {
    var t = $('toast');
    t.textContent = msg;
    t.classList.remove('hidden');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { t.classList.add('hidden'); }, ms || 3500);
  }

  function busy(msg) {
    if (msg) {
      $('busy-text').textContent = msg;
      $('busy').classList.remove('hidden');
    } else $('busy').classList.add('hidden');
  }

  function logoHtml(url) {
    return url ? '<img src="' + esc(url) + '" onerror="this.style.display=\'none\'">' : '';
  }

  /** Convierte enlaces de Google Drive y Dropbox en enlaces de descarga directa. */
  function directDownloadUrl(url) {
    var u = String(url || '').trim();
    var m = /drive\.google\.com\/file\/d\/([^\/?#]+)/.exec(u) || /drive\.google\.com\/open\?id=([^&#]+)/.exec(u);
    if (m) return 'https://drive.google.com/uc?export=download&id=' + m[1];
    if (/dropbox\.com\//.test(u)) return u.replace(/([?&])dl=0/, '$1dl=1') + (/[?&]dl=/.test(u) ? '' : (u.indexOf('?') >= 0 ? '&' : '?') + 'dl=1');
    return u;
  }

  // ------------------------------------------------------------ Teclas del mando

  var KEY = {
    LEFT: 37, UP: 38, RIGHT: 39, DOWN: 40, ENTER: 13,
    BACK: 10009, ESC: 27, BACKSPACE: 8,
    CH_UP: 427, CH_DOWN: 428, PAGE_UP: 33, PAGE_DOWN: 34,
    RED: 403, GREEN: 404, YELLOW: 405, BLUE: 406,
    PLAY_PAUSE: 10252, PLAY: 415, PAUSE: 19, STOP: 413,
    INFO: 457, CH_LIST: 10073,
    DONE: 65376, CANCEL: 65385
  };

  function registerTvKeys() {
    try {
      var names = ['ColorF0Red', 'ColorF1Green', 'ColorF2Yellow', 'ColorF3Blue', 'ChannelUp', 'ChannelDown',
        'MediaPlayPause', 'MediaPlay', 'MediaPause', 'MediaStop', 'Info', 'ChannelList',
        '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
      for (var i = 0; i < names.length; i++) {
        try { root.tizen.tvinputdevice.registerKey(names[i]); } catch (e) { /* tecla no disponible */ }
      }
    } catch (e2) { /* no es un televisor */ }
  }

  /** Traduce la tecla pulsada a una acción. Admite también un teclado de PC para pruebas. */
  function actionOf(e) {
    var c = e.keyCode;
    if (c === KEY.LEFT) return 'left';
    if (c === KEY.RIGHT) return 'right';
    if (c === KEY.UP) return 'up';
    if (c === KEY.DOWN) return 'down';
    if (c === KEY.ENTER) return 'ok';
    if (c === KEY.BACK || c === KEY.ESC || c === KEY.BACKSPACE) return 'back';
    if (c === KEY.CH_UP || c === KEY.PAGE_UP) return 'chup';
    if (c === KEY.CH_DOWN || c === KEY.PAGE_DOWN) return 'chdown';
    if (c === KEY.RED || e.key === 'r') return 'red';
    if (c === KEY.GREEN || e.key === 'g') return 'green';
    if (c === KEY.YELLOW || e.key === 'y') return 'yellow';
    if (c === KEY.BLUE || e.key === 'b') return 'blue';
    if (c === KEY.PLAY_PAUSE || c === KEY.PLAY || c === KEY.PAUSE || e.key === ' ') return 'playpause';
    if (c === KEY.STOP) return 'stop';
    if (c === KEY.INFO || e.key === 'i') return 'info';
    if (c === KEY.CH_LIST || e.key === 'l') return 'chlist';
    if (c >= 48 && c <= 57) return 'digit' + (c - 48);
    if (c >= 96 && c <= 105) return 'digit' + (c - 96);
    return null;
  }

  // ------------------------------------------------------------ Lista con desplazamiento
  // Solo dibuja las filas que se ven, para que listas de miles de canales vayan fluidas.

  function VList(el, renderRow) {
    this.el = el;
    this.renderRow = renderRow;
    this.items = [];
    this.index = 0;
    this.top = 0;
    this.rowH = 78;
    this.visible = Math.floor(el.clientHeight / this.rowH) || 10;
    this.emptyText = '';
    this.selectedIndex = -1;
  }

  VList.prototype.set = function (items, index, emptyText) {
    this.items = items || [];
    this.emptyText = emptyText || '';
    this.index = Math.max(0, Math.min(index || 0, this.items.length - 1));
    this.top = Math.max(0, this.index - Math.floor(this.visible / 2));
    this.render();
  };

  VList.prototype.move = function (delta) {
    var n = this.items.length;
    if (!n) return false;
    var next = this.index + delta;
    if (next < 0) next = Math.abs(delta) > 1 ? 0 : n - 1;
    else if (next >= n) next = Math.abs(delta) > 1 ? n - 1 : 0;
    if (next === this.index) return false;
    this.index = next;
    this.render();
    return true;
  };

  VList.prototype.current = function () { return this.items[this.index]; };

  VList.prototype.setActive = function (on) {
    if (on) this.el.classList.add('active');
    else this.el.classList.remove('active');
  };

  VList.prototype.render = function () {
    this.visible = Math.floor(this.el.clientHeight / this.rowH) || this.visible;
    var n = this.items.length;
    if (!n) {
      this.el.innerHTML = this.emptyText ? '<div class="empty">' + esc(this.emptyText) + '</div>' : '';
      return;
    }
    if (this.index < this.top + 1) this.top = Math.max(0, this.index - 1);
    if (this.index > this.top + this.visible - 2) this.top = Math.min(n - this.visible, this.index - this.visible + 2);
    if (this.top < 0) this.top = 0;
    var html = '';
    var end = Math.min(n, this.top + this.visible);
    for (var i = this.top; i < end; i++) {
      var cls = 'row' + (i === this.index ? ' focus' : '') + (i === this.selectedIndex ? ' selected' : '');
      html += '<div class="' + cls + '">' + this.renderRow(this.items[i], i) + '</div>';
    }
    if (n > this.visible) {
      var h = this.el.clientHeight;
      var barH = Math.max(40, h * this.visible / n);
      var barTop = (h - barH) * (this.top / Math.max(1, n - this.visible));
      html += '<div class="scrollbar" style="top:' + barTop + 'px;height:' + barH + 'px"></div>';
    }
    this.el.innerHTML = html;
  };

  // ------------------------------------------------------------ Estado

  var screen = 'browse';
  var browseCol = 0; // 0 = categorías, 1 = canales
  var catList;
  var chanList;
  var sideList;
  var trackList;
  var sync;
  var pushTimer = null;
  var pulling = false;
  var trackType = '';   // '' = lista de canales; 'AUDIO' o 'TEXT' = pistas
  var subsTimer = null;
  var player;
  var searchQuery = '';
  var playList = [];   // canales de la lista desde la que se está viendo
  var playIndex = 0;
  var playListTitle = '';
  var osdTimer = null;
  var digits = '';
  var digitTimer = null;
  var sideOpen = false;
  var lastBackPress = 0;
  var epgToken = 0;

  function channelRow(c, i) {
    return '<span class="num">' + (i + 1) + '</span>' +
      '<span class="logo">' + (c.l ? logoHtml(c.l) : '<span class="ph">' + esc(store.channelName(c).replace(/^[^A-Za-z0-9ÁÉÍÓÚÑáéíóúñ]+/, '').charAt(0).toUpperCase()) + '</span>') + '</span>' +
      '<span class="name">' + esc(store.channelName(c)) + '</span>' +
      (store.isFavorite(c) ? '<span class="star">★</span>' : '');
  }

  function catRow(cat) {
    return '<span class="name">' + esc(cat.name) + '</span>' +
      (cat.count != null ? '<span class="count">' + cat.count + '</span>' : '');
  }

  // ------------------------------------------------------------ Pantalla de canales

  function buildCategories() {
    var cats = [
      { id: 'act:search', name: 'Buscar' },
      { id: 'act:settings', name: 'Ajustes y listas' }
    ];
    if (searchQuery) cats.push({ id: 'search', name: 'Resultados: "' + searchQuery + '"' });
    var favs = store.favoriteChannels();
    cats.push({ id: 'fav', name: '★  Favoritos', count: favs.length });
    cats.push({ id: 'all', name: 'Todos los canales', count: store.allChannels().length });
    var folders = store.folders();
    for (var f = 0; f < folders.length; f++) {
      cats.push({ id: 'folder:' + folders[f].id, name: 'Carpeta: ' + folders[f].name, count: store.folderChannels(folders[f].id).length });
    }
    var groups = store.groups();
    for (var g = 0; g < groups.length; g++) {
      cats.push({ id: 'group:' + groups[g].key, name: groups[g].name, count: groups[g].count });
    }
    return cats;
  }

  function channelsForCat(cat) {
    if (!cat) return [];
    if (cat.id === 'fav') return store.favoriteChannels();
    if (cat.id === 'all') return store.allChannels();
    if (cat.id === 'search') return store.search(searchQuery);
    if (cat.id.indexOf('folder:') === 0) return store.folderChannels(cat.id.substring(7));
    if (cat.id.indexOf('group:') === 0) return store.channelsInGroup(cat.id.substring(6));
    return [];
  }

  function emptyTextFor(cat) {
    if (!cat) return '';
    if (cat.id === 'act:search') return 'Pulsa OK para buscar un canal por su nombre.';
    if (cat.id === 'act:settings') return 'Pulsa OK para añadir listas, importar la configuración del móvil o cambiar ajustes.';
    if (cat.id === 'fav') return 'Aún no tienes favoritos. Ponte encima de un canal y pulsa el botón rojo del mando.';
    if (store.sources.length === 0) return 'Todavía no hay listas. Entra en Ajustes y listas para añadir una.';
    return 'No hay canales aquí.';
  }

  var catPositions = {}; // recuerda en qué canal estabas dentro de cada categoría

  function refreshChannelsColumn(keepIndex) {
    var cat = catList.current();
    var items = channelsForCat(cat);
    var idx = keepIndex ? chanList.index : (cat && catPositions[cat.id]) || 0;
    chanList.set(items, idx, emptyTextFor(cat));
    $('chans-title').textContent = cat && cat.id.indexOf('act:') !== 0 ? cat.name : 'Canales';
    renderInfo();
  }

  function renderBrowse(selectCatId, selectChanKey) {
    var cats = buildCategories();
    var ci = 0;
    var want = selectCatId || (catList.current() && catList.current().id);
    for (var i = 0; i < cats.length; i++) if (cats[i].id === want) ci = i;
    if (!want) {
      // Al abrir: favoritos si hay, si no, todos.
      for (var j = 0; j < cats.length; j++) {
        if (cats[j].id === (store.favoriteChannels().length ? 'fav' : 'all')) ci = j;
      }
    }
    catList.set(cats, ci);
    refreshChannelsColumn(false);
    if (selectChanKey) {
      for (var k = 0; k < chanList.items.length; k++) {
        if (chanList.items[k].k === selectChanKey) {
          chanList.set(chanList.items, k, chanList.emptyText);
          break;
        }
      }
    }
    setBrowseCol(browseCol);
    renderInfo();
  }

  function setBrowseCol(col) {
    if (col === 1 && !chanList.items.length) col = 0;
    browseCol = col;
    catList.setActive(col === 0);
    chanList.setActive(col === 1);
    catList.render();
    chanList.render();
    renderInfo();
  }

  function renderInfo() {
    var el = $('info-panel');
    var c = browseCol === 1 ? chanList.current() : null;
    if (!c) {
      var total = store.totalChannels();
      el.innerHTML = '<div class="info-name">Mi IPTV</div><div class="info-sub">' +
        (store.sources.length ? store.sources.length + (store.sources.length === 1 ? ' lista | ' : ' listas | ') + total + ' canales' : 'Sin listas todavía') +
        '<br><br>Versión ' + VERSION + ' para Samsung TV</div>';
      return;
    }
    var src = store.sources.filter(function (s) { return s.id === c.s; })[0];
    el.innerHTML = '<div class="info-logo">' + logoHtml(c.l) + '</div>' +
      '<div class="info-name">' + esc(store.channelName(c)) + (store.isFavorite(c) ? ' <span class="star">★</span>' : '') + '</div>' +
      '<div class="info-sub">' + esc(store.groupName(c.g || '')) + (src ? '<br>Lista: ' + esc(src.name) : '') + '</div>';
  }

  function browseKey(a) {
    var list = browseCol === 0 ? catList : chanList;
    if (a === 'up' || a === 'down' || a === 'chup' || a === 'chdown') {
      var d = a === 'up' ? -1 : a === 'down' ? 1 : a === 'chup' ? -list.visible : list.visible;
      if (list.move(d) && browseCol === 0) refreshChannelsColumn(false);
      renderInfo();
      return;
    }
    if (a === 'right') {
      if (browseCol === 0) setBrowseCol(1);
      return;
    }
    if (a === 'left') {
      if (browseCol === 1) setBrowseCol(0);
      return;
    }
    if (a === 'ok') {
      if (browseCol === 0) {
        var cat = catList.current();
        if (!cat) return;
        if (cat.id === 'act:search') return openSearch();
        if (cat.id === 'act:settings') return openSettings();
        setBrowseCol(1);
      } else if (chanList.current()) {
        catPositions[catList.current().id] = chanList.index;
        startPlaying(chanList.items, chanList.index, catList.current().name);
      }
      return;
    }
    if (a === 'red' && browseCol === 1 && chanList.current()) {
      var c = chanList.current();
      var on = store.toggleFavorite(c);
      toast(on ? '★ Añadido a favoritos' : 'Quitado de favoritos');
      var curCat = catList.current().id;
      renderBrowse(curCat, curCat === 'fav' ? null : c.k);
      return;
    }
    if (a === 'green') return openSearch();
    if (a === 'yellow') return refreshAll(true);
    if (a === 'blue') return openSettings();
    if (a === 'back') {
      if (browseCol === 1) return setBrowseCol(0);
      var now = Date.now();
      if (now - lastBackPress < 2500) return exitApp();
      lastBackPress = now;
      toast('Pulsa Volver otra vez para salir');
    }
  }

  // ------------------------------------------------------------ Reproducción

  function show(name) {
    screen = name;
    $('screen-browse').classList.toggle('hidden', name !== 'browse');
    $('screen-player').classList.toggle('hidden', name !== 'player');
    $('screen-form').classList.toggle('hidden', name !== 'form');
    // En el televisor el vídeo va detrás de la página: el fondo debe ser transparente al reproducir.
    document.body.style.background = name === 'player' ? 'transparent' : '#000';
  }

  function startPlaying(list, index, title) {
    playList = list.slice();
    playListTitle = title || '';
    show('player');
    playIndex = -1;
    tuneTo(index);
  }

  function tuneTo(index) {
    if (!playList.length) return;
    index = (index + playList.length) % playList.length;
    if (index === playIndex && player.current) return showOsd();
    playIndex = index;
    var c = playList[index];
    store.setLastChannel(c);
    player.play(c.u, { userAgent: c.a || store.settings.userAgent, referrer: c.r });
    $('player-state').classList.add('hidden');
    renderOsd(c);
    showOsd();
    loadShortEpg(c);
  }

  function renderOsd(c) {
    $('osd-num').textContent = String(playIndex + 1);
    $('osd-name').textContent = store.channelName(c);
    $('osd-fav').textContent = store.isFavorite(c) ? '★' : '';
    var gname = store.groupName(c.g || '');
    $('osd-group').textContent = gname + (playListTitle && playListTitle !== gname ? '  |  ' + playListTitle : '');
    $('osd-logo').innerHTML = logoHtml(c.l);
    $('osd-logo').style.display = c.l ? '' : 'none';
    $('osd-clock').textContent = hhmm(new Date());
    $('osd-epg').innerHTML = '';
  }

  function showOsd() {
    $('osd').classList.remove('hidden');
    $('osd-clock').textContent = hhmm(new Date());
    clearTimeout(osdTimer);
    osdTimer = setTimeout(function () { $('osd').classList.add('hidden'); }, 6000);
  }

  function loadShortEpg(c) {
    var url = store.shortEpgUrl(c);
    var token = ++epgToken;
    if (!url) return;
    store.getText(url, 15000).then(function (text) {
      if (token !== epgToken) return;
      var j = JSON.parse(text);
      var list = (j && j.epg_listings) || [];
      var html = '';
      var now = Date.now() / 1000;
      for (var i = 0; i < list.length && i < 2; i++) {
        var p = list[i];
        var st = Number(p.start_timestamp);
        var en = Number(p.stop_timestamp || p.end_timestamp);
        var title = P.decodeBase64Utf8(p.title);
        var label = (st ? hhmm(new Date(st * 1000)) : '') + (en ? ' a ' + hhmm(new Date(en * 1000)) : '');
        var isNow = st && en && now >= st && now < en;
        html += '<div class="' + (isNow ? 'now' : 'next') + '">' + (isNow ? 'Ahora: ' : 'Después: ') + esc(label) + '  ' + esc(title) + '</div>';
        if (isNow) html += '<div class="progress"><div style="width:' + Math.round(100 * (now - st) / (en - st)) + '%"></div></div>';
      }
      $('osd-epg').innerHTML = html;
    }).catch(function () { /* sin guía para este canal */ });
  }

  function onPlayerState(state, extra) {
    var el = $('player-state');
    if (state === 'loading') {
      el.textContent = 'Cargando canal…';
      el.classList.remove('hidden');
    } else if (state === 'retry') {
      el.textContent = 'Reconectando (intento ' + extra + ' de 3)…';
      el.classList.remove('hidden');
    } else if (state === 'paused') {
      el.textContent = 'En pausa';
      el.classList.remove('hidden');
    } else if (state === 'playing' || state === 'stopped') {
      el.classList.add('hidden');
    }
  }

  function onPlayerError(msg) {
    var el = $('player-state');
    el.innerHTML = esc(msg) + '<br><span style="font-size:26px;color:#aab6cc">Prueba otro canal con ▲ ▼ o pulsa Volver.</span>';
    el.classList.remove('hidden');
  }

  function openSide() {
    trackType = '';
    sideOpen = true;
    $('side').classList.remove('hidden');
    $('side-title').textContent = playListTitle || 'Canales';
    sideList.setActive(true);
    sideList.set(playList, playIndex);
    clearTimeout(osdTimer);
    $('osd').classList.add('hidden');
  }

  function closeSide() {
    sideOpen = false;
    trackType = '';
    $('side').classList.add('hidden');
  }

  // ------------------------------------------------------------ Pistas

  function trackRow(t) {
    return '<span class="radio">' + (t.selected ? '●' : '○') + '</span> ' + esc(t.label);
  }

  function openTracks(type) {
    var list = player.tracks(type);
    if (type === 'AUDIO' && !list.length) return toast('Este canal solo tiene un idioma de audio');
    if (type === 'TEXT') {
      if (!list.length) return toast('Este canal no emite subtítulos');
      var off = true;
      for (var i = 0; i < list.length; i++) if (list[i].selected) off = false;
      list.unshift({ index: -1, label: 'Sin subtítulos', selected: off });
    }
    trackType = type;
    sideOpen = true;
    $('side').classList.remove('hidden');
    $('side-title').textContent = type === 'AUDIO' ? 'Idioma de audio' : 'Subtítulos';
    var sel = 0;
    for (var j = 0; j < list.length; j++) if (list[j].selected) sel = j;
    trackList.setActive(true);
    trackList.set(list, sel);
    clearTimeout(osdTimer);
    $('osd').classList.add('hidden');
  }

  function chooseTrack() {
    var t = trackList.current();
    var type = trackType;
    closeSide();
    if (!t) return;
    if (!player.selectTrack(type, t.index)) return toast('No se pudo cambiar la pista');
    if (type === 'AUDIO') {
      var code = root.MiPlayer.langCode(t.lang);
      if (code && store.settings.audioLanguage !== code) {
        store.settings.audioLanguage = code;
        store.save();
        toast('Audio en ' + root.MiPlayer.langName(code).toLowerCase() + ' siempre que el canal lo tenga');
        return;
      }
    }
    toast(t.index < 0 ? 'Subtítulos desactivados' : t.label);
  }

  function showSubtitle(text, duration) {
    var el = $('subs');
    clearTimeout(subsTimer);
    if (!text) {
      el.classList.add('hidden');
      return;
    }
    el.innerHTML = esc(text).replace(/\n/g, '<br>');
    el.classList.remove('hidden');
    subsTimer = setTimeout(function () { el.classList.add('hidden'); }, Math.max(1500, duration || 4000));
  }

  function playerKey(a) {
    if (sideOpen && trackType) {
      if (a === 'up') return trackList.move(-1);
      if (a === 'down') return trackList.move(1);
      if (a === 'ok') return chooseTrack();
      if (a === 'back' || a === 'left' || a === 'right' || a === 'yellow' || a === 'blue') return closeSide();
      return;
    }
    if (sideOpen) {
      if (a === 'up') return sideList.move(-1);
      if (a === 'down') return sideList.move(1);
      if (a === 'chup') return sideList.move(-sideList.visible);
      if (a === 'chdown') return sideList.move(sideList.visible);
      if (a === 'ok') {
        closeSide();
        return tuneTo(sideList.index);
      }
      if (a === 'red' && sideList.current()) {
        store.toggleFavorite(sideList.current());
        return sideList.render();
      }
      if (a === 'back' || a === 'left' || a === 'right' || a === 'chlist') return closeSide();
      return;
    }
    if (a && a.indexOf('digit') === 0) return typeDigit(a.substring(5));
    if (a === 'up' || a === 'chup') return tuneTo(playIndex - 1);
    if (a === 'down' || a === 'chdown') return tuneTo(playIndex + 1);
    if (a === 'left' || a === 'chlist') return openSide();
    if (a === 'ok' || a === 'info' || a === 'right') return showOsd();
    if (a === 'playpause') return player.togglePause();
    if (a === 'red') {
      var c = playList[playIndex];
      var on = store.toggleFavorite(c);
      toast(on ? '★ Añadido a favoritos' : 'Quitado de favoritos');
      renderOsd(c);
      loadShortEpg(c);
      return showOsd();
    }
    if (a === 'yellow') return openTracks('AUDIO');
    if (a === 'blue') return openTracks('TEXT');
    if (a === 'back' || a === 'stop') {
      var cur = playList[playIndex];
      player.stop();
      clearTimeout(osdTimer);
      $('osd').classList.add('hidden');
      $('player-state').classList.add('hidden');
      show('browse');
      renderBrowse(null, cur && cur.k);
      setBrowseCol(1);
    }
  }

  function typeDigit(d) {
    digits = (digits + d).substring(0, 4);
    $('numpad').textContent = digits;
    $('numpad').classList.remove('hidden');
    clearTimeout(digitTimer);
    digitTimer = setTimeout(function () {
      var n = parseInt(digits, 10);
      digits = '';
      $('numpad').classList.add('hidden');
      if (n >= 1 && n <= playList.length) tuneTo(n - 1);
      else toast('No hay canal con ese número en esta lista');
    }, 1500);
  }

  // ------------------------------------------------------------ Formularios y ajustes

  var form = null; // { title, items, index, onBack, editing }

  function openForm(def) {
    form = { title: def.title, items: def.items, index: 0, onBack: def.onBack, editing: false };
    for (var i = 0; i < form.items.length; i++) {
      if (isFocusable(form.items[i])) { form.index = i; break; }
    }
    if (def.focusId) {
      for (var j = 0; j < form.items.length; j++) if (form.items[j].id === def.focusId) form.index = j;
    }
    show('form');
    $('form-title').textContent = def.title;
    renderForm();
  }

  function isFocusable(it) { return it.type !== 'text'; }

  function renderForm() {
    var html = '';
    for (var i = 0; i < form.items.length; i++) {
      var it = form.items[i];
      var f = i === form.index ? ' focus' : '';
      if (it.type === 'text') html += '<div class="text">' + it.html + '</div>';
      else if (it.type === 'input') {
        html += '<div class="field' + f + '" data-i="' + i + '"><label>' + esc(it.label) + '</label>' +
          '<input id="in-' + i + '" type="' + (it.password ? 'password' : 'text') + '" value="' + esc(it.value || '') + '" placeholder="' + esc(it.placeholder || '') + '"></div>';
      } else {
        html += '<div class="' + (it.type === 'item' ? 'item' : 'btn') + f + '" data-i="' + i + '">' + esc(it.label) +
          (it.sub ? '<span class="sub' + (it.subErr ? ' err' : '') + '">' + esc(it.sub) + '</span>' : '') + '</div>';
      }
    }
    var el = $('form');
    el.innerHTML = html;
    scrollFormToFocus();
  }

  function scrollFormToFocus() {
    var el = $('form');
    var node = el.querySelector('[data-i="' + form.index + '"]');
    if (!node) return;
    var top = node.offsetTop - el.offsetTop;
    if (top + node.offsetHeight > el.scrollTop + el.clientHeight - 20) el.scrollTop = top + node.offsetHeight - el.clientHeight + 40;
    if (top < el.scrollTop + 20) el.scrollTop = Math.max(0, top - 120);
  }

  function readInputs() {
    for (var i = 0; i < form.items.length; i++) {
      var it = form.items[i];
      if (it.type === 'input') {
        var input = $('in-' + i);
        if (input) it.value = input.value;
      }
    }
  }

  function formValue(id) {
    readInputs();
    for (var i = 0; i < form.items.length; i++) if (form.items[i].id === id) return String(form.items[i].value || '').trim();
    return '';
  }

  function moveForm(delta) {
    var i = form.index;
    do {
      i += delta;
    } while (i >= 0 && i < form.items.length && !isFocusable(form.items[i]));
    if (i < 0 || i >= form.items.length) return;
    readInputs();
    var old = $('form').querySelector('.focus');
    if (old) old.classList.remove('focus');
    form.index = i;
    var node = $('form').querySelector('[data-i="' + i + '"]');
    if (node) node.classList.add('focus');
    scrollFormToFocus();
  }

  function stopEditing() {
    var input = $('in-' + form.index);
    form.editing = false;
    if (input) input.blur();
    readInputs();
  }

  function formKey(a, e) {
    if (form.editing) {
      // Mientras se escribe, el teclado de la tele recibe las teclas.
      var c = e.keyCode;
      if (c === KEY.DONE || c === KEY.CANCEL || c === KEY.ENTER || c === KEY.BACK || c === KEY.ESC) {
        e.preventDefault();
        stopEditing();
        if (c !== KEY.CANCEL && c !== KEY.BACK && c !== KEY.ESC) moveForm(1);
        return;
      }
      if (c === KEY.UP || c === KEY.DOWN) {
        // En el PC: salir del campo y moverse.
        e.preventDefault();
        stopEditing();
        moveForm(c === KEY.UP ? -1 : 1);
      }
      return;
    }
    if (a === 'up') return moveForm(-1);
    if (a === 'down') return moveForm(1);
    if (a === 'chup') return moveForm(-5);
    if (a === 'chdown') return moveForm(5);
    if (a === 'ok') {
      var it = form.items[form.index];
      if (!it) return;
      if (it.type === 'input') {
        var input = $('in-' + form.index);
        if (input) {
          form.editing = true;
          input.focus();
          try { input.setSelectionRange(input.value.length, input.value.length); } catch (err) { /* nada */ }
        }
        return;
      }
      if (it.action) it.action();
      return;
    }
    if (a === 'back') {
      if (form.onBack) return form.onBack();
      return goBrowse();
    }
  }

  function goBrowse() {
    form = null;
    show('browse');
    renderBrowse();
  }

  function openSearch() {
    openForm({
      title: 'Buscar canal',
      items: [
        { type: 'input', id: 'q', label: 'Nombre del canal (pulsa OK para escribir)', value: searchQuery, placeholder: 'Por ejemplo: noticias' },
        {
          type: 'button', label: 'Buscar', action: function () {
            searchQuery = formValue('q');
            form = null;
            show('browse');
            renderBrowse(searchQuery ? 'search' : 'all');
            setBrowseCol(1);
          }
        },
        { type: 'button', label: 'Cancelar', action: goBrowse }
      ]
    });
  }

  function sourceSub(s) {
    var t = s.type === 'xtream' ? 'Xtream Codes' : s.type === 'm3uFile' ? 'Archivo M3U' : 'Enlace M3U';
    var when = s.lastUpdated ? new Date(s.lastUpdated) : null;
    var txt = t + ' | ' + (s.channelCount || 0) + ' canales' +
      (when ? ' | actualizada ' + pad2(when.getDate()) + '/' + pad2(when.getMonth() + 1) + ' ' + hhmm(when) : '') +
      (s.enabled ? '' : ' | DESACTIVADA');
    return s.lastError ? txt + ' | Error: ' + s.lastError : txt;
  }

  function openSettings(focusId) {
    var items = [
      { type: 'button', id: 'add-m3u', label: '+  Añadir lista M3U (enlace)', action: function () { openAddM3u(); } },
      { type: 'button', id: 'add-xt', label: '+  Añadir Xtream Codes (servidor, usuario y contraseña)', action: function () { openAddXtream(); } },
      {
        type: 'item', id: 'sync', label: 'Sincronizar con Google Drive',
        sub: sync.connected() ? 'Conectado con ' + sync.account() : 'Recibe sola la configuración del móvil y del PC',
        action: function () { openSync(); }
      },
      { type: 'button', id: 'import', label: 'Importar la configuración del móvil o del PC', action: function () { openImport(); } },
      { type: 'button', id: 'refresh', label: 'Actualizar todas las listas ahora', action: function () { refreshAll(true); } },
      {
        type: 'item', id: 'hidden', label: 'Mostrar canales ocultos: ' + (store.settings.showHidden ? 'Sí' : 'No'),
        sub: 'Los canales y grupos que ocultaste en el móvil o el PC.',
        action: function () {
          store.settings.showHidden = !store.settings.showHidden;
          store.save();
          store.rebuild();
          openSettings('hidden');
        }
      },
      { type: 'text', html: '<b>Mis listas</b> (pulsa OK sobre una para actualizarla, desactivarla o borrarla)' }
    ];
    if (!store.sources.length) items.push({ type: 'text', html: 'Todavía no has añadido ninguna lista.' });
    store.sources.forEach(function (s) {
      items.push({ type: 'item', id: 'src-' + s.id, label: s.name, sub: sourceSub(s), subErr: !!s.lastError, action: function () { openSource(s); } });
    });
    items.push({
      type: 'text',
      html: 'Mi IPTV ' + VERSION + ' para Samsung TV.<br>Botones del mando: <b>rojo</b> favorito | <b>verde</b> buscar | <b>amarillo</b> actualizar (en un canal: idioma) | <b>azul</b> ajustes | <b>CH+ / CH-</b> cambiar de canal o pasar página.'
    });
    openForm({ title: 'Ajustes y listas', items: items, focusId: focusId, onBack: goBrowse });
  }

  function openSource(s) {
    openForm({
      title: s.name,
      items: [
        { type: 'text', html: esc(sourceSub(s)) },
        {
          type: 'button', label: 'Actualizar esta lista', action: function () {
            busy('Actualizando ' + s.name + '…');
            store.refreshSource(s).then(function (n) {
              store.rebuild();
              busy(null);
              toast(s.name + ': ' + n + ' canales');
              openSettings('src-' + s.id);
            }, function (err) {
              busy(null);
              toast('No se pudo actualizar: ' + err.message, 6000);
              openSettings('src-' + s.id);
            });
          }
        },
        {
          type: 'button', label: s.enabled ? 'Desactivar (ocultar sus canales)' : 'Activar', action: function () {
            s.enabled = !s.enabled;
            store.save();
            store.rebuild();
            openSettings('src-' + s.id);
          }
        },
        {
          type: 'button', label: 'Borrar esta lista', action: function () {
            openForm({
              title: '¿Borrar "' + s.name + '"?',
              items: [
                { type: 'text', html: 'Se quitará del televisor. Tus listas del móvil y del PC no cambian.' },
                { type: 'button', label: 'No, volver', action: function () { openSource(s); } },
                {
                  type: 'button', label: 'Sí, borrar', action: function () {
                    store.removeSource(s.id);
                    toast('Lista borrada');
                    openSettings();
                  }
                }
              ],
              onBack: function () { openSource(s); }
            });
          }
        },
        { type: 'button', label: 'Volver', action: function () { openSettings('src-' + s.id); } }
      ],
      onBack: function () { openSettings('src-' + s.id); }
    });
  }

  function addAndRefresh(src) {
    store.addSource(src);
    busy('Descargando canales de ' + src.name + '…');
    store.refreshSource(src).then(function (n) {
      store.rebuild();
      busy(null);
      toast('Lista añadida: ' + n + ' canales');
      goBrowse();
    }, function (err) {
      store.rebuild();
      busy(null);
      toast('Lista guardada, pero no se pudo descargar: ' + err.message, 7000);
      openSettings('src-' + src.id);
    });
  }

  function openAddM3u() {
    openForm({
      title: 'Añadir lista M3U',
      items: [
        { type: 'text', html: 'Ponte en cada casilla y pulsa <b>OK</b> para escribir con el teclado de la tele. Al terminar, pulsa <b>Hecho</b>.' },
        { type: 'input', id: 'name', label: 'Nombre de la lista', placeholder: 'Mi lista' },
        { type: 'input', id: 'url', label: 'Enlace M3U (http://…)', placeholder: 'http://…' },
        {
          type: 'button', label: 'Guardar y descargar canales', action: function () {
            var url = formValue('url');
            if (!/^https?:\/\//i.test(url)) return toast('El enlace debe empezar por http:// o https://');
            var x = P.extractXtreamFromUrl(url);
            if (x && /get\.php/i.test(url)) {
              // Enlace de Xtream: mejor usar su API (más rápido y con guía).
              return addAndRefresh({ name: formValue('name') || 'Xtream', type: 'xtream', server: x.server, username: x.username, password: x.password });
            }
            addAndRefresh({ name: formValue('name') || 'Lista M3U', type: 'm3uUrl', url: url });
          }
        },
        { type: 'button', label: 'Cancelar', action: function () { openSettings(); } }
      ],
      onBack: function () { openSettings(); }
    });
  }

  function openAddXtream() {
    openForm({
      title: 'Añadir Xtream Codes',
      items: [
        { type: 'text', html: 'Son los datos que te dio tu proveedor. Ponte en cada casilla y pulsa <b>OK</b> para escribir.' },
        { type: 'input', id: 'name', label: 'Nombre de la lista', placeholder: 'Mi proveedor' },
        { type: 'input', id: 'server', label: 'Servidor (con el puerto si lo tiene)', placeholder: 'http://servidor.com:8080' },
        { type: 'input', id: 'user', label: 'Usuario' },
        { type: 'input', id: 'pass', label: 'Contraseña', password: true },
        {
          type: 'button', label: 'Guardar y descargar canales', action: function () {
            var server = P.normalizeServer(formValue('server'));
            if (!server || !formValue('user')) return toast('Rellena al menos el servidor y el usuario');
            addAndRefresh({ name: formValue('name') || 'Xtream', type: 'xtream', server: server, username: formValue('user'), password: formValue('pass') });
          }
        },
        { type: 'button', label: 'Cancelar', action: function () { openSettings(); } }
      ],
      onBack: function () { openSettings(); }
    });
  }

  function openImport() {
    openForm({
      title: 'Importar configuración',
      items: [
        {
          type: 'text',
          html: 'Así pasas al televisor tus listas, favoritos, carpetas y nombres del móvil o del PC:<br>' +
            '1. En el móvil o el PC: <b>Ajustes > Exportar configuración</b>.<br>' +
            '2. Sube ese archivo a Google Drive y elige <b>Compartir > Cualquier persona con el enlace</b>. Copia el enlace.<br>' +
            '3. Escribe aquí ese enlace (o cualquier otro enlace directo al archivo).<br>' +
            '<b>Importante:</b> el archivo lleva tus contraseñas. Cuando termines, deja de compartirlo o bórralo de Drive.<br>' +
            'Se sustituirá la configuración que haya ahora en la tele.'
        },
        { type: 'input', id: 'url', label: 'Enlace al archivo de configuración', placeholder: 'https://drive.google.com/file/d/…' },
        {
          type: 'button', label: 'Importar', action: function () {
            var url = formValue('url');
            if (!/^https?:\/\//i.test(url)) return toast('El enlace debe empezar por http:// o https://');
            busy('Descargando configuración…');
            store.getText(directDownloadUrl(url), 60000).then(function (text) {
              store.importConfig(text);
              busy('Descargando canales…');
              return store.refreshAll();
            }).then(function (errors) {
              busy(null);
              toast(errors.length ? 'Importado, con avisos: ' + errors.join(' | ') : 'Configuración importada: ' + store.totalChannels() + ' canales', errors.length ? 8000 : 4000);
              goBrowse();
            }).catch(function (err) {
              busy(null);
              toast('No se pudo importar: ' + err.message + ' Revisa que el enlace sea público.', 8000);
            });
          }
        },
        { type: 'button', label: 'Cancelar', action: function () { openSettings(); } }
      ],
      onBack: function () { openSettings(); }
    });
  }

  // ------------------------------------------------------------ Google Drive

  function schedulePush() {
    if (!sync || !sync.connected() || pulling) return;
    clearTimeout(pushTimer);
    pushTimer = setTimeout(function () {
      sync.push().catch(function (err) { toast('No se pudo guardar en Drive: ' + err.message, 6000); });
    }, 20000);
  }

  /** Trae de Drive lo cambiado en el móvil o el PC y descarga los canales. */
  function pullFromDrive(force, quiet) {
    if (!sync.connected()) return Promise.resolve();
    pulling = true;
    return sync.pull(force).then(function (changed) {
      if (!changed) return;
      if (!quiet) busy('Descargando canales…');
      return store.refreshAll().then(function () {
        busy(null);
        if (screen === 'browse') renderBrowse();
        toast('Configuración actualizada desde Google Drive');
      });
    }).catch(function (err) {
      busy(null);
      if (!quiet) toast('Google Drive: ' + err.message, 6000);
    }).then(function () { pulling = false; });
  }

  function openSync() {
    var items = [{
      type: 'text',
      html: 'Tus listas, favoritos, carpetas y nombres se guardan en una carpeta privada de tu Google Drive ' +
        'y pasan solos entre el móvil, el ordenador y la tele. No aparece entre tus archivos.'
    }];
    if (sync.connected()) {
      items.push({ type: 'text', html: 'Conectado con <b>' + esc(sync.account()) + '</b>.' });
      items.push({
        type: 'button', label: 'Traer ahora la configuración de Drive', action: function () {
          busy('Leyendo Google Drive…');
          pullFromDrive(true).then(function () { busy(null); openSync(); });
        }
      });
      items.push({ type: 'button', label: 'Desconectar esta tele', action: function () { sync.signOut(); toast('Desconectada'); openSync(); } });
    } else if (!sync.hasClient()) {
      items.push({ type: 'text', html: 'Falta el permiso de Google. Escribe el ID y el secreto de cliente (los mismos que en el móvil).' });
      items.push({ type: 'input', id: 'cid', label: 'ID de cliente', value: '' });
      items.push({ type: 'input', id: 'csec', label: 'Secreto del cliente', value: '' });
      items.push({
        type: 'button', label: 'Guardar', action: function () {
          sync.setClient(formValue('cid'), formValue('csec'));
          openSync();
        }
      });
    } else {
      items.push({
        type: 'button', label: 'Conectar con Google Drive', action: function () {
          busy('Pidiendo un código a Google…');
          sync.startSignIn().then(function (code) {
            busy(null);
            var cancelled = false;
            openForm({
              title: 'Conectar con Google Drive',
              items: [
                {
                  type: 'text',
                  html: '1. En el móvil o el ordenador abre <b>' + esc(code.url) + '</b><br>' +
                    '2. Escribe este código y acepta el permiso:<br><span class="bigcode">' + esc(code.userCode) + '</span><br>' +
                    'Esperando…'
                },
                { type: 'button', label: 'Cancelar', action: function () { cancelled = true; openSync(); } }
              ],
              onBack: function () { cancelled = true; openSync(); }
            });
            return sync.waitForSignIn(code, function () { return cancelled; }).then(function (ok) {
              if (cancelled) return;
              if (!ok) { toast('El código ha caducado. Vuelve a intentarlo.'); return openSync(); }
              toast('Conectado. Trayendo tu configuración…');
              return pullFromDrive(true).then(function () { goBrowse(); });
            });
          }).catch(function (err) {
            busy(null);
            toast(err.message, 6000);
            openSync();
          });
        }
      });
    }
    items.push({ type: 'button', label: 'Volver', action: function () { openSettings('sync'); } });
    openForm({ title: 'Google Drive', items: items, onBack: function () { openSettings('sync'); } });
  }

  // ------------------------------------------------------------ General

  function refreshAll(showBusy) {
    if (!store.sources.length) {
      toast('Primero añade una lista en Ajustes y listas');
      return Promise.resolve();
    }
    if (showBusy) busy('Actualizando listas…');
    return store.refreshAll().then(function (errors) {
      busy(null);
      if (showBusy || errors.length) {
        toast(errors.length ? 'Avisos: ' + errors.join(' | ') : 'Listas actualizadas: ' + store.totalChannels() + ' canales', errors.length ? 7000 : 3500);
      }
      if (screen === 'browse') renderBrowse();
      else if (screen === 'form' && form && form.title === 'Ajustes y listas') openSettings('refresh');
    });
  }

  function exitApp() {
    try { player.stop(); } catch (e) { /* nada */ }
    try {
      root.tizen.application.getCurrentApplication().exit();
    } catch (e2) {
      toast('Para salir, pulsa el botón de inicio del mando');
    }
  }

  function tickClock() {
    var t = hhmm(new Date());
    $('clock').textContent = t;
  }

  function onKey(e) {
    var a = actionOf(e);
    if (screen === 'form') {
      if (form && form.editing) return formKey(a, e);
      if (a) e.preventDefault();
      return formKey(a, e);
    }
    if (!a) return;
    e.preventDefault();
    if (!$('busy').classList.contains('hidden')) return; // esperando
    if (screen === 'browse') browseKey(a);
    else if (screen === 'player') playerKey(a);
  }

  function needsRefresh() {
    if (!store.sources.length) return false;
    if (!store.totalChannels()) return true;
    var h = store.settings.autoRefreshHours || 0;
    if (!h) return false;
    var last = store.settings.lastRefresh ? Date.parse(store.settings.lastRefresh) : 0;
    return Date.now() - last > h * 3600 * 1000;
  }

  function init() {
    registerTvKeys();
    store.load();
    sync = new root.MiSync(store);
    // Cada cambio hecho en la tele se sube a Drive (si está conectada).
    var origSave = store.save;
    store.save = function () {
      origSave.call(store);
      schedulePush();
    };
    catList = new VList($('cats'), catRow);
    chanList = new VList($('chans'), channelRow);
    sideList = new VList($('side-list'), channelRow);
    trackList = new VList($('side-list'), trackRow);
    player = new root.MiPlayer({
      objectEl: $('av-player'),
      videoEl: $('html-player'),
      onState: onPlayerState,
      onError: onPlayerError,
      onSubtitle: showSubtitle,
      preferredAudio: function () { return store.settings.audioLanguage || ''; }
    });
    document.addEventListener('keydown', onKey);
    document.addEventListener('visibilitychange', function () {
      if (document.hidden) player.suspend();
      else player.restore();
    });
    tickClock();
    setInterval(tickClock, 15000);
    show('browse');
    renderBrowse();

    if (!store.sources.length) {
      openSettings();
      toast('¡Bienvenido! Añade una lista o importa la configuración del móvil.', 6000);
    } else if (needsRefresh()) {
      refreshAll(!store.totalChannels());
    }
    // Actualización automática mientras la app está abierta.
    setInterval(function () {
      if (screen !== 'form' && needsRefresh()) refreshAll(false);
    }, 30 * 60 * 1000);
    // Cambios hechos en el móvil o el PC (Google Drive).
    if (sync.connected()) pullFromDrive(false, !!store.sources.length);
    setInterval(function () {
      if (screen !== 'form') pullFromDrive(false, true);
    }, 15 * 60 * 1000);
  }

  root.MiApp = { store: store, directDownloadUrl: directDownloadUrl };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})(this);
