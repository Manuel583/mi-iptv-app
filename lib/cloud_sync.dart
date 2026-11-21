// Sincronización de la configuración con el Google Drive del usuario.
//
// | Se guarda un único archivo (mi-iptv.json) en la carpeta privada de la app
//   dentro de Drive ("appDataFolder"): no aparece entre tus archivos y
//   ninguna otra app puede leerlo.
// | Para entrar se usa el método de Google para televisores: la app muestra
//   un código y lo escribes en google.com/device desde el móvil o el PC.
//   Así funciona igual en el móvil, en Windows y en la tele.
// | Las contraseñas de tus listas viajan sólo entre tus aparatos y tu Drive.
//   Nunca se guardan en GitHub.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';

/// El identificador del permiso de Google se añade al compilar (secretos de
/// GitHub GOOGLE_CLIENT_ID y GOOGLE_CLIENT_SECRET) o se escribe en Ajustes.
const _builtInClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
const _builtInClientSecret = String.fromEnvironment('GOOGLE_CLIENT_SECRET');

const _scope = 'https://www.googleapis.com/auth/drive.appdata';
const _fileName = 'mi-iptv.json';

class DeviceCode {
  DeviceCode(
    this.userCode,
    this.url,
    this.deviceCode,
    this.interval,
    this.expires,
  );
  final String userCode;
  final String url;
  final String deviceCode;
  final int interval;
  final DateTime expires;
}

class CloudSync extends ChangeNotifier {
  CloudSync._();
  static final CloudSync instance = CloudSync._();

  final http.Client _http = http.Client();
  File? _file;

  // Datos guardados sólo en este aparato (nunca se sincronizan).
  String clientId = '';
  String clientSecret = '';
  String refreshToken = '';
  String account = '';
  String _remoteId = '';
  String _lastHash = '';
  DateTime? lastSync;
  String lastError = '';
  bool busy = false;

  String? _accessToken;
  DateTime _accessExpires = DateTime(2000);
  Timer? _pushTimer;
  Timer? _pullTimer;
  bool _applying = false;

  String get effectiveClientId =>
      clientId.isNotEmpty ? clientId : _builtInClientId;
  String get effectiveClientSecret =>
      clientSecret.isNotEmpty ? clientSecret : _builtInClientSecret;
  bool get hasClient =>
      effectiveClientId.isNotEmpty && effectiveClientSecret.isNotEmpty;
  bool get hasBuiltInClient => _builtInClientId.isNotEmpty;
  bool get connected => refreshToken.isNotEmpty;

  // ---------------------------------------------------------------- Disco

  Future<void> load() async {
    try {
      final d = await getApplicationSupportDirectory();
      _file = File('${d.path}/google.json');
      if (await _file!.exists()) {
        final j =
            jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
        clientId = (j['clientId'] ?? '') as String;
        clientSecret = (j['clientSecret'] ?? '') as String;
        refreshToken = (j['refreshToken'] ?? '') as String;
        account = (j['account'] ?? '') as String;
        _remoteId = (j['remoteId'] ?? '') as String;
        _lastHash = (j['lastHash'] ?? '') as String;
        final t = j['lastSync'];
        lastSync = t is String ? DateTime.tryParse(t) : null;
      }
    } catch (e) {
      debugPrint('google.json: $e');
    }
    app.onUserChange = _schedulePush;
    if (connected) {
      _startTimers();
      unawaited(syncNow());
    }
  }

  Future<void> _save() async {
    try {
      await _file?.writeAsString(
        jsonEncode({
          'clientId': clientId,
          'clientSecret': clientSecret,
          'refreshToken': refreshToken,
          'account': account,
          'remoteId': _remoteId,
          'lastHash': _lastHash,
          'lastSync': lastSync?.toIso8601String(),
        }),
      );
    } catch (_) {}
  }

  Future<void> setClient(String id, String secret) async {
    clientId = id.trim();
    clientSecret = secret.trim();
    await _save();
    notifyListeners();
  }

  // ---------------------------------------------------------------- Entrar

