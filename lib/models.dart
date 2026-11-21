// Modelos de datos de la aplicación.

enum SourceType { m3uUrl, m3uFile, xtream }

String sourceTypeLabel(SourceType t) {
  switch (t) {
    case SourceType.m3uUrl:
      return 'Enlace M3U';
    case SourceType.m3uFile:
      return 'Archivo M3U';
    case SourceType.xtream:
      return 'Xtream Codes';
  }
}

/// Una lista de canales añadida por el usuario.
class PlaylistSource {
  PlaylistSource({
    required this.id,
    required this.name,
    required this.type,
    this.url = '',
    this.server = '',
    this.username = '',
    this.password = '',
    this.xtreamOutput = 'ts',
    this.epgUrl = '',
    this.useIncludedEpg = true,
    this.detectedEpgUrl = '',
    this.enabled = true,
    this.lastUpdated,
    this.lastError,
    this.channelCount = 0,
  });

  final String id;
  String name;
  SourceType type;
  String url;
  String server;
  String username;
  String password;
  String xtreamOutput;
  String epgUrl;
  bool useIncludedEpg;
  String detectedEpgUrl;
  bool enabled;
  DateTime? lastUpdated;
  String? lastError;
  int channelCount;

  /// Enlaces de guía (EPG) que aporta esta lista.
  List<String> get epgUrls {
    final out = <String>[];
    if (epgUrl.trim().isNotEmpty) out.add(epgUrl.trim());
    if (useIncludedEpg) {
      if (type == SourceType.xtream && server.isNotEmpty) {
        out.add(
          '$server/xmltv.php?username=${Uri.encodeQueryComponent(username)}&password=${Uri.encodeQueryComponent(password)}',
        );
      } else if (detectedEpgUrl.isNotEmpty) {
        for (final u in detectedEpgUrl.split(',')) {
          if (u.trim().startsWith('http')) out.add(u.trim());
        }
      }
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'url': url,
    'server': server,
    'username': username,
    'password': password,
    'xtreamOutput': xtreamOutput,
    'epgUrl': epgUrl,
    'useIncludedEpg': useIncludedEpg,
    'detectedEpgUrl': detectedEpgUrl,
    'enabled': enabled,
    'lastUpdated': lastUpdated?.toIso8601String(),
    'lastError': lastError,
    'channelCount': channelCount,
  };

  factory PlaylistSource.fromJson(Map<String, dynamic> j) => PlaylistSource(
    id: j['id'] as String,
    name: (j['name'] ?? 'Lista') as String,
    type: SourceType.values.firstWhere(
      (t) => t.name == j['type'],
      orElse: () => SourceType.m3uUrl,
    ),
    url: (j['url'] ?? '') as String,
    server: (j['server'] ?? '') as String,
    username: (j['username'] ?? '') as String,
    password: (j['password'] ?? '') as String,
    xtreamOutput: (j['xtreamOutput'] ?? 'ts') as String,
    epgUrl: (j['epgUrl'] ?? '') as String,
    useIncludedEpg: (j['useIncludedEpg'] ?? true) as bool,
    detectedEpgUrl: (j['detectedEpgUrl'] ?? '') as String,
    enabled: (j['enabled'] ?? true) as bool,
    lastUpdated: j['lastUpdated'] == null
        ? null
        : DateTime.tryParse(j['lastUpdated'] as String),
    lastError: j['lastError'] as String?,
    channelCount: (j['channelCount'] ?? 0) as int,
  );
}

/// Un canal de televisión.
class Channel {
  const Channel({
    required this.key,
    required this.sourceId,
    required this.name,
    required this.url,
    this.logo = '',
    this.group = '',
    this.tvgId = '',
    this.tvgName = '',
    this.country = '',
    this.userAgent = '',
    this.referrer = '',
  });

  /// Identificador estable (lista + grupo + nombre).
  final String key;
  final String sourceId;
  final String name;
  final String url;
  final String logo;
  final String group;
  final String tvgId;
  final String tvgName;
  final String country;
  final String userAgent;
  final String referrer;

  Map<String, dynamic> toJson() => {
    'k': key,
    's': sourceId,
    'n': name,
    'u': url,
    if (logo.isNotEmpty) 'l': logo,
    if (group.isNotEmpty) 'g': group,
    if (tvgId.isNotEmpty) 'i': tvgId,
    if (tvgName.isNotEmpty) 't': tvgName,
    if (country.isNotEmpty) 'c': country,
    if (userAgent.isNotEmpty) 'a': userAgent,
    if (referrer.isNotEmpty) 'r': referrer,
  };

  factory Channel.fromJson(Map<String, dynamic> j) => Channel(
    key: j['k'] as String,
    sourceId: j['s'] as String,
    name: j['n'] as String,
    url: j['u'] as String,
    logo: (j['l'] ?? '') as String,
    group: (j['g'] ?? '') as String,
    tvgId: (j['i'] ?? '') as String,
    tvgName: (j['t'] ?? '') as String,
    country: (j['c'] ?? '') as String,
    userAgent: (j['a'] ?? '') as String,
    referrer: (j['r'] ?? '') as String,
  );
}

/// Carpeta personal creada por el usuario.
class Folder {
  Folder({required this.id, required this.name, List<String>? channelKeys})
    : channelKeys = channelKeys ?? [];

  final String id;
  String name;
  final List<String> channelKeys;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'channels': channelKeys,
  };

