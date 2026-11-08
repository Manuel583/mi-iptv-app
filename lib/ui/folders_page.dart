import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'common.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final list = app.favoriteChannels();
        return Column(
          children: [
            _Toolbar(
              text: _editing
                  ? 'Arrastra para ordenar tus favoritos'
                  : '${list.length} favoritos',
              editing: _editing,
              onEdit: list.isEmpty
                  ? null
                  : () => setState(() => _editing = !_editing),
              onMosaic: list.isEmpty
                  ? null
                  : () => openMosaic(context, list.take(4).toList()),
            ),
            Expanded(
              child: ChannelListView(
                channels: list,
                editing: _editing,
                showGroup: true,
                onReorder: app.reorderFavorites,
                emptyText: 'Aún no tienes favoritos.\nPulsa la estrella de cualquier canal para añadirlo aquí.',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.text,
    required this.editing,
    this.onEdit,
    this.onMosaic,
  });
  final String text;
  final bool editing;
  final VoidCallback? onEdit;
  final VoidCallback? onMosaic;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
          IconButton(
            tooltip: 'Ver en mosaico',
            icon: const Icon(Icons.grid_view),
            onPressed: onMosaic,
          ),
          IconButton(
            tooltip: editing ? 'Terminar' : 'Ordenar',
            icon: Icon(editing ? Icons.check : Icons.swap_vert),
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

class FoldersPage extends StatefulWidget {
  const FoldersPage({super.key});

  @override
  State<FoldersPage> createState() => _FoldersPageState();
}

class _FoldersPageState extends State<FoldersPage> {
  bool _editing = false;

  Future<void> _create() async {
    final name = await askText(
      context,
      title: 'Nueva carpeta',
      label: 'Nombre (p. ej. "Oriente Medio")',
    );
    if (name != null && name.trim().isNotEmpty) app.createFolder(name);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final folders = app.custom.folders;
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'nueva-carpeta',
            onPressed: _create,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('Nueva carpeta'),
          ),
          body: Column(
            children: [
              _Toolbar(
                text: _editing
                    ? 'Arrastra para ordenar tus carpetas'
                    : '${folders.length} carpetas',
                editing: _editing,
                onEdit: folders.isEmpty
                    ? null
                    : () => setState(() => _editing = !_editing),
              ),
              Expanded(
                child: folders.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Crea carpetas para agrupar canales a tu gusto, '
                            'por ejemplo "EE. UU.", "Oriente Medio" o "Elecciones".\n\n'
                            'Después, en cualquier canal pulsa los tres puntos y elige '
                            '"Añadir a una carpeta".',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: folders.length,
                        onReorderItem: app.reorderFolders,
                        itemBuilder: (context, i) {
                          final f = folders[i];
                          return ListTile(
                            key: ValueKey(f.id),
                            leading: _editing
                                ? ReorderableDragStartListener(
                                    index: i,
                                    child: const Icon(Icons.drag_handle),
                                  )
                                : const Icon(Icons.folder),
                            title: Text(f.name),
                            subtitle: Text(
                              '${app.folderChannels(f).length} canales',
                            ),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => FolderPage(folder: f),
                              ),
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) async {
                                if (v == 'rename') {
                                  final n = await askText(
                                    context,
                                    title: 'Renombrar carpeta',
                                    initial: f.name,
                                    okText: 'Guardar',
                                  );
                                  if (n != null && n.trim().isNotEmpty) {
                                    app.renameFolder(f, n);
                                  }
                                } else if (v == 'delete') {
                                  if (await confirm(
                                    context,
                                    'Eliminar carpeta',
                                    '¿Eliminar "${f.name}"? Los canales no se borran.',
                                    ok: 'Eliminar',
                                  )) {
                                    app.deleteFolder(f);
                                  }
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text('Renombrar'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Eliminar'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class FolderPage extends StatefulWidget {
  const FolderPage({super.key, required this.folder});
  final Folder folder;

  @override
  State<FolderPage> createState() => _FolderPageState();
}

class _FolderPageState extends State<FolderPage> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final list = app.folderChannels(widget.folder);
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.folder.name),
            actions: [
              IconButton(
                tooltip: 'Ver en mosaico',
                icon: const Icon(Icons.grid_view),
                onPressed: list.isEmpty
                    ? null
                    : () => openMosaic(context, list.take(4).toList()),
              ),
              IconButton(
                tooltip: _editing ? 'Terminar' : 'Ordenar',
                icon: Icon(_editing ? Icons.check : Icons.swap_vert),
                onPressed: list.isEmpty
                    ? null
                    : () => setState(() => _editing = !_editing),
              ),
            ],
          ),
          body: ChannelListView(
            channels: list,
            editing: _editing,
            folder: widget.folder,
            showGroup: true,
            onReorder: (o, n) => app.reorderFolderChannels(widget.folder, o, n),
            emptyText: 'Esta carpeta está vacía.\nEn cualquier canal pulsa los tres puntos y elige "Añadir a una carpeta".',
          ),
        );
      },
    );
  }
}
