// Pruebas de la versión para Samsung TV. Se ejecutan con: node --test tizen/test
'use strict';
var test = require('node:test');
var assert = require('node:assert');
var P = require('../js/parsers.js');
var Store = require('../js/store.js');

var M3U = '#EXTM3U url-tvg="http://epg.example/guia.xml.gz"\n' +
  '#EXTINF:-1 tvg-id="La1.es" tvg-name="La 1" tvg-logo="http://logo/la1.png" group-title="ES | Generalistas",La 1 HD\n' +
  'http://example.com/la1.m3u8\n' +
  '#EXTINF:-1 tvg-id="CNN.us" group-title="News, World",CNN, International\n' +
  '#EXTVLCOPT:http-user-agent=MiAgente/1.0\n' +
  'http://example.com/cnn.ts\n' +
  '#EXTINF:-1,Sin grupo\n' +
  '#EXTGRP:Radio\n' +
  'http://example.com/radio\n' +
  '#EXTINF:-1 group-title="ES | Generalistas",La 1 HD\n' +
  'http://example.com/la1-backup.m3u8\n';

test('Lee una lista M3U igual que la app del móvil', function () {
  var p = P.parseM3u(M3U, 'src');
  assert.strictEqual(p.epgUrl, 'http://epg.example/guia.xml.gz');
  assert.strictEqual(p.channels.length, 4);
  var la1 = p.channels[0];
  assert.strictEqual(la1.n, 'La 1 HD');
  assert.strictEqual(la1.g, 'ES | Generalistas');
  assert.strictEqual(la1.i, 'La1.es');
  assert.strictEqual(la1.l, 'http://logo/la1.png');
  assert.strictEqual(la1.k, 'src|ES | Generalistas|La 1 HD');
  assert.strictEqual(p.channels[1].n, 'CNN, International');
  assert.strictEqual(p.channels[1].a, 'MiAgente/1.0');
  assert.strictEqual(p.channels[2].g, 'Radio');
  assert.strictEqual(p.channels[3].k, 'src|ES | Generalistas|La 1 HD#2');
});

test('Lee respuestas de Xtream Codes', function () {
  var list = P.parseXtream({
    categories: '[{"category_id":"1","category_name":"USA News"}]',
    streams: '[{"name":"CNN","stream_id":55,"stream_icon":"","epg_channel_id":"cnn.us","category_id":"1"}]',
    sourceId: 'x', server: 'http://srv:8080', username: 'yo', password: 'clave', output: 'ts'
  });
  assert.strictEqual(list.length, 1);
  assert.strictEqual(list[0].u, 'http://srv:8080/live/yo/clave/55.ts');
  assert.strictEqual(list[0].g, 'USA News');
  assert.strictEqual(list[0].x, '55');
  assert.strictEqual(P.normalizeServer('srv.com:8080/'), 'http://srv.com:8080');
  assert.deepStrictEqual(P.extractXtreamFromUrl('http://srv.com:8080/get.php?username=a&password=b&type=m3u_plus'),
    { server: 'http://srv.com:8080', username: 'a', password: 'b' });
  assert.throws(function () {
    P.parseXtream({ categories: '[]', streams: '{"user_info":{"auth":0}}', sourceId: 'x', server: 's', username: 'u', password: 'p' });
  });
});

test('Quita tildes y decodifica la guía de Xtream', function () {
  assert.strictEqual(P.normalizeText('Fútbol ESPAÑA'), 'futbol espana');
  assert.strictEqual(P.decodeBase64Utf8(Buffer.from('Telediario y más', 'utf8').toString('base64')), 'Telediario y más');
});

function fakeStore(files) {
  return new Store({
    storage: Store.memoryStorage(),
    getText: function (url) {
      if (files[url] == null) return Promise.reject(new Error('404 ' + url));
      return Promise.resolve(files[url]);
    }
  });
}

test('Importa la configuración exportada del móvil y respeta favoritos, ocultos y orden', function () {
  var files = { 'http://lista/a.m3u': M3U };
  var s = fakeStore(files);
  s.importConfig(JSON.stringify({
    app: 'mi-iptv', version: 1,
    settings: { showHidden: false, lastChannelKey: '' },
    custom: {
      channelNames: { 'src|ES | Generalistas|La 1 HD': 'La Uno' },
      hiddenChannels: ['src|ES | Generalistas|La 1 HD#2'],
      groupNames: { Radio: 'Radios' },
      hiddenGroups: [],
      groupOrder: ['Radio'],
      channelOrder: {},
      favorites: ['src|News, World|CNN, International'],
      folders: [{ id: 'f1', name: 'Noticias', channels: ['src|News, World|CNN, International'] }]
    },
    sources: [{ id: 'src', name: 'Mi lista', type: 'm3uUrl', url: 'http://lista/a.m3u', enabled: true }],
    files: {}
  }));
  return s.refreshAll().then(function (errors) {
    assert.deepStrictEqual(errors, []);
    var groups = s.groups();
    assert.strictEqual(groups[0].name, 'Radios');
    assert.strictEqual(groups.length, 3);
    var es = s.channelsInGroup('ES | Generalistas');
    assert.strictEqual(es.length, 1, 'el canal oculto no aparece');
    assert.strictEqual(s.channelName(es[0]), 'La Uno');
    assert.strictEqual(s.favoriteChannels()[0].n, 'CNN, International');
    assert.strictEqual(s.folderChannels('f1').length, 1);
    assert.strictEqual(s.search('uno').length, 1);
    s.settings.showHidden = true;
    assert.strictEqual(s.channelsInGroup('ES | Generalistas').length, 2);
    // Se conserva al volver a abrir la app.
    var s2 = new Store({ storage: s.storage, getText: s.getText });
    s2.load();
    assert.strictEqual(s2.favoriteChannels().length, 1);
    assert.strictEqual(s2.totalChannels(), 4);
  });
});

