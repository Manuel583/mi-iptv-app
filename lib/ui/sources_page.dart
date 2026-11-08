import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../parsers.dart';
import 'common.dart';

String _ago(DateTime? d) {
  if (d == null) return 'nunca';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'hace un momento';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  return 'hace ${diff.inDays} días';
}

class SourcesPage extends StatelessWidget {
  const SourcesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis listas'),
        actions: [
          ListenableBuilder(
            listenable: app,
            builder: (context, _) => IconButton(
              tooltip: 'Actualizar todas',
              icon: const Icon(Icons.refresh),
              onPressed: app.refreshing ? null : app.refreshAll,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'nueva-lista',
        icon: const Icon(Icons.add),
        label: const Text('Añadir lista'),
        onPressed: () => showAddSourceMenu(context),
      ),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          if (app.sources.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Todavía no has añadido ninguna lista.',
                    textAlign: TextAlign.center),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              if (app.refreshStatus.isNotEmpty)
                ListTile(
                  leading: const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  title: Text(app.refreshStatus),
                ),
              for (final s in app.sources)
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    leading: Icon(
                      s.type == SourceType.xtream
                          ? Icons.dns_outlined
                          : s.type == SourceType.m3uFile
                              ? Icons.insert_drive_file_outlined
                              : Icons.link,
                      color: s.enabled ? null : Colors.grey,
                    ),
                    title: Text(s.name),
                    subtitle: Text(
                      '${sourceTypeLabel(s.type)} | ${s.channelCount} canales | actualizada ${_ago(s.lastUpdated)}'
                      '${s.enabled ? '' : ' | DESACTIVADA'}'
                      '${s.lastError != null ? '\nError: ${s.lastError}' : ''}',
                      style: s.lastError != null
                          ? TextStyle(color: Theme.of(context).colorScheme.error)
                          : null,
                    ),
                    isThreeLine: s.lastError != null,
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        switch (v) {
                          case 'refresh':
                            final err = await app.refreshSource(s);
                            await app.refreshEpg();
                            if (context.mounted) {
                              showMessage(context,
                                  err ?? 'Lista "${s.name}" actualizada');
                            }
                            break;
                          case 'edit':
                            await showSourceEditor(context, existing: s);
                            break;
                          case 'toggle':
                            app.setSourceEnabled(s, !s.enabled);
                            break;
                          case 'delete':
                            if (await confirm(
                                context,
                                'Eliminar lista',
                                '¿Eliminar "${s.name}"? Tus favoritos y carpetas se conservan, '
                                    'pero sus canales dejarán de aparecer.',
                                ok: 'Eliminar')) {
                              await app.removeSource(s);
                            }
                            break;
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'refresh', child: Text('Actualizar ahora')),
                        const PopupMenuItem(value: 'edit', child: Text('Editar')),
                        PopupMenuItem(
                            value: 'toggle',
                            child: Text(s.enabled ? 'Desactivar' : 'Activar')),
                        const PopupMenuItem(
                            value: 'delete', child: Text('Eliminar')),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

Future<void> showAddSourceMenu(BuildContext context) async {
  final type = await showModalBottomSheet<SourceType>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text('¿Cómo quieres añadir la lista?')),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Enlace M3U'),
            subtitle: const Text('Una dirección que termina en .m3u o .m3u8'),
            onTap: () => Navigator.pop(ctx, SourceType.m3uUrl),
          ),
          ListTile(
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: const Text('Archivo M3U'),
            subtitle: const Text('Un archivo guardado en este dispositivo'),
            onTap: () => Navigator.pop(ctx, SourceType.m3uFile),
          ),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Servidor, usuario y contraseña'),
            subtitle: const Text('Xtream Codes'),
            onTap: () => Navigator.pop(ctx, SourceType.xtream),
          ),
        ],
      ),
    ),
  );
  if (type == null || !context.mounted) return;
  await showSourceEditor(context, type: type);
}

Future<void> showSourceEditor(BuildContext context,
    {PlaylistSource? existing, SourceType? type}) async {
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => SourceEditorPage(
        existing: existing, type: existing?.type ?? type ?? SourceType.m3uUrl),
  ));
}

class SourceEditorPage extends StatefulWidget {
  const SourceEditorPage({super.key, this.existing, required this.type});
  final PlaylistSource? existing;
  final SourceType type;

  @override
  State<SourceEditorPage> createState() => _SourceEditorPageState();
}