  /// Paso 1: pide a Google un código para escribir en google.com/device.
  Future<DeviceCode> startSignIn() async {
    if (!hasClient) {
      throw const FormatException(
        'Falta el permiso de Google (ID de cliente).',
      );
    }
    final r = await _http.post(
      Uri.parse('https://oauth2.googleapis.com/device/code'),
      body: {'client_id': effectiveClientId, 'scope': '$_scope openid email'},
    );
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode != 200) {
      throw FormatException(_googleError(j));
    }
    return DeviceCode(
      j['user_code'] as String,
      (j['verification_url'] ??
              j['verification_uri'] ??
              'https://www.google.com/device')
          as String,
      j['device_code'] as String,
      ((j['interval'] ?? 5) as num).toInt(),
      DateTime.now().add(
        Duration(seconds: ((j['expires_in'] ?? 1800) as num).toInt()),
      ),
    );
  }

  /// Paso 2: espera a que el usuario escriba el código. Devuelve true si entró.
  Future<bool> waitForSignIn(
    DeviceCode code, {
    bool Function()? cancelled,
  }) async {
    var interval = code.interval;
    while (DateTime.now().isBefore(code.expires)) {
      await Future.delayed(Duration(seconds: interval));
      if (cancelled?.call() ?? false) return false;
      final r = await _http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        body: {
          'client_id': effectiveClientId,
          'client_secret': effectiveClientSecret,
          'device_code': code.deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        },
      );
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode == 200) {
        refreshToken = (j['refresh_token'] ?? '') as String;
        _accessToken = j['access_token'] as String?;
        _accessExpires = DateTime.now().add(
          Duration(seconds: ((j['expires_in'] ?? 3600) as num).toInt() - 60),
        );
        account =
            _emailFromIdToken(j['id_token'] as String?) ??
            'tu cuenta de Google';
        _remoteId = '';
        _lastHash = '';
        await _save();
        _startTimers();
        notifyListeners();
        await syncNow(preferRemote: true);
        return true;
      }
      final err = j['error'];
      if (err == 'authorization_pending') continue;
      if (err == 'slow_down') {
        interval += 5;
        continue;
      }
      throw FormatException(_googleError(j));
    }
    return false;
  }

  Future<void> signOut() async {
    final t = refreshToken;
    refreshToken = '';
    account = '';
    _accessToken = null;
    _remoteId = '';
    _lastHash = '';
    lastSync = null;
    _pullTimer?.cancel();
    _pushTimer?.cancel();
    await _save();
    notifyListeners();
    if (t.isNotEmpty) {
      try {
        await _http.post(
          Uri.parse('https://oauth2.googleapis.com/revoke'),
          body: {'token': t},
        );
      } catch (_) {}
    }
  }

  static String? _emailFromIdToken(String? idToken) {
    if (idToken == null) return null;
    try {
      final part = idToken.split('.')[1];
      final j = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(part))),
      );
      return (j as Map)['email'] as String?;
    } catch (_) {
      return null;
    }
  }

  static String _googleError(Map<String, dynamic> j) {
    final e = '${j['error'] ?? ''}';
    switch (e) {
      case 'access_denied':
        return 'Has rechazado el permiso en la página de Google.';
      case 'expired_token':
        return 'El código ha caducado. Vuelve a intentarlo.';
      case 'invalid_client':
        return 'El ID o el secreto de cliente de Google no son correctos.';
      case 'invalid_grant':
        return 'Google ha retirado el permiso. Vuelve a conectar la cuenta.';
    }
    return '${j['error_description'] ?? e}';
  }

  Future<String> _token() async {
    if (_accessToken != null && DateTime.now().isBefore(_accessExpires)) {
      return _accessToken!;
    }
    final r = await _http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      body: {
        'client_id': effectiveClientId,
        'client_secret': effectiveClientSecret,
        'refresh_token': refreshToken,
        'grant_type': 'refresh_token',
      },
    );
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode != 200) {
      if (j['error'] == 'invalid_grant') {
        refreshToken = '';
        await _save();
        notifyListeners();
      }
      throw FormatException(_googleError(j));
    }
    _accessToken = j['access_token'] as String;
    _accessExpires = DateTime.now().add(
      Duration(seconds: ((j['expires_in'] ?? 3600) as num).toInt() - 60),
    );
    return _accessToken!;
  }

  // ---------------------------------------------------------------- Drive

  Future<Map<String, String>> _auth() async => {
    'Authorization': 'Bearer ${await _token()}',
  };

  /// Busca el archivo en Drive: (id, fecha de modificación).
  Future<(String, DateTime)?> _remoteInfo() async {
    final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
      'spaces': 'appDataFolder',
      'q': "name = '$_fileName'",
      'fields': 'files(id,modifiedTime)',
      'orderBy': 'modifiedTime desc',
    });
    final r = await _http.get(uri, headers: await _auth());
    if (r.statusCode != 200) {
      throw HttpException('Drive respondió ${r.statusCode}');
    }
    final files = (jsonDecode(r.body) as Map)['files'] as List;
    if (files.isEmpty) return null;
    final f = files.first as Map;
    return (f['id'] as String, DateTime.parse(f['modifiedTime'] as String));
  }

  Future<Map<String, dynamic>?> _download(String id) async {
    final r = await _http.get(
      Uri.https('www.googleapis.com', '/drive/v3/files/$id', {'alt': 'media'}),
      headers: await _auth(),
    );
    if (r.statusCode != 200) {
      throw HttpException('Drive respondió ${r.statusCode}');
    }
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    return j is Map ? Map<String, dynamic>.from(j) : null;
  }

  Future<void> _upload(Map<String, dynamic> data) async {
    final body = utf8.encode(jsonEncode(data));
    final headers = await _auth();
    if (_remoteId.isNotEmpty) {
      final r = await _http.patch(
        Uri.https('www.googleapis.com', '/upload/drive/v3/files/$_remoteId', {
          'uploadType': 'media',
        }),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: body,
      );
      if (r.statusCode == 200) return;
      if (r.statusCode != 404) {
        throw HttpException('Drive respondió ${r.statusCode}');
      }
      _remoteId = '';
    }
    const boundary = 'mi-iptv-limite';
    final meta = jsonEncode({
      'name': _fileName,
      'parents': ['appDataFolder'],
    });
    final multipart = <int>[
      ...utf8.encode(
        '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$meta\r\n'
        '--$boundary\r\nContent-Type: application/json\r\n\r\n',
      ),
      ...body,
      ...utf8.encode('\r\n--$boundary--'),
    ];
    final r = await _http.post(
      Uri.https('www.googleapis.com', '/upload/drive/v3/files', {
        'uploadType': 'multipart',
        'fields': 'id',
      }),
      headers: {
        ...headers,
        'Content-Type': 'multipart/related; boundary=$boundary',
      },
      body: multipart,
    );
    if (r.statusCode != 200) {
      throw HttpException('Drive respondió ${r.statusCode}');
    }
    _remoteId = (jsonDecode(r.body) as Map)['id'] as String;
  }

  // ---------------------------------------------------------------- Sincronizar

  void _startTimers() {
    _pullTimer?.cancel();
    _pullTimer = Timer.periodic(const Duration(minutes: 15), (_) => syncNow());
  }

  void _schedulePush() {
    if (!connected || _applying) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(seconds: 20), () => syncNow());
  }

  /// Llamar al volver a la app.
  void onResume() {
    if (connected) unawaited(syncNow());
  }

  /// Compara con Drive: si allí hay cambios más nuevos, los aplica; si los
  /// nuevos son los de este aparato, los sube.
  Future<void> syncNow({bool preferRemote = false}) async {
    if (!connected || busy) return;
    busy = true;
    lastError = '';
    notifyListeners();
    try {
      final local = await app.syncPayload();
      final localHash = payloadHash(local);
      final info = await _remoteInfo();
      Map<String, dynamic>? remote;
      if (info != null) {
        _remoteId = info.$1;
        if (lastSync == null || info.$2.isAfter(lastSync!) || preferRemote) {
          remote = await _download(info.$1);
        }
      }
      final localChanged = localHash != _lastHash;
      if (remote != null && remote['app'] == 'mi-iptv') {
        final remoteHash = payloadHash(remote);
        if (remoteHash != localHash) {
          // Gana el cambio más reciente.
          final rt = DateTime.tryParse('${remote['updatedAt'] ?? ''}');
          final lt = app.lastUserChange;
          final remoteWins =
              preferRemote ||
              !localChanged ||
              (rt != null && (lt == null || rt.isAfter(lt)));
          if (remoteWins) {
            _applying = true;
            try {
              await app.applySyncPayload(remote);
            } finally {
              _applying = false;
            }
            _lastHash = payloadHash(await app.syncPayload());
          } else {
            await _upload({
              ...local,
              'updatedAt': (lt ?? DateTime.now()).toIso8601String(),
            });
            _lastHash = localHash;
          }
        } else {
          _lastHash = localHash;
        }
      } else if (localChanged || info == null) {
        await _upload({
          ...local,
          'updatedAt': (app.lastUserChange ?? DateTime.now()).toIso8601String(),
        });
        _lastHash = localHash;
      }
      lastSync = DateTime.now();
      await _save();
    } catch (e) {
      lastError = e is FormatException ? e.message : '$e';
      debugPrint('Sincronización: $e');
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}

/// Huella del contenido (sin la fecha), para saber si algo cambió.
String payloadHash(Map<String, dynamic> p) {
  final copy = Map<String, dynamic>.from(p)
    ..remove('updatedAt')
    ..remove('device');
  final text = jsonEncode(_sorted(copy));
  var h = 0xcbf29ce484222325;
  for (final b in utf8.encode(text)) {
    h ^= b;
    h = h * 0x100000001b3;
  }
  return h.toRadixString(16);
}

Object? _sorted(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => '$k').toList()..sort();
    return {for (final k in keys) k: _sorted(v[k])};
  }
  if (v is List) return v.map(_sorted).toList();
  return v;
}
