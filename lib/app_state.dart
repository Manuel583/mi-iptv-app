// Estado central de la aplicación.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';

import 'country.dart';
import 'epg.dart';
import 'models.dart';
import 'parsers.dart';

const defaultUserAgent = 'VLC/3.0.20 LibVLC/3.0.20';

class GroupInfo {
  GroupInfo(this.key, this.name, this.hidden, this.count);
  final String key;
  final String name;
  final bool hidden;
  final int count;
}

class AppController extends ChangeNotifier {
  AppController._();
  static final AppController instance = AppController._();

  late Directory _dir;
  bool _dirReady = false;
  bool loaded = false;

  AppSettings settings = AppSettings();
  Customization custom = Customization();
  final List<PlaylistSource> sources = [];

  /// Canales por lista (id de lista -> canales).
  final Map<String, List<Channel>> _channelsBySource = {};

  // Índices calculados.
  List<Channel> allChannels = [];
  Map<String, Channel> byKey = {};
  List<String> _groupKeys = [];
  Map<String, List<Channel>> _groupChannels = {};
  Map<String, List<Channel>> _countryChannels = {};
  List<String> _countryKeys = [];

  EpgData epg = EpgData.empty();
  final Map<String, List<Programme>?> _epgCache = {};

  bool refreshing = false;
  String refreshStatus = '';
  bool epgLoading = false;
  Timer? _autoTimer;

  /// Versión que aumenta con cada cambio (para refrescar listas en pantalla).
  int revision = 0;

  late final http.Client _http = IOClient(
    HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..badCertificateCallback = (_, _, _) => true,
  );

  String get effectiveUserAgent =>
      settings.userAgent.trim().isEmpty ? defaultUserAgent : settings.userAgent;

  // ---------------------------------------------------------------- Carga

