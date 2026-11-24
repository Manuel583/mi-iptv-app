// Prueba de rendimiento de la versión para Samsung TV con una lista enorme.
// Se ejecuta con: node --test tizen/test/rendimiento.test.js
'use strict';
var test = require('node:test');
var assert = require('node:assert');
var Store = require('../js/store.js');

var WORDS = ['Deportes', 'Noticias', 'Cine', 'Música', 'Infantil', 'Documentales', 'Fútbol', 'Series', 'Cocina', 'Viajes'];

function bigStore() {
  var list = [];
  for (var i = 0; i < 60000; i++) {
    var g = 'ES | ' + WORDS[i % WORDS.length] + ' ' + (i % 300);
    list.push({ k: 'big|' + g + '|' + i, s: 'big', n: 'Canal ' + WORDS[(i / 7 | 0) % WORDS.length] + ' ' + i + ' HD', u: 'http://e/' + i, g: g });
  }
  for (var m = 0; m < 40000; m++) {
    var mg = 'Películas ' + (m % 150);
    list.push({ k: 'big|' + mg + '|' + m, s: 'big', n: 'Película número ' + m, u: 'http://e/m' + m, g: mg, v: 'm' });
  }
  var st = new Store({ storage: Store.memoryStorage() });
  st.sources = [{ id: 'big', name: 'Enorme', type: 'm3uUrl', enabled: true }];
  st.channelsBySource.big = list;
  st.custom.hiddenChannels = list.slice(0, 2000).map(function (c) { return c.k; });
  st.rebuild();
  return st;
}

function ms(f) {
  var t = Date.now();
  f();
  return Date.now() - t;
}

test('La tele va fluida con 100.000 canales y películas', function () {
  var st = bigStore();
  var first = ms(function () { st.search('deportes 12'); });
  var again = ms(function () { for (var i = 0; i < 5; i++) st.search('pelicula 99'); });
  var all = ms(function () { st.allChannels(); st.groups(); });
  console.log('Rendimiento TV | primera búsqueda: ' + first + ' ms | 5 búsquedas más: ' + again +
    ' ms | lista "Todos" y grupos: ' + all + ' ms');
  assert.ok(st.search('pelicula 99').length > 0);
  assert.ok(st.search('canal deportes').every(function (c) { return st.custom.hiddenChannels.indexOf(c.k) < 0; }));
  assert.ok(again < 1000);
  assert.ok(all < 1000);
});