test('Las listas que eran archivos del móvil se leen del archivo exportado', function () {
  var s = fakeStore({});
  s.importConfig({
    app: 'mi-iptv',
    sources: [{ id: 'f', name: 'Archivo', type: 'm3uFile' }],
    files: { f: M3U }
  });
  return s.refreshAll().then(function (errors) {
    assert.deepStrictEqual(errors, []);
    assert.strictEqual(s.totalChannels(), 4);
  });
});

test('Avisa de errores sin romper las demás listas', function () {
  var s = fakeStore({ 'http://ok/a.m3u': M3U });
  s.addSource({ name: 'Buena', type: 'm3uUrl', url: 'http://ok/a.m3u' });
  s.addSource({ name: 'Rota', type: 'm3uUrl', url: 'http://mal/b.m3u' });
  return s.refreshAll().then(function (errors) {
    assert.strictEqual(errors.length, 1);
    assert.ok(/^Rota:/.test(errors[0]));
    assert.strictEqual(s.totalChannels(), 4);
  });
});

test('Rechaza archivos que no son de Mi IPTV', function () {
  var s = fakeStore({});
  assert.throws(function () { s.importConfig('{"hola":1}'); }, /no es una configuración/);
  assert.throws(function () { s.importConfig('no es json'); }, /no es una configuración/);
});

test('Separa canales, películas y series y crea las carpetas de fútbol y TDT', function () {
  var m3u = '#EXTM3U\n' +
    '#EXTINF:-1 group-title="ES | Generalistas",La 1 HD\nhttp://srv.com/live/u/p/1.ts\n' +
    '#EXTINF:-1 group-title="ES | Deportes",M+ LaLiga FHD\nhttp://srv.com/u/p/2\n' +
    '#EXTINF:-1 group-title="ES | Deportes",DAZN F1\nhttp://srv.com/u/p/3\n' +
    '#EXTINF:-1 group-title="VOD | Acción",Gladiator (2000)\nhttp://srv.com/movie/u/p/4.mkv\n' +
    '#EXTINF:-1 group-title="Series | Drama",Breaking Bad S01E02\nhttp://srv.com/series/u/p/5.mkv\n' +
    '#EXTINF:-1 group-title="Series | Drama",Breaking Bad S01E01\nhttp://srv.com/series/u/p/6.mkv\n' +
    '#EXTINF:-1 group-title="Series | Drama",Breaking Bad S02E01\nhttp://srv.com/series/u/p/7.mkv\n';
  var ch = P.parseM3u(m3u, 's').channels;
  assert.deepStrictEqual(ch.map(function (c) { return c.v || 'l'; }), ['l', 'l', 'l', 'm', 's', 's', 's']);
  assert.strictEqual(ch[4].sn, 'Breaking Bad');
  assert.strictEqual(ch[4].se, 1);
  assert.strictEqual(ch[4].ep, 2);

  var s = fakeStore({ 'http://lista/v.m3u': m3u });
  var src = s.addSource({ name: 'L', type: 'm3uUrl', url: 'http://lista/v.m3u' });
  src.id = 's';
  s.channelsBySource.s = ch;
  s.rebuild();
  assert.strictEqual(s.totalChannels(), 3);
  assert.strictEqual(s.movieCount, 1);
  assert.strictEqual(s.seriesCount, 1);
  assert.strictEqual(s.movieGroups()[0].name, 'VOD | Acción');
  var info = s.seriesInGroup('Series | Drama')[0];
  var seasons = s.seasonsOf(info);
  assert.strictEqual(seasons.length, 2);
  assert.strictEqual(seasons[0].episodes[0].ep, 1);
  var smart = s.smartFolders();
  assert.deepStrictEqual(smart[0].channels.map(function (c) { return c.n; }), ['M+ LaLiga FHD']);
  assert.deepStrictEqual(smart[1].channels.map(function (c) { return c.n; }), ['La 1 HD']);
});

test('Lee películas y series de Xtream', function () {
  var vod = P.parseXtreamVod({
    categories: '[{"category_id":"7","category_name":"Estrenos"}]',
    streams: '[{"stream_id":9,"name":"Dune","category_id":"7","container_extension":"mkv"}]',
    sourceId: 'x', server: 'http://srv:80', username: 'yo', password: 'clave'
  });
  assert.strictEqual(vod[0].u, 'http://srv:80/movie/yo/clave/9.mkv');
  var series = P.parseXtreamSeries({
    categories: '[{"category_id":"3","category_name":"Drama"}]',
    series: '[{"series_id":12,"name":"The Wire","category_id":"3"}]',
    sourceId: 'x'
  });
  assert.strictEqual(series[0].xs, '12');
  var eps = P.parseXtreamSeriesInfo('{"episodes":{"2":[{"id":"101","episode_num":1,"season":2}],"1":[{"id":"100","episode_num":"1","container_extension":"mkv"}]}}',
    series[0], 'http://srv:80', 'yo', 'clave');
  assert.strictEqual(eps.length, 2);
  assert.strictEqual(eps[0].se, 1);
  assert.strictEqual(eps[0].u, 'http://srv:80/series/yo/clave/100.mkv');
  assert.strictEqual(P.isTdtChannel('|ES| Antena 3 FHD'), true);
  assert.strictEqual(P.isTdtChannel('Antena 3 Internacional'), false);
  assert.strictEqual(P.isFootballChannel('Movistar Liga de Campeones 1'), true);
  assert.strictEqual(P.isFootballChannel('Movistar Golf'), false);
});
