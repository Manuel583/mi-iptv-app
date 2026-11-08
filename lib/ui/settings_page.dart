import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'common.dart';
import 'sources_page.dart';

const _palette = <int>[
  0xFF1565C0, // azul
  0xFF00838F, // turquesa
  0xFF2E7D32, // verde
  0xFF9E9D24, // oliva
  0xFFF9A825, // amarillo
  0xFFEF6C00, // naranja
  0xFFC62828, // rojo
  0xFFAD1457, // rosa
  0xFF6A1B9A, // morado
  0xFF4527A0, // índigo
  0xFF5D4037, // marrón
  0xFF546E7A, // gris azulado
];

bool get _isAndroid => !kIsWeb && Platform.isAndroid;

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final s = app.settings;
        final theme = Theme.of(context);
        Widget section(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(
            t,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        );
        return ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            section('Listas de canales'),
            ListTile(
              leading: const Icon(Icons.playlist_play),
              title: const Text('Mis listas'),
              subtitle: Text(
                '${app.sources.length} listas | ${app.allChannels.length} canales',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const SourcesPage())),
            ),
            ListTile(
              leading: const Icon(Icons.update),
              title: const Text('Actualizar automáticamente'),
              trailing: DropdownButton<int>(
                value: s.autoRefreshHours,
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Nunca')),
                  DropdownMenuItem(value: 1, child: Text('Cada hora')),
                  DropdownMenuItem(value: 3, child: Text('Cada 3 horas')),
                  DropdownMenuItem(value: 6, child: Text('Cada 6 horas')),
                  DropdownMenuItem(value: 12, child: Text('Cada 12 horas')),
                  DropdownMenuItem(value: 24, child: Text('Cada día')),
                  DropdownMenuItem(value: 72, child: Text('Cada 3 días')),
                  DropdownMenuItem(value: 168, child: Text('Cada semana')),
                ],
                onChanged: (v) =>
                    app.updateSettings((s) => s.autoRefreshHours = v ?? 12),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('Guías de programación (EPG)'),
              subtitle: Text(
                s.epgUrls.isEmpty
                    ? 'Sólo las incluidas en tus listas'
                    : '${s.epgUrls.length} enlaces XMLTV añadidos',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const _EpgUrlsPage())),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.visibility_outlined),
              title: const Text('Mostrar canales y grupos ocultos'),
              subtitle: const Text(
                'Aparecen atenuados para poder recuperarlos',
              ),
              value: s.showHidden,
              onChanged: (v) => app.updateSettings((s) => s.showHidden = v),
            ),

            section('Apariencia'),
            ListTile(
              leading: const Icon(Icons.brightness_6_outlined),
              title: const Text('Tema'),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'system', label: Text('Automático')),
                    ButtonSegment(value: 'light', label: Text('Claro')),
                    ButtonSegment(value: 'dark', label: Text('Oscuro')),
                  ],
                  selected: {s.themeMode},
                  onSelectionChanged: (v) =>
                      app.updateSettings((s) => s.themeMode = v.first),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Color principal'),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final c in _palette)
                      InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => app.updateSettings((s) => s.seedColor = c),
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: Color(c),
                          child: s.seedColor == c
                              ? const Icon(Icons.check, color: Colors.white)
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.format_size),
              title: Text('Tamaño de letra: ${(s.textScale * 100).round()} %'),
              subtitle: Slider(
                value: s.textScale,
                min: 0.8,
                max: 1.6,
                divisions: 8,
                label: '${(s.textScale * 100).round()} %',
                onChanged: (v) => app.updateSettings((s) => s.textScale = v),
              ),
            ),

            section('Reproducción'),
            SwitchListTile(
              secondary: const Icon(Icons.autorenew),
              title: const Text('Reconectar automáticamente'),
              subtitle: const Text('Si un canal se corta, vuelve a conectarlo'),
              value: s.reconnect,
              onChanged: (v) => app.updateSettings((s) => s.reconnect = v),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.memory),
              title: const Text('Aceleración por hardware'),
              subtitle: const Text(
                'Desactívala sólo si ves la imagen verde, negra o a saltos',
              ),
              value: s.hardwareDecoding,
              onChanged: (v) =>
                  app.updateSettings((s) => s.hardwareDecoding = v),
            ),
            if (_isAndroid) ...[
              SwitchListTile(
                secondary: const Icon(Icons.picture_in_picture_alt_outlined),
                title: const Text('Imagen flotante al salir de la app'),
                value: s.pipOnLeave,
                onChanged: (v) => app.updateSettings((s) => s.pipOnLeave = v),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.headphones_outlined),
                title: const Text('Seguir sonando en segundo plano'),
                subtitle: const Text(
                  'Muestra una notificación con el botón "Detener"',
                ),
                value: s.backgroundAudio,
                onChanged: (v) =>
                    app.updateSettings((s) => s.backgroundAudio = v),
              ),
            ],
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Identificador del reproductor (User-Agent)'),
              subtitle: Text(
                s.userAgent.isEmpty
                    ? 'Predeterminado ($defaultUserAgent)'
                    : s.userAgent,
              ),
              onTap: () async {
                final v = await askText(
                  context,
                  title: 'User-Agent',
                  label: 'Déjalo vacío para usar el predeterminado',
                  initial: s.userAgent,
                  okText: 'Guardar',
                );
                if (v != null) {
                  app.updateSettings((s) => s.userAgent = v.trim());
                }
              },
            ),

            section('Copia de seguridad'),
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('Exportar configuración'),
              subtitle: const Text(
                'Guarda listas, favoritos, carpetas y ajustes en un archivo',
              ),
              onTap: () => exportConfigFlow(context),
            ),
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('Importar configuración'),
              subtitle: const Text('Sustituye la configuración actual'),
              onTap: () => importConfigFlow(context),
            ),

            section('Acerca de'),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Mi IPTV'),
              subtitle: Text(
                'Reproductor personal. Atajos en Windows: ↑/↓ cambiar canal | '
                'Espacio pausa | F pantalla completa | M silencio | '
                'A audio | S subtítulos | P miniventana | Esc salir',
              ),
            ),
          ],
        );
      },
    );
  }
}

