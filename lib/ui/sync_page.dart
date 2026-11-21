// Pantalla para conectar Google Drive y sincronizar la configuración.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cloud_sync.dart';
import 'common.dart';

class SyncPage extends StatefulWidget {
  const SyncPage({super.key});

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  final _sync = CloudSync.instance;

  Future<void> _connect() async {
    DeviceCode code;
    try {
      code = await _sync.startSignIn();
    } catch (e) {
      if (mounted) {
        showMessage(context, '$e'.replaceFirst('FormatException: ', ''));
      }
      return;
    }
    if (!mounted) return;
    var cancelled = false;
    final wait = _sync.waitForSignIn(code, cancelled: () => cancelled);
    final dialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Conectar con Google Drive'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('1. En el móvil o en el ordenador, abre esta página:'),
            const SizedBox(height: 6),
            SelectableText(
              code.url,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 12),
            const Text('2. Escribe este código y acepta el permiso:'),
            const SizedBox(height: 6),
            Row(
              children: [
                SelectableText(
                  code.userCode,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 28,
                    letterSpacing: 2,
                  ),
                ),
                IconButton(
                  tooltip: 'Copiar',
                  icon: const Icon(Icons.copy),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: code.userCode)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Expanded(child: Text('Esperando a que aceptes…')),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelled = true;
              Navigator.pop(ctx);
            },
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    try {
      final ok = await wait;
      if (!cancelled && mounted) {
        Navigator.of(context).pop();
        showMessage(
          context,
          ok
              ? 'Conectado. La configuración se sincronizará sola.'
              : 'El código ha caducado. Vuelve a intentarlo.',
        );
      }
    } catch (e) {
      if (!cancelled && mounted) {
        Navigator.of(context).pop();
        showMessage(context, '$e'.replaceFirst('FormatException: ', ''));
      }
    }
    await dialog;
  }

  Future<void> _editClient() async {
    final id = TextEditingController(text: _sync.clientId);
    final secret = TextEditingController(text: _sync.clientSecret);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permiso de Google'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Pega aquí el "ID de cliente" y el "Secreto del cliente" que creaste en Google Cloud '
                '(tipo "TV y dispositivos de entrada limitada"). Se guardan sólo en este aparato.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: id,
                decoration: const InputDecoration(labelText: 'ID de cliente'),
              ),
              TextField(
                controller: secret,
                decoration: const InputDecoration(
                  labelText: 'Secreto del cliente',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (ok == true) await _sync.setClient(id.text, secret.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sincronizar con Google Drive')),
      body: ListenableBuilder(
        listenable: _sync,
        builder: (context, _) {
          final s = _sync;
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Text(
                  'Tus listas, favoritos, carpetas, nombres y ajustes se guardan en una carpeta privada '
                  'de tu Google Drive y pasan solos al móvil, al ordenador y a la tele. '
                  'No aparece entre tus archivos y sólo esta app puede leerla.',
                ),
              ),
              if (s.connected) ...[
                ListTile(
                  leading: const Icon(Icons.cloud_done_outlined),
                  title: Text('Conectado con ${s.account}'),
                  subtitle: Text(
                    s.busy
                        ? 'Sincronizando…'
                        : s.lastError.isNotEmpty
                        ? 'Último intento con error: ${s.lastError}'
                        : s.lastSync == null
                        ? 'Todavía no se ha sincronizado'
                        : 'Última vez: ${hhmm(s.lastSync!)}',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text('Sincronizar ahora'),
                  enabled: !s.busy,
                  onTap: () => s.syncNow(),
                ),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Traer la configuración de Drive'),
                  subtitle: const Text(
                    'Sustituye la de este aparato por la guardada en Drive',
                  ),
                  enabled: !s.busy,
                  onTap: () => s.syncNow(preferRemote: true),
                ),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Desconectar'),
                  subtitle: const Text(
                    'Este aparato deja de sincronizar. Lo de Drive no se borra.',
                  ),
                  onTap: () async {
                    final ok = await confirm(
                      context,
                      'Desconectar',
                      '¿Dejar de sincronizar este aparato?',
                      ok: 'Desconectar',
                    );
                    if (ok) await s.signOut();
                  },
                ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.add_to_drive),
                  title: const Text('Conectar con Google Drive'),
                  subtitle: Text(
                    s.hasClient
                        ? 'Te dará un código para escribir en google.com/device'
                        : 'Primero falta el permiso de Google (abajo)',
                  ),
                  enabled: s.hasClient,
                  onTap: _connect,
                ),
              ],
              const Divider(),
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: const Text('Permiso de Google (ID de cliente)'),
                subtitle: Text(
                  s.clientId.isNotEmpty
                      ? 'Escrito a mano en este aparato'
                      : s.hasBuiltInClient
                      ? 'Incluido en la app'
                      : 'Falta. Sigue los pasos del manual y pégalo aquí.',
                ),
                onTap: _editClient,
              ),
            ],
          );
        },
      ),
    );
  }
}