class _SourceEditorPageState extends State<SourceEditorPage> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _url = TextEditingController(text: widget.existing?.url ?? '');
  late final _server =
      TextEditingController(text: widget.existing?.server ?? '');
  late final _user =
      TextEditingController(text: widget.existing?.username ?? '');
  late final _pass =
      TextEditingController(text: widget.existing?.password ?? '');
  late final _epg = TextEditingController(text: widget.existing?.epgUrl ?? '');
  late String _output = widget.existing?.xtreamOutput ?? 'ts';
  late bool _useIncludedEpg = widget.existing?.useIncludedEpg ?? true;
  String? _fileContent;
  String? _fileName;
  bool _busy = false;
  bool _showPass = false;

  Future<void> _pickFile() async {
    final f = await FilePicker.pickFile(dialogTitle: 'Elige la lista M3U');
    if (f == null) return;
    final bytes = await f.readAsBytes();
    setState(() {
      _fileContent = utf8.decode(bytes, allowMalformed: true);
      _fileName = f.name;
      if (_name.text.trim().isEmpty) {
        _name.text = f.name.replaceAll(RegExp(r'\.m3u8?$'), '');
      }
    });
  }

  Future<void> _save() async {
    final type = widget.type;
    String name = _name.text.trim();
    if (type == SourceType.m3uUrl) {
      final u = _url.text.trim();
      if (!u.startsWith('http')) {
        showMessage(context, 'Escribe un enlace que empiece por http:// o https://');
        return;
      }
      // Si es un enlace de Xtream (get.php?username=..), se ofrece usarlo así.
      if (name.isEmpty) name = Uri.tryParse(u)?.host ?? 'Lista M3U';
    } else if (type == SourceType.m3uFile) {
      if (_fileContent == null && widget.existing == null) {
        showMessage(context, 'Elige primero un archivo');
        return;
      }
      if (name.isEmpty) name = _fileName ?? 'Archivo M3U';
    } else {
      if (_server.text.trim().isEmpty ||
          _user.text.trim().isEmpty ||
          _pass.text.isEmpty) {
        showMessage(context, 'Rellena servidor, usuario y contraseña');
        return;
      }
      if (name.isEmpty) name = normalizeServer(_server.text);
    }

    setState(() => _busy = true);
    final s = widget.existing ?? app.newSource(name, type);
    s
      ..name = name
      ..url = _url.text.trim()
      ..server = normalizeServer(_server.text)
      ..username = _user.text.trim()
      ..password = _pass.text
      ..xtreamOutput = _output
      ..epgUrl = _epg.text.trim()
      ..useIncludedEpg = _useIncludedEpg;
    String? err;
    if (widget.existing == null) {
      err = await app.addSource(s, fileContent: _fileContent);
    } else {
      await app.updateSource(s, fileContent: _fileContent);
      err = s.lastError;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      showMessage(context, 'Lista guardada, pero hubo un problema: $err');
    } else {
      showMessage(context, 'Lista "${s.name}" cargada: ${s.channelCount} canales');
    }
    Navigator.pop(context);
  }

  void _maybeExtractXtream(String v) {
    final x = extractXtreamFromUrl(v);
    if (x != null) {
      setState(() {
        _server.text = x.$1;
        _user.text = x.$2;
        _pass.text = x.$3;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.type;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null
            ? 'Añadir ${sourceTypeLabel(type)}'
            : 'Editar lista'),
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nombre de la lista (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (type == SourceType.m3uUrl)
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Enlace de la lista M3U',
                  hintText: 'https://…/lista.m3u',
                  border: OutlineInputBorder(),
                ),
              ),
            if (type == SourceType.m3uFile) ...[
              OutlinedButton.icon(
                icon: const Icon(Icons.folder_open),
                label: Text(_fileName ??
                    (widget.existing != null
                        ? 'Sustituir por otro archivo'
                        : 'Elegir archivo M3U')),
                onPressed: _pickFile,
              ),
              const SizedBox(height: 8),
              const Text(
                  'El archivo se copia dentro de la aplicación, así que puedes borrarlo después. '
                  'Para cambiar su contenido, edita la lista y elige el archivo nuevo.'),
            ],
            if (type == SourceType.xtream) ...[
              TextField(
                controller: _server,
                keyboardType: TextInputType.url,
                onChanged: _maybeExtractXtream,
                decoration: const InputDecoration(
                  labelText: 'Servidor',
                  hintText: 'http://servidor.com:8080',
                  helperText:
                      'También puedes pegar aquí el enlace completo con username y password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _user,
                decoration: const InputDecoration(
                  labelText: 'Usuario',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pass,
                obscureText: !_showPass,
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _showPass ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showPass = !_showPass),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _output,
                decoration: const InputDecoration(
                  labelText: 'Formato de emisión',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'ts', child: Text('MPEG-TS (.ts), recomendado')),
                  DropdownMenuItem(value: 'm3u8', child: Text('HLS (.m3u8)')),
                ],
                onChanged: (v) => setState(() => _output = v ?? 'ts'),
              ),
            ],
            const SizedBox(height: 24),
            Text('Guía de programación (EPG)',
                style: Theme.of(context).textTheme.titleMedium),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Usar la guía incluida en la lista'),
              subtitle: Text(type == SourceType.xtream
                  ? 'Se descarga del propio servidor'
                  : 'Si la lista indica un enlace de guía (url-tvg)'),
              value: _useIncludedEpg,
              onChanged: (v) => setState(() => _useIncludedEpg = v),
            ),
            TextField(
              controller: _epg,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Enlace XMLTV adicional (opcional)',
                hintText: 'https://…/guia.xml o .xml.gz',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(_busy ? 'Cargando canales…' : 'Guardar y cargar'),
              onPressed: _busy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
