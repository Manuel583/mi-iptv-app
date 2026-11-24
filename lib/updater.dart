// Actualizar la app desde la propia app (Android y Windows).
//
// La app pregunta a GitHub cuál es la última versión publicada en "Releases".
// Si el repositorio es público no hace falta nada más. Si es privado, hace
// falta un permiso de lectura (token) que el usuario pega en Ajustes. El token
// se guarda sólo en este aparato, en un archivo aparte que NO se incluye en la
// copia de seguridad.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Versión de esta compilación. La pone GitHub al compilar
/// (--dart-define=APP_VERSION=1.0.N). En pruebas locales vale 0.0.0.
const String appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '0.0.0',
);

const _repo = 'Manuel583/mi-iptv-app';
const _apiLatest = 'https://api.github.com/repos/$_repo/releases/latest';
const _androidAsset = 'mi-iptv-android.apk';
const _windowsAsset = 'mi-iptv-windows-instalador.exe';

/// Compara versiones tipo "1.0.12" (acepta una "v" delante).
/// Devuelve >0 si a es más nueva que b.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .trim()
      .replaceFirst(RegExp(r'^[vV]'), '')
      .split(RegExp(r'[.+\-]'))
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

class ReleaseInfo {
  ReleaseInfo({
    required this.version,
    required this.name,
    required this.notes,
    required this.assetApiUrl,
    required this.assetSize,
  });

  final String version; // sin la "v"
  final String name;
  final String notes;
  final String? assetApiUrl; // archivo para este sistema (null si no hay)
  final int assetSize;

  bool get isNewer => compareVersions(version, appVersion) > 0;

  /// Lee la respuesta de GitHub y elige el archivo de este sistema.
  static ReleaseInfo fromJson(Map<String, dynamic> j, {required String asset}) {
    final tag = (j['tag_name'] ?? '') as String;
    String? url;
    var size = 0;
    for (final a in (j['assets'] as List? ?? const [])) {
      final m = (a as Map).cast<String, dynamic>();
      if (m['name'] == asset) {
        url = m['url'] as String?;
        size = (m['size'] as num?)?.toInt() ?? 0;
      }
    }
    return ReleaseInfo(
      version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
      name: (j['name'] ?? tag) as String,
      notes: (j['body'] ?? '') as String,
      assetApiUrl: url,
      assetSize: size,
    );
  }
}

/// Error con un mensaje ya pensado para el usuario.
class UpdateError implements Exception {
  UpdateError(this.message);
  final String message;
  @override
  String toString() => message;
}

class Updater extends ChangeNotifier {
  static const _ch = MethodChannel('mi_iptv/updater');

  final navigatorKey = GlobalKey<NavigatorState>();
  final messengerKey = GlobalKey<ScaffoldMessengerState>();

  String _token = '';
  DateTime? lastCheck;
  ReleaseInfo? latest;
  bool checking = false;
  double? progress; // 0..1 mientras descarga
  bool _loaded = false;

