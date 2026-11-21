// Pruebas de la sincronización de la tele: node --test tizen/test/sync.test.js
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const Sync = require('../js/sync.js');

test('al subir desde la tele no se pierde lo que la tele no maneja', () => {
  const remote = {
    app: 'mi-iptv',
    settings: { themeMode: 'dark', epgUrls: ['http://guia.xml'], showHidden: false, audioLanguage: '' },
    custom: { favorites: ['a'] },
    sources: [
      { id: '1', name: 'Lista', type: 'xtream', server: 'http://s', username: 'u', password: 'p', epgUrl: 'http://extra.xml' },
      { id: '2', name: 'Borrada', type: 'm3uFile' }
    ],
    files: { '2': '#EXTM3U' },
    updatedAt: 'x'
  };
  const tv = {
    settings: { showHidden: true, audioLanguage: 'es', lastChannelKey: 'k' },
    custom: { favorites: ['a', 'b'] },
    sources: [{ id: '1', name: 'Mi lista', type: 'xtream', server: 'http://s', username: 'u', password: 'p', lastUpdated: 'hoy', channelCount: 9 }]
  };
  const out = Sync.mergeForUpload(remote, tv);
  assert.strictEqual(out.settings.themeMode, 'dark');
  assert.deepStrictEqual(out.settings.epgUrls, ['http://guia.xml']);
  assert.strictEqual(out.settings.showHidden, true);
  assert.strictEqual(out.settings.audioLanguage, 'es');
  assert.strictEqual(out.settings.lastChannelKey, undefined);
  assert.deepStrictEqual(out.custom.favorites, ['a', 'b']);
  assert.strictEqual(out.sources.length, 1);
  assert.strictEqual(out.sources[0].name, 'Mi lista');
  assert.strictEqual(out.sources[0].epgUrl, 'http://extra.xml');
  assert.strictEqual(out.sources[0].lastUpdated, undefined);
  assert.strictEqual(out.sources[0].channelCount, undefined);
  assert.deepStrictEqual(out.files, {});
  // No modifica el original.
  assert.strictEqual(remote.sources.length, 2);
});