Future<void> exportConfigFlow(BuildContext context) async {
  try {
    final bytes = await app.exportConfig();
    final d = DateTime.now();
    final name =
        'mi-iptv-config-${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}.json';
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Guardar configuración',
      fileName: name,
      bytes: bytes,
      mimeType: 'application/json',
    );
    if (uri == null) return;
    // En Windows el diálogo sólo devuelve la ruta: escribimos el archivo.
    if (uri.scheme == 'file') {
      final f = File(uri.toFilePath());
      if (!await f.exists() || await f.length() == 0) {
        await f.writeAsBytes(bytes);
      }
    }
    if (context.mounted) {
      showMessage(
        context,
        'Configuración exportada. Contiene tus contraseñas: guárdala en un lugar seguro.',
      );
    }
  } catch (e) {
    if (context.mounted) showMessage(context, 'No se pudo exportar: $e');
  }
}

Future<void> importConfigFlow(BuildContext context) async {
  final ok = await confirm(
    context,
    'Importar configuración',
    'Se sustituirán tus listas, favoritos, carpetas y ajustes actuales por los del archivo. ¿Continuar?',
    ok: 'Elegir archivo',
  );
  if (!ok) return;
  try {
    final f = await FilePicker.pickFile(
      dialogTitle: 'Elige el archivo de configuración',
    );
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (context.mounted) showMessage(context, 'Importando y cargando listas…');
    await app.importConfig(bytes);
    if (context.mounted) showMessage(context, 'Configuración importada');
  } catch (e) {
    if (context.mounted) showMessage(context, 'No se pudo importar: $e');
  }
}

class _EpgUrlsPage extends StatelessWidget {
  const _EpgUrlsPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guías de programación'),
        actions: [
          IconButton(
            tooltip: 'Actualizar guía ahora',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await app.refreshEpg();
              if (context.mounted) showMessage(context, 'Guía actualizada');
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Añadir enlace XMLTV'),
        onPressed: () async {
          final v = await askText(
            context,
            title: 'Enlace de guía XMLTV',
            label: 'https://…/guia.xml o .xml.gz',
            okText: 'Añadir',
          );
          if (v != null && v.trim().startsWith('http')) {
            app.updateSettings((s) => s.epgUrls.add(v.trim()));
            await app.refreshEpg();
          }
        },
      ),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final urls = app.settings.epgUrls;
          final included = app.sources
              .where((s) => s.enabled)
              .expand((s) => s.epgUrls.map((u) => (s.name, u)))
              .toList();
          final last = app.settings.lastEpgRefresh;
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              ListTile(
                title: Text(
                  app.epgLoading
                      ? 'Descargando guía…'
                      : 'Última actualización: ${last == null ? 'nunca' : '${last.day}/${last.month} ${hhmm(last)}'}',
                ),
                subtitle: Text(
                  '${app.epg.programmes.length} canales con programación',
                ),
              ),
              const Divider(),
              const ListTile(title: Text('Enlaces añadidos por ti')),
              if (urls.isEmpty)
                const ListTile(
                  subtitle: Text(
                    'Ninguno. Pulsa "Añadir enlace XMLTV" si tu proveedor te dio uno.',
                  ),
                ),
              for (final u in urls)
                ListTile(
                  leading: const Icon(Icons.link),
                  title: Text(u, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    tooltip: 'Quitar',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        app.updateSettings((s) => s.epgUrls.remove(u)),
                  ),
                ),
              const Divider(),
              const ListTile(title: Text('Incluidos en tus listas')),
              if (included.isEmpty) const ListTile(subtitle: Text('Ninguno')),
              for (final (name, u) in included)
                ListTile(
                  leading: const Icon(Icons.playlist_play),
                  title: Text(name),
                  subtitle: Text(
                    u.replaceAll(RegExp(r'password=[^&]*'), 'password=***'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