  factory Folder.fromJson(Map<String, dynamic> j) => Folder(
    id: j['id'] as String,
    name: j['name'] as String,
    channelKeys: List<String>.from((j['channels'] ?? []) as List),
  );
}

/// Personalización: nombres, orden, ocultos, favoritos y carpetas.
class Customization {
  Map<String, String> channelNames = {};
  Set<String> hiddenChannels = {};
  Map<String, String> groupNames = {};
  Set<String> hiddenGroups = {};
  List<String> groupOrder = [];
  Map<String, List<String>> channelOrder = {};
  List<String> favorites = [];
  List<Folder> folders = [];

  Map<String, dynamic> toJson() => {
    'channelNames': channelNames,
    'hiddenChannels': hiddenChannels.toList(),
    'groupNames': groupNames,
    'hiddenGroups': hiddenGroups.toList(),
    'groupOrder': groupOrder,
    'channelOrder': channelOrder,
    'favorites': favorites,
    'folders': folders.map((f) => f.toJson()).toList(),
  };

  static Customization fromJson(Map<String, dynamic>? j) {
    final c = Customization();
    if (j == null) return c;
    c.channelNames = Map<String, String>.from((j['channelNames'] ?? {}) as Map);
    c.hiddenChannels = Set<String>.from(
      (j['hiddenChannels'] ?? const []) as List,
    );
    c.groupNames = Map<String, String>.from((j['groupNames'] ?? {}) as Map);
    c.hiddenGroups = Set<String>.from((j['hiddenGroups'] ?? const []) as List);
    c.groupOrder = List<String>.from((j['groupOrder'] ?? const []) as List);
    c.channelOrder = ((j['channelOrder'] ?? {}) as Map).map(
      (k, v) => MapEntry(k as String, List<String>.from(v as List)),
    );
    c.favorites = List<String>.from((j['favorites'] ?? const []) as List);
    c.folders = ((j['folders'] ?? const []) as List)
        .map((f) => Folder.fromJson(Map<String, dynamic>.from(f as Map)))
        .toList();
    return c;
  }
}

/// Ajustes generales.
class AppSettings {
  String themeMode = 'system'; // system | light | dark
  int seedColor = 0xFF1565C0;
  double textScale = 1.0;
  int autoRefreshHours = 12; // 0 = nunca
  List<String> epgUrls = [];
  String userAgent = '';
  bool showHidden = false;
  bool reconnect = true;
  bool pipOnLeave = true;
  bool backgroundAudio = true;
  bool hardwareDecoding = true;
  int timeshiftMinutes = 15; // 0 = desactivado
  DateTime? lastRefresh;
  DateTime? lastEpgRefresh;
  String lastChannelKey = '';
  Map<String, dynamic> liveCaptionStyle = {};

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode,
    'seedColor': seedColor,
    'textScale': textScale,
    'autoRefreshHours': autoRefreshHours,
    'epgUrls': epgUrls,
    'userAgent': userAgent,
    'showHidden': showHidden,
    'reconnect': reconnect,
    'pipOnLeave': pipOnLeave,
    'backgroundAudio': backgroundAudio,
    'hardwareDecoding': hardwareDecoding,
    'timeshiftMinutes': timeshiftMinutes,
    'lastRefresh': lastRefresh?.toIso8601String(),
    'lastEpgRefresh': lastEpgRefresh?.toIso8601String(),
    'lastChannelKey': lastChannelKey,
    'liveCaptionStyle': liveCaptionStyle,
  };

  static AppSettings fromJson(Map<String, dynamic>? j) {
    final s = AppSettings();
    if (j == null) return s;
    s.themeMode = (j['themeMode'] ?? s.themeMode) as String;
    s.seedColor = (j['seedColor'] ?? s.seedColor) as int;
    s.textScale = ((j['textScale'] ?? s.textScale) as num).toDouble();
    s.autoRefreshHours = (j['autoRefreshHours'] ?? s.autoRefreshHours) as int;
    s.epgUrls = List<String>.from((j['epgUrls'] ?? const []) as List);
    s.userAgent = (j['userAgent'] ?? '') as String;
    s.showHidden = (j['showHidden'] ?? false) as bool;
    s.reconnect = (j['reconnect'] ?? true) as bool;
    s.pipOnLeave = (j['pipOnLeave'] ?? true) as bool;
    s.backgroundAudio = (j['backgroundAudio'] ?? true) as bool;
    s.hardwareDecoding = (j['hardwareDecoding'] ?? true) as bool;
    s.timeshiftMinutes = (j['timeshiftMinutes'] ?? 15) as int;
    s.lastRefresh = j['lastRefresh'] == null
        ? null
        : DateTime.tryParse(j['lastRefresh'] as String);
    s.lastEpgRefresh = j['lastEpgRefresh'] == null
        ? null
        : DateTime.tryParse(j['lastEpgRefresh'] as String);
    s.lastChannelKey = (j['lastChannelKey'] ?? '') as String;
    s.liveCaptionStyle = ((j['liveCaptionStyle'] as Map?) ?? const {})
        .cast<String, dynamic>();
    return s;
  }
}

/// Un programa de la guía.
class Programme {
  const Programme(this.start, this.stop, this.title, this.desc);
  final DateTime start;
  final DateTime stop;
  final String title;
  final String desc;

  bool isNow(DateTime now) => !now.isBefore(start) && now.isBefore(stop);

  double progress(DateTime now) {
    final total = stop.difference(start).inSeconds;
    if (total <= 0) return 0;
    return (now.difference(start).inSeconds / total).clamp(0.0, 1.0);
  }
}