  Future<void> load() async {
    _dir = await getApplicationSupportDirectory();
    _dirReady = true;
    await Directory('${_dir.path}/channels').create(recursive: true);
    await Directory('${_dir.path}/files').create(recursive: true);
    await Directory('${_dir.path}/epg').create(recursive: true);
    final f = File('${_dir.path}/config.json');
    if (await f.exists()) {
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        _applyConfig(j);
      } catch (e) {
        debugPrint('Error leyendo configuración: $e');
      }
    }
    for (final s in sources) {
      await _loadChannelCache(s);
    }
    _rebuildIndex();
    loaded = true;
    notifyListeners();
    unawaited(_loadEpgCache());
    _startAutoRefresh();
  }

  void _applyConfig(Map<String, dynamic> j) {
    lastUserChange = DateTime.tryParse('${j['lastUserChange'] ?? ''}');
    settings = AppSettings.fromJson(
      (j['settings'] as Map?)?.cast<String, dynamic>(),
    );
    custom = Customization.fromJson(
      (j['custom'] as Map?)?.cast<String, dynamic>(),
    );
    sources
      ..clear()
      ..addAll(
        ((j['sources'] ?? const []) as List).map(
          (e) => PlaylistSource.fromJson(Map<String, dynamic>.from(e as Map)),
        ),
      );
  }

  Map<String, dynamic> _configJson() => {
    'app': 'mi-iptv',
    'version': 1,
    'lastUserChange': lastUserChange?.toIso8601String(),
    'settings': settings.toJson(),
    'custom': custom.toJson(),
    'sources': sources.map((s) => s.toJson()).toList(),
  };

  Timer? _saveTimer;
  void save() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _saveNow);
  }

  Future<void> _saveNow() async {
    if (!_dirReady) return;
    try {
      final f = File('${_dir.path}/config.json');
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(_configJson()));
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('Error guardando: $e');
    }
  }

  /// Se llama cuando el usuario cambia algo (para sincronizar).
  VoidCallback? onUserChange;
  DateTime? lastUserChange;

  void changed({bool reindex = false, bool user = true}) {
    if (reindex) _rebuildIndex();
    revision++;
    save();
    notifyListeners();
    if (user) {
      lastUserChange = DateTime.now();
      onUserChange?.call();
    }
  }

  Future<void> _loadChannelCache(PlaylistSource s) async {
    final f = File('${_dir.path}/channels/${s.id}.json');
    if (!await f.exists()) return;
    try {
      final text = await f.readAsString();
      final list = await compute(_decodeChannels, text);
      _channelsBySource[s.id] = list;
    } catch (e) {
      debugPrint('Caché dañada de ${s.name}: $e');
    }
  }

  /// Sólo para pruebas: carga canales sin tocar el disco.
  @visibleForTesting
  void debugSetData(PlaylistSource s, List<Channel> channels) {
    sources
      ..clear()
      ..add(s);
    _channelsBySource
      ..clear()
      ..[s.id] = channels;
    s.channelCount = channels.length;
    _rebuildIndex();
    loaded = true;
    notifyListeners();
  }

  // ---------------------------------------------------------------- Índices

  void _rebuildIndex() {
    final all = <Channel>[];
    for (final s in sources) {
      if (!s.enabled) continue;
      all.addAll(_channelsBySource[s.id] ?? const []);
    }
    allChannels = all;
    byKey = {for (final c in all) c.key: c};

    final natural = <String>[];
    final groups = <String, List<Channel>>{};
    final countries = <String, List<Channel>>{};
    for (final c in all) {
      final g = groups[c.group];
      if (g == null) {
        natural.add(c.group);
        groups[c.group] = [c];
      } else {
        g.add(c);
      }
      (countries[c.country.isEmpty ? noCountry : c.country] ??= []).add(c);
    }
    final orderSet = custom.groupOrder.toSet();
    _groupKeys = [
      ...custom.groupOrder.where(groups.containsKey),
      ...natural.where((g) => !orderSet.contains(g)),
    ];
    groups.forEach((g, list) {
      final order = custom.channelOrder[g];
      if (order != null && order.isNotEmpty) {
        final pos = <String, int>{};
        for (var i = 0; i < order.length; i++) {
          pos[order[i]] = i;
        }
        final indexed = list.asMap().entries.toList();
        indexed.sort((a, b) {
          final pa = pos[a.value.key] ?? (1 << 30) + a.key;
          final pb = pos[b.value.key] ?? (1 << 30) + b.key;
          return pa.compareTo(pb);
        });
        groups[g] = indexed.map((e) => e.value).toList();
      }
    });
    _groupChannels = groups;

    // Los canales de cada país siguen el orden de los grupos.
    final groupPos = <String, int>{};
    for (var i = 0; i < _groupKeys.length; i++) {
      groupPos[_groupKeys[i]] = i;
    }
    final chanPos = <String, int>{};
    for (final g in _groupKeys) {
      final l = groups[g]!;
      for (var i = 0; i < l.length; i++) {
        chanPos[l[i].key] = i;
      }
    }
    countries.forEach((k, list) {
      list.sort((a, b) {
        final c = (groupPos[a.group] ?? 0).compareTo(groupPos[b.group] ?? 0);
        if (c != 0) return c;
        return (chanPos[a.key] ?? 0).compareTo(chanPos[b.key] ?? 0);
      });
    });
    _countryChannels = countries;
    _countryKeys = countries.keys.toList()
      ..sort((a, b) {
        if (a == noCountry) return 1;
        if (b == noCountry) return -1;
        return normalizeText(a).compareTo(normalizeText(b));
      });
    _epgCache.clear();
    revision++;
  }

  // ---------------------------------------------------------------- Consultas

  String channelName(Channel c) => custom.channelNames[c.key] ?? c.name;

  String groupName(String g) =>
      custom.groupNames[g] ?? (g.isEmpty ? 'Sin grupo' : g);

  bool isHidden(Channel c) =>
      custom.hiddenChannels.contains(c.key) ||
      custom.hiddenGroups.contains(c.group);

  bool isFavorite(Channel c) => custom.favorites.contains(c.key);

  /// Grupos en orden. Con [includeHidden] también los ocultos.
  List<GroupInfo> groups({bool includeHidden = false}) {
    final show = includeHidden || settings.showHidden;
    final out = <GroupInfo>[];
    for (final g in _groupKeys) {
      final hidden = custom.hiddenGroups.contains(g);
      if (hidden && !show) continue;
      final count = _groupChannels[g]!
          .where((c) => show || !custom.hiddenChannels.contains(c.key))
          .length;
      out.add(GroupInfo(g, groupName(g), hidden, count));
    }
    return out;
  }

  List<Channel> channelsInGroup(String g, {bool includeHidden = false}) {
    final show = includeHidden || settings.showHidden;
    final list = _groupChannels[g] ?? const [];
    if (show) return list;
    return list.where((c) => !custom.hiddenChannels.contains(c.key)).toList();
  }

  List<GroupInfo> countries() {
    final out = <GroupInfo>[];
    for (final k in _countryKeys) {
      final n = channelsInCountry(k).length;
      if (n > 0) out.add(GroupInfo(k, k, false, n));
    }
    return out;
  }

  List<Channel> channelsInCountry(String country) {
    final list = _countryChannels[country] ?? const [];
    if (settings.showHidden) return list;
    return list.where((c) => !isHidden(c)).toList();
  }

  List<Channel> favoriteChannels() => [
    for (final k in custom.favorites)
      if (byKey[k] != null) byKey[k]!,
  ];

  List<Channel> folderChannels(Folder f) => [
    for (final k in f.channelKeys)
      if (byKey[k] != null) byKey[k]!,
  ];

  List<Channel> search(String query, {int limit = 500}) {
    final q = normalizeText(query.trim());
    if (q.isEmpty) return const [];
    final words = q.split(RegExp(r'\s+'));
    final out = <Channel>[];
    for (final c in allChannels) {
      if (!settings.showHidden && isHidden(c)) continue;
      final hay = normalizeText('${channelName(c)} ${groupName(c.group)}');
      if (words.every(hay.contains)) {
        out.add(c);
        if (out.length >= limit) break;
      }
    }
    return out;
  }

  /// Programación del canal (o null si no hay guía).
  List<Programme>? programmesFor(Channel c) {
    if (_epgCache.containsKey(c.key)) return _epgCache[c.key];
    final p = epg.lookup(c) ?? _xtreamEpg[c.key];
    _epgCache[c.key] = p;
    return p;
  }

  // Guía pedida canal a canal al servidor Xtream, para los canales que no
  // aparecen en la guía completa (xmltv.php).
  final Map<String, List<Programme>> _xtreamEpg = {};
  final Set<String> _xtreamAsked = {};
  int _xtreamRunning = 0;
  final List<Channel> _xtreamQueue = [];

  /// Si el canal no tiene guía y es de una lista Xtream, la pide al servidor.
  void requestProgrammes(Channel c) {
    if (epgLoading || !_xtreamAsked.add(c.key)) return;
    final p = programmesFor(c);
    if (p != null && p.isNotEmpty) return;
    final s = sources.where((s) => s.id == c.sourceId).firstOrNull;
    if (s == null || s.type != SourceType.xtream || !s.useIncludedEpg) return;
    _xtreamQueue.add(c);
    _pumpXtream();
  }

  void _pumpXtream() {
    while (_xtreamRunning < 3 && _xtreamQueue.isNotEmpty) {
      final c = _xtreamQueue.removeLast();
      _xtreamRunning++;
      _fetchXtreamEpg(c).whenComplete(() {
        _xtreamRunning--;
        _pumpXtream();
      });
    }
  }

  Future<void> _fetchXtreamEpg(Channel c) async {
    final s = sources.where((s) => s.id == c.sourceId).firstOrNull;
    final id = xtreamStreamId(c.url);
    if (s == null || id == null) return;
    final base =
        '${s.server}/player_api.php?username=${Uri.encodeQueryComponent(s.username)}&password=${Uri.encodeQueryComponent(s.password)}';
    for (final action in [
      'get_simple_data_table&stream_id=$id',
      'get_short_epg&stream_id=$id&limit=50',
    ]) {
      try {
        final text = await _getText('$base&action=$action');
        final list = parseXtreamEpg(text);
        if (list.isNotEmpty) {
          _xtreamEpg[c.key] = list;
          _epgCache.remove(c.key);
          revision++;
          notifyListeners();
          return;
        }
      } catch (e) {
        debugPrint('Guía Xtream de ${c.name}: $e');
      }
    }
  }

  (Programme?, Programme?) nowNext(Channel c) =>
      nowAndNext(programmesFor(c), DateTime.now());

  // ---------------------------------------------------------------- Edición

  void toggleFavorite(Channel c) {
    if (!custom.favorites.remove(c.key)) custom.favorites.add(c.key);
    changed();
  }

  void reorderFavorites(int oldIndex, int newIndex) {
    final visible = favoriteChannels().map((c) => c.key).toList();
    _reorder(visible, oldIndex, newIndex);
    custom.favorites = [
      ...visible,
      ...custom.favorites.where((k) => !visible.contains(k)),
    ];
    changed();
  }

  void renameChannel(Channel c, String? name) {
    if (name == null || name.trim().isEmpty || name.trim() == c.name) {
      custom.channelNames.remove(c.key);
    } else {
      custom.channelNames[c.key] = name.trim();
    }
    changed();
  }

  void setChannelHidden(Channel c, bool hidden) {
    if (hidden) {
      custom.hiddenChannels.add(c.key);
    } else {
      custom.hiddenChannels.remove(c.key);
    }
    changed();
  }

  void renameGroup(String g, String? name) {
    if (name == null || name.trim().isEmpty || name.trim() == g) {
      custom.groupNames.remove(g);
    } else {
      custom.groupNames[g] = name.trim();
    }
    changed();
  }

  void setGroupHidden(String g, bool hidden) {
    if (hidden) {
      custom.hiddenGroups.add(g);
    } else {
      custom.hiddenGroups.remove(g);
    }
    changed();
  }

  void reorderGroups(int oldIndex, int newIndex) {
    final keys = List<String>.from(_groupKeys);
    _reorder(keys, oldIndex, newIndex);
    custom.groupOrder = keys;
    changed(reindex: true);
  }

  void reorderChannelsInGroup(String g, int oldIndex, int newIndex) {
    final keys = (_groupChannels[g] ?? const []).map((c) => c.key).toList();
    _reorder(keys, oldIndex, newIndex);
    custom.channelOrder[g] = keys;
    changed(reindex: true);
  }

  void resetGroupOrder() {
    custom.groupOrder = [];
    custom.channelOrder = {};
    changed(reindex: true);
  }

  Folder createFolder(String name) {
    final f = Folder(id: _newId(), name: name.trim());
    custom.folders.add(f);
    changed();
    return f;
  }

  void renameFolder(Folder f, String name) {
    f.name = name.trim();
    changed();
  }

  void deleteFolder(Folder f) {
    custom.folders.remove(f);
    changed();
  }

  void reorderFolders(int oldIndex, int newIndex) {
    _reorder(custom.folders, oldIndex, newIndex);
    changed();
  }

  void addToFolder(Folder f, Channel c) {
    if (!f.channelKeys.contains(c.key)) f.channelKeys.add(c.key);
    changed();
  }

  void removeFromFolder(Folder f, Channel c) {
    f.channelKeys.remove(c.key);
    changed();
  }

  void reorderFolderChannels(Folder f, int oldIndex, int newIndex) {
    final visible = folderChannels(f).map((c) => c.key).toList();
    _reorder(visible, oldIndex, newIndex);
    final rest = f.channelKeys.where((k) => !visible.contains(k)).toList();
    f.channelKeys
      ..clear()
      ..addAll([...visible, ...rest]);
    changed();
  }

  static void _reorder<T>(List<T> list, int oldIndex, int newIndex) {
    // newIndex ya viene ajustado (onReorderItem).
    if (oldIndex < 0 || oldIndex >= list.length) return;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex.clamp(0, list.length), item);
  }

  String _newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
      (allChannels.length % 1000).toString();

  // ---------------------------------------------------------------- Listas

  Future<String?> addSource(PlaylistSource s, {String? fileContent}) async {
    sources.add(s);
    if (fileContent != null) {
      await File('${_dir.path}/files/${s.id}.m3u').writeAsString(fileContent);
    }
    changed();
    final err = await refreshSource(s);
    unawaited(refreshEpg());
    return err;
  }

  PlaylistSource newSource(String name, SourceType type) =>
      PlaylistSource(id: _newId(), name: name, type: type);

  Future<void> updateSource(PlaylistSource s, {String? fileContent}) async {
    if (fileContent != null) {
      await File('${_dir.path}/files/${s.id}.m3u').writeAsString(fileContent);
    }
    changed();
    await refreshSource(s);
    unawaited(refreshEpg());
  }

  Future<void> removeSource(PlaylistSource s) async {
    sources.remove(s);
    _channelsBySource.remove(s.id);
    for (final p in ['channels/${s.id}.json', 'files/${s.id}.m3u']) {
      final f = File('${_dir.path}/$p');
      if (await f.exists()) await f.delete();
    }
    changed(reindex: true);
  }

  void setSourceEnabled(PlaylistSource s, bool enabled) {
    s.enabled = enabled;
    changed(reindex: true);
  }

  Map<String, String> _headers([String? ua]) => {
    'User-Agent': (ua == null || ua.isEmpty) ? effectiveUserAgent : ua,
  };

  Future<String> _getText(String url) async {
    final r = await _http
        .get(Uri.parse(url), headers: _headers())
        .timeout(const Duration(minutes: 3));
    if (r.statusCode >= 400) {
      throw HttpException(
        'El servidor respondió con el código ${r.statusCode}',
      );
    }
    return utf8.decode(r.bodyBytes, allowMalformed: true);
  }

  /// Descarga y procesa una lista. Devuelve el error o null si fue bien.
  Future<String?> refreshSource(PlaylistSource s) async {
    refreshStatus = 'Actualizando "${s.name}"…';
    notifyListeners();
    try {
      List<Channel> channels;
      final id = s.id;
      switch (s.type) {
        case SourceType.m3uUrl:
          final text = await _getText(s.url.trim());
          final parsed = await compute(_parseM3uJob, (text, id));
          channels = parsed.channels;
          s.detectedEpgUrl = parsed.epgUrl;
          break;
        case SourceType.m3uFile:
          final f = File('${_dir.path}/files/${s.id}.m3u');
          if (!await f.exists()) {
            throw 'No se encuentra el archivo de la lista.';
          }
          final text = await f.readAsString();
          final parsed = await compute(_parseM3uJob, (text, id));
          channels = parsed.channels;
          s.detectedEpgUrl = parsed.epgUrl;
          break;
        case SourceType.xtream:
          final server = normalizeServer(s.server);
          s.server = server;
          final base =
              '$server/player_api.php?username=${Uri.encodeQueryComponent(s.username)}&password=${Uri.encodeQueryComponent(s.password)}';
          final catsText = await _getText('$base&action=get_live_categories');
          final streamsText = await _getText('$base&action=get_live_streams');
          final user = s.username, pass = s.password, out = s.xtreamOutput;
          channels = await compute(_parseXtreamJob, [
            catsText,
            streamsText,
            id,
            server,
            user,
            pass,
            out,
          ]);
          break;
      }
      if (channels.isEmpty) {
        throw 'La lista no contiene canales.';
      }
      _channelsBySource[s.id] = channels;
      final json = jsonEncode(channels.map((c) => c.toJson()).toList());
      await File('${_dir.path}/channels/${s.id}.json').writeAsString(json);
      s.channelCount = channels.length;
      s.lastUpdated = DateTime.now();
      s.lastError = null;
      changed(reindex: true, user: false);
      return null;
    } catch (e) {
      s.lastError = _friendlyError(e);
      changed(user: false);
      return s.lastError;
    } finally {
      refreshStatus = '';
      notifyListeners();
    }
  }

  String _friendlyError(Object e) {
    if (e is SocketException) {
      return 'No se pudo conectar con el servidor (${e.message}).';
    }
    if (e is TimeoutException) {
      return 'El servidor tardó demasiado en responder.';
    }
    if (e is FormatException) return e.message;
    if (e is HttpException) return e.message;
    return e.toString();
  }

  Future<void> refreshAll() async {
    if (refreshing) return;
    refreshing = true;
    notifyListeners();
    try {
      for (final s in List.of(sources)) {
        if (s.enabled) await refreshSource(s);
      }
      settings.lastRefresh = DateTime.now();
      save();
      await refreshEpg();
    } finally {
      refreshing = false;
      refreshStatus = '';
      notifyListeners();
    }
  }

  void _startAutoRefresh() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => _checkAuto(),
    );
    // Comprobación inicial, poco después de abrir.
    Timer(const Duration(seconds: 5), _checkAuto);
  }

  void _checkAuto() {
    final h = settings.autoRefreshHours;
    if (h <= 0 || refreshing || sources.isEmpty) return;
    final last = settings.lastRefresh;
    if (last == null || DateTime.now().difference(last).inMinutes >= h * 60) {
      refreshAll();
    }
  }

  // ---------------------------------------------------------------- Guía

  List<String> get allEpgUrls {
    final set = <String>{};
    for (final u in settings.epgUrls) {
      if (u.trim().isNotEmpty) set.add(u.trim());
    }
    for (final s in sources) {
      if (s.enabled) set.addAll(s.epgUrls);
    }
    return set.toList();
  }

  String _epgFileName(String url) =>
      '${_dir.path}/epg/${url.hashCode.toUnsigned(32).toRadixString(16)}.xml';

  Future<void> refreshEpg() async {
    final urls = allEpgUrls;
    if (urls.isEmpty) return;
    epgLoading = true;
    notifyListeners();
    try {
      for (final url in urls) {
        refreshStatus = 'Descargando guía de programación…';
        notifyListeners();
        try {
          final req = http.Request('GET', Uri.parse(url))
            ..headers.addAll(_headers());
          final resp = await _http
              .send(req)
              .timeout(const Duration(minutes: 2));
          if (resp.statusCode >= 400) continue;
          final path = _epgFileName(url);
          final tmp = File('$path.tmp');
          final sink = tmp.openWrite();
          await resp.stream.pipe(sink);
          await tmp.rename(path);
        } catch (e) {
          debugPrint('Error descargando guía $url: $e');
        }
      }
      settings.lastEpgRefresh = DateTime.now();
      save();
      await _loadEpgCache();
    } finally {
      epgLoading = false;
      refreshStatus = '';
      notifyListeners();
    }
  }

  Future<void> _loadEpgCache() async {
    final urls = allEpgUrls;
    final merged = EpgData.empty();
    final from = DateTime.now().subtract(const Duration(hours: 3));
    final to = DateTime.now().add(const Duration(days: 4));
    for (final url in urls) {
      final path = _epgFileName(url);
      if (!await File(path).exists()) continue;
      try {
        final data = await compute(_parseEpgJob, (path, from, to));
        merged.merge(data);
      } catch (e) {
        debugPrint('Guía no válida $url: $e');
      }
    }
    epg = merged;
    _epgCache.clear();
    _xtreamAsked.clear();
    revision++;
    notifyListeners();
  }

  // ---------------------------------------------------------------- Ajustes

  void updateSettings(void Function(AppSettings s) fn) {
    fn(settings);
    changed(reindex: true);
  }

  void setLastChannel(Channel c) {
    settings.lastChannelKey = c.key;
    save();
  }

  // ---------------------------------------------------------------- Sincronizar

  /// Ajustes que se comparten entre aparatos (el resto son de cada uno).
  static const syncedSettings = [
    'themeMode',
    'seedColor',
    'autoRefreshHours',
    'epgUrls',
    'userAgent',
    'showHidden',
    'reconnect',
    'recordBeforeMinutes',
    'recordAfterMinutes',
    'audioLanguage',
    'subtitleLanguage',
  ];

  static const _localSourceFields = [
    'lastUpdated',
    'lastError',
    'channelCount',
    'detectedEpgUrl',
  ];

  /// Lo que se guarda en Drive.
  Future<Map<String, dynamic>> syncPayload() async {
    final all = settings.toJson();
    final files = <String, String>{};
    for (final s in sources) {
      if (s.type == SourceType.m3uFile) {
        final f = File('${_dir.path}/files/${s.id}.m3u');
        if (await f.exists()) files[s.id] = await f.readAsString();
      }
    }
    return {
      'app': 'mi-iptv',
      'version': 1,
      'settings': {for (final k in syncedSettings) k: all[k]},
      'custom': custom.toJson(),
      'sources': [
        for (final s in sources)
          s.toJson()..removeWhere((k, _) => _localSourceFields.contains(k)),
      ],
      'files': files,
    };
  }

  /// Aplica lo que llega de Drive sin borrar lo propio de este aparato.
  Future<void> applySyncPayload(Map<String, dynamic> p) async {
    final oldById = {for (final s in sources) s.id: s};
    final oldEpg = allEpgUrls.join('|');
    final oldFiles = <String, String>{};
    for (final s in sources) {
      if (s.type == SourceType.m3uFile) {
        final f = File('${_dir.path}/files/${s.id}.m3u');
        if (await f.exists()) oldFiles[s.id] = await f.readAsString();
      }
    }
    // Ajustes compartidos.
    final cur = settings.toJson();
    final incoming = (p['settings'] as Map?) ?? const {};
    for (final k in syncedSettings) {
      if (incoming.containsKey(k)) cur[k] = incoming[k];
    }
    settings = AppSettings.fromJson(cur);
    custom = Customization.fromJson(
      (p['custom'] as Map?)?.cast<String, dynamic>(),
    );
    // Listas.
    final newSources = <PlaylistSource>[];
    final toRefresh = <PlaylistSource>[];
    final files = (p['files'] as Map?) ?? const {};
    for (final raw in (p['sources'] as List?) ?? const []) {
      final j = Map<String, dynamic>.from(raw as Map);
      final old = oldById[j['id']];
      if (old != null) {
        for (final k in _localSourceFields) {
          j[k] = old.toJson()[k];
        }
      }
      final s = PlaylistSource.fromJson(j);
      newSources.add(s);
      final content = files[s.id];
      if (content is String) {
        await File('${_dir.path}/files/${s.id}.m3u').writeAsString(content);
      }
      final same =
          old != null &&
          old.type == s.type &&
          old.url == s.url &&
          old.server == s.server &&
          old.username == s.username &&
          old.password == s.password &&
          old.xtreamOutput == s.xtreamOutput &&
          (content == null || content == oldFiles[s.id]);
      if (!same && s.enabled) toRefresh.add(s);
    }
    final newIds = newSources.map((s) => s.id).toSet();
    for (final s in sources) {
      if (newIds.contains(s.id)) continue;
      _channelsBySource.remove(s.id);
      for (final f in ['channels/${s.id}.json', 'files/${s.id}.m3u']) {
        final file = File('${_dir.path}/$f');
        if (await file.exists()) await file.delete();
      }
    }
    for (final s in newSources) {
      if (!_channelsBySource.containsKey(s.id)) await _loadChannelCache(s);
    }
    sources
      ..clear()
      ..addAll(newSources);
    final t = DateTime.tryParse('${p['updatedAt'] ?? ''}');
    if (t != null) lastUserChange = t;
    changed(reindex: true, user: false);
    for (final s in toRefresh) {
      await refreshSource(s);
    }
    if (allEpgUrls.join('|') != oldEpg || toRefresh.isNotEmpty) {
      unawaited(refreshEpg());
    }
  }

  // ---------------------------------------------------------------- Exportar

  Future<Uint8List> exportConfig() async {
    final files = <String, String>{};
    for (final s in sources) {
      if (s.type == SourceType.m3uFile) {
        final f = File('${_dir.path}/files/${s.id}.m3u');
        if (await f.exists()) files[s.id] = await f.readAsString();
      }
    }
    final j = _configJson()
      ..['exportedAt'] = DateTime.now().toIso8601String()
      ..['files'] = files;
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(j)),
    );
  }

  /// Sustituye toda la configuración por la del archivo.
  Future<void> importConfig(Uint8List bytes) async {
    final j = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    if (j is! Map || j['app'] != 'mi-iptv') {
      throw const FormatException(
        'El archivo no es una configuración de Mi IPTV.',
      );
    }
    final map = Map<String, dynamic>.from(j);
    // Borrar datos anteriores.
    for (final s in sources) {
      for (final p in ['channels/${s.id}.json', 'files/${s.id}.m3u']) {
        final f = File('${_dir.path}/$p');
        if (await f.exists()) await f.delete();
      }
    }
    _channelsBySource.clear();
    _applyConfig(map);
    final files = (map['files'] as Map?) ?? const {};
    for (final e in files.entries) {
      await File('${_dir.path}/files/${e.key}.m3u').writeAsString('${e.value}');
    }
    settings.lastRefresh = null;
    changed(reindex: true);
    await _saveNow();
    await refreshAll();
  }
}

final app = AppController.instance;

// Tareas pesadas que se ejecutan en segundo plano (otro hilo).

List<Channel> _decodeChannels(String text) => (jsonDecode(text) as List)
    .map((e) => Channel.fromJson(Map<String, dynamic>.from(e as Map)))
    .toList();

ParsedPlaylist _parseM3uJob((String, String) a) => parseM3u(a.$1, a.$2);

List<Channel> _parseXtreamJob(List<String> a) => parseXtream(
  categoriesJson: a[0],
  streamsJson: a[1],
  sourceId: a[2],
  server: a[3],
  username: a[4],
  password: a[5],
  output: a[6],
);

Future<EpgData> _parseEpgJob((String, DateTime, DateTime) a) =>
    parseXmltvFile(a.$1, a.$2, a.$3);
