import 'dart:io';

import 'package:flutter/material.dart';

import '../models.dart';
import '../recordings.dart';
import 'common.dart';

/// Lista de grabaciones guardadas en el dispositivo.
class RecordingsPage extends StatefulWidget {
  const RecordingsPage({super.key});

  @override
  State<RecordingsPage> createState() => _RecordingsPageState();
}

class _RecordingsPageState extends State<RecordingsPage> {
  late Future<List<File>> _files = Recordings.list();
  String _folder = '';

  @override
  void initState() {
    super.initState();
    Recordings.folder()
        .then((d) {
          if (mounted) setState(() => _folder = d.path);
        })
        .catchError((_) {});
  }

  void _reload() => setState(() => _files = Recordings.list());

  String _title(File f) {
    final name = f.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  void _play(File f) {
    openPlayer(context, [
      Channel(
        key: 'rec:${f.path}',
        sourceId: '',
        name: _title(f),
        url: f.path,
        group: 'Grabaciones',
      ),
    ], 0);
  }

  Future<void> _delete(File f) async {
    final ok = await confirm(
      context,
      'Borrar grabación',
      '¿Borrar "${_title(f)}"? No se puede deshacer.',
      ok: 'Borrar',
    );
    if (!ok) return;
    try {
      await f.delete();
      await Recordings.publish(f.path);
    } catch (e) {
      if (mounted) showMessage(context, 'No se ha podido borrar: $e');
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Grabaciones'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<List<File>>(
        future: _files,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final files = snap.data ?? const <File>[];
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              children: [
                if (_folder.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: const Text('Carpeta'),
                    subtitle: Text(_folder),
                  ),
                if (snap.hasError)
                  ListTile(
                    leading: const Icon(Icons.error_outline),
                    title: Text('No se puede abrir la carpeta: ${snap.error}'),
                  ),
                if (files.isEmpty && !snap.hasError)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Todavía no hay grabaciones.\n\n'
                      'Para grabar, abre un canal y pulsa el botón rojo de grabar. '
                      'La grabación sigue mientras el canal esté abierto y se '
                      'guarda al pulsar otra vez el botón, al cambiar de canal o '
                      'al salir del reproductor.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final f in files)
                  Builder(
                    builder: (context) {
                      final st = f.statSync();
                      return ListTile(
                        leading: const Icon(Icons.movie_outlined),
                        title: Text(
                          _title(f),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${formatBytes(st.size)} | '
                          '${st.modified.day}/${st.modified.month}/${st.modified.year} '
                          '${hhmm(st.modified)}',
                        ),
                        onTap: () => _play(f),
                        trailing: IconButton(
                          tooltip: 'Borrar',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(f),
                        ),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