  /// Sólo Android y Windows pueden actualizarse solos.
  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isWindows);

  bool get hasToken => _token.isNotEmpty;
  bool get downloading => progress != null;
  String get _asset => Platform.isAndroid ? _androidAsset : _windowsAsset;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/actualizaciones.json');
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        _token = (j['token'] ?? '') as String;
        lastCheck = DateTime.tryParse((j['lastCheck'] ?? '') as String);
      }
    } catch (e) {
      debugPrint('No se pudo leer actualizaciones.json: $e');
    }
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      await f.writeAsString(
        jsonEncode({
          'token': _token,
          'lastCheck': lastCheck?.toIso8601String(),
        }),
      );
    } catch (e) {
      debugPrint('No se pudo guardar actualizaciones.json: $e');
    }
  }

  Map<String, String> _headers(String token, {bool binary = false}) => {
    if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    'Accept': binary
        ? 'application/octet-stream'
        : 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'mi-iptv-app',
  };

  Future<ReleaseInfo> _fetchLatest(String token) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(_apiLatest));
      _headers(token).forEach(req.headers.set);
      final res = await req.close().timeout(const Duration(seconds: 30));
      final body = await res.transform(utf8.decoder).join();
      switch (res.statusCode) {
        case 200:
          return ReleaseInfo.fromJson(
            jsonDecode(body) as Map<String, dynamic>,
            asset: _asset,
          );
        case 401:
          throw UpdateError(
            'GitHub no acepta el permiso de lectura. Puede que haya caducado '
            'o esté mal copiado. Crea uno nuevo y pégalo otra vez.',
          );
        case 403:
          if (token.isEmpty) {
            throw UpdateError(
              'GitHub ha recibido demasiadas consultas desde esta conexión. '
              'Prueba dentro de un rato.',
            );
          }
          throw UpdateError(
            'El permiso de lectura no da acceso al repositorio de la app. '
            'Revisa que elegiste "mi-iptv-app" y "Contents: Read-only".',
          );
        case 404:
          if (token.isEmpty) {
            throw UpdateError(
              'No se encuentra ninguna versión publicada. Si el repositorio '
              'es privado, pega el permiso de lectura de GitHub (abajo).',
            );
          }
          throw UpdateError(
            'El permiso de lectura no da acceso al repositorio de la app. '
            'Revisa que elegiste "mi-iptv-app" y "Contents: Read-only".',
          );
        default:
          throw UpdateError(
            'GitHub respondió con un error (${res.statusCode}).',
          );
      }
    } on UpdateError {
      rethrow;
    } on SocketException {
      throw UpdateError('Sin conexión a internet.');
    } on TimeoutException {
      throw UpdateError(
        'GitHub tarda demasiado en responder. Prueba más tarde.',
      );
    } catch (e) {
      throw UpdateError('No se pudo comprobar la versión: $e');
    } finally {
      client.close(force: true);
    }
  }

  /// Comprueba y guarda un token nuevo. Lanza [UpdateError] si no sirve.
  Future<void> setToken(String token) async {
    final t = token.trim();
    if (t.isEmpty) {
      _token = '';
      latest = null;
      await _save();
      notifyListeners();
      return;
    }
    latest = await _fetchLatest(t);
    _token = t;
    lastCheck = DateTime.now();
    await _save();
    notifyListeners();
  }

  /// Pregunta a GitHub por la última versión.
  Future<ReleaseInfo> check() async {
    checking = true;
    notifyListeners();
    try {
      latest = await _fetchLatest(_token);
      lastCheck = DateTime.now();
      await _save();
      return latest!;
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  /// Al abrir la app: como mucho una vez al día, sin molestar si falla.
  Future<void> checkOnStartup() async {
    if (!supported) return;
    await load();
    final last = lastCheck;
    if (last != null && DateTime.now().difference(last).inHours < 20) return;
    try {
      final r = await check();
      if (r.isNewer && r.assetApiUrl != null) {
        messengerKey.currentState?.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 12),
            content: Text('Hay una versión nueva de Mi IPTV (${r.version}).'),
            action: SnackBarAction(
              label: 'Actualizar',
              onPressed: () {
                final ctx = navigatorKey.currentContext;
                if (ctx != null) startUpdate(ctx);
              },
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Comprobación de versión al arrancar: $e');
    }
  }

  /// Descarga el archivo de GitHub a [dest], avisando del progreso.
  /// GitHub redirige a un enlace temporal de descarga: ese segundo paso
  /// va sin el token (si se envía, la descarga falla).
  Future<void> _download(ReleaseInfo r, File dest) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      var req = await client.getUrl(Uri.parse(r.assetApiUrl!));
      req.followRedirects = false;
      _headers(_token, binary: true).forEach(req.headers.set);
      var res = await req.close();
      var hops = 0;
      while (res.isRedirect ||
          (res.statusCode >= 300 && res.statusCode < 400)) {
        final loc = res.headers.value(HttpHeaders.locationHeader);
        await res.drain<void>();
        if (loc == null || ++hops > 5) {
          throw UpdateError('GitHub no dio el enlace de descarga.');
        }
        req = await client.getUrl(Uri.parse(r.assetApiUrl!).resolve(loc));
        req.followRedirects = false;
        req.headers.set('User-Agent', 'mi-iptv-app');
        res = await req.close();
      }
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw UpdateError('La descarga falló (${res.statusCode}).');
      }
      final total = res.contentLength > 0 ? res.contentLength : r.assetSize;
      final sink = dest.openWrite();
      var got = 0;
      try {
        await for (final chunk in res) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) {
            progress = (got / total).clamp(0.0, 1.0);
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && got < total) {
        throw UpdateError('La descarga se cortó. Inténtalo de nuevo.');
      }
    } on UpdateError {
      rethrow;
    } on SocketException {
      throw UpdateError('Se perdió la conexión durante la descarga.');
    } catch (e) {
      throw UpdateError('No se pudo descargar: $e');
    } finally {
      client.close(force: true);
    }
  }

  /// Flujo completo: comprobar, preguntar, descargar e instalar.
  Future<void> startUpdate(BuildContext context) async {
    if (downloading || checking) return;
    void msg(String t) {
      final m = messengerKey.currentState;
      m
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(t)));
    }

    ReleaseInfo r;
    try {
      r = await check();
    } on UpdateError catch (e) {
      msg(e.message);
      return;
    }
    if (!r.isNewer) {
      msg('Ya tienes la última versión ($appVersion).');
      return;
    }
    if (r.assetApiUrl == null) {
      msg('La versión ${r.version} no trae archivo para este aparato.');
      return;
    }

    // En Android, comprobar antes el permiso para instalar aplicaciones.
    if (Platform.isAndroid) {
      final can = await _ch.invokeMethod<bool>('canInstall') ?? false;
      if (!can) {
        if (!context.mounted) return;
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Falta un permiso'),
            content: const Text(
              'Android necesita que permitas a Mi IPTV instalar aplicaciones. '
              'Se abrirá la pantalla de Android: activa "Permitir de esta fuente", '
              'vuelve a la app y pulsa otra vez "Buscar actualización".',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Abrir ajustes'),
              ),
            ],
          ),
        );
        if (go == true) await _ch.invokeMethod('openInstallSettings');
        return;
      }
    }

    if (!context.mounted) return;
    final sizeMb = r.assetSize > 0
        ? ' (${(r.assetSize / (1024 * 1024)).toStringAsFixed(0)} MB)'
        : '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Versión ${r.version} disponible'),
        content: Text(
          'Tienes la $appVersion. ¿Descargar e instalar la nueva$sizeMb?\n\n'
          '${Platform.isAndroid ? 'Android te pedirá confirmar la instalación. Tus listas y ajustes se conservan.' : 'Se cerrará Mi IPTV y se abrirá el instalador. Pulsa "Siguiente" hasta terminar. Tus listas y ajustes se conservan.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Actualizar'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    progress = 0;
    notifyListeners();
    final nav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Descargando actualización…'),
          content: ListenableBuilder(
            listenable: this,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 12),
                Text('${((progress ?? 0) * 100).round()} %'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final dir = Platform.isAndroid
          ? Directory('${(await getTemporaryDirectory()).path}/updates')
          : await Directory.systemTemp.createTemp('mi-iptv-');
      await dir.create(recursive: true);
      final file = File('${dir.path}/$_asset');
      if (await file.exists()) await file.delete();
      await _download(r, file);
      progress = null;
      notifyListeners();
      if (nav.canPop()) nav.pop();

      if (Platform.isAndroid) {
        await _ch.invokeMethod('installApk', {'path': file.path});
      } else {
        await Process.start(
          file.path,
          const [],
          mode: ProcessStartMode.detached,
        );
        // Cerrar para que el instalador pueda sustituir los archivos.
        await Future<void>.delayed(const Duration(milliseconds: 500));
        exit(0);
      }
    } catch (e) {
      progress = null;
      notifyListeners();
      if (nav.canPop()) nav.pop();
      msg(e is UpdateError ? e.message : 'No se pudo actualizar: $e');
    }
  }
}

final updater = Updater();
