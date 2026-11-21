import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../models.dart';
import 'epg_page.dart';
import 'mosaic_page.dart';
import 'player_page.dart';

String hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Future<String?> askText(
  BuildContext context, {
  required String title,
  String initial = '',
  String label = 'Nombre',
  String okText = 'Aceptar',
}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text),
          child: Text(okText),
        ),
      ],
    ),
  );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String text, {
  String ok = 'Aceptar',
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

void openPlayer(BuildContext context, List<Channel> list, int index) {
  if (list.isEmpty) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PlayerPage(channels: list, initialIndex: index),
    ),
  );
}

void openMosaic(BuildContext context, List<Channel?> initial) {
  Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => MosaicPage(initial: initial)));
}

class ChannelLogo extends StatelessWidget {
  const ChannelLogo(this.channel, {super.key, this.size = 44});
  final Channel channel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        app.channelName(channel).trim().isEmpty
            ? '?'
            : app.channelName(channel).trim()[0].toUpperCase(),
        style: TextStyle(
          color: cs.onPrimaryContainer,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    if (channel.logo.isEmpty || !channel.logo.startsWith('http')) {
      return fallback;
    }
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          channel.logo,
          fit: BoxFit.contain,
          cacheWidth: (size * 2).round(),
          errorBuilder: (_, _, _) => fallback,
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : fallback,
        ),
      ),
    );
  }
}

/// Fila de canal reutilizable en todas las listas.
class ChannelTile extends StatelessWidget {
  const ChannelTile({
    super.key,
    required this.channel,
    required this.onTap,
    this.folder,
    this.trailing,
    this.showGroup = false,
  });

  final Channel channel;
  final VoidCallback onTap;
  final Folder? folder;
  final Widget? trailing;
  final bool showGroup;

  @override
  Widget build(BuildContext context) {
    app.requestProgrammes(channel);
    final (now, next) = app.nowNext(channel);
    final hidden = app.isHidden(channel);
    final fav = app.isFavorite(channel);
    final cs = Theme.of(context).colorScheme;
    final subtitleParts = <String>[];
    if (showGroup) subtitleParts.add(app.groupName(channel.group));
    Widget? subtitle;
    if (now != null) {
      subtitle = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${hhmm(now.start)} ${now.title}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          LinearProgressIndicator(
            value: now.progress(DateTime.now()),
            minHeight: 3,
            borderRadius: BorderRadius.circular(2),
          ),
          if (next != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Después: ${hhmm(next.start)} ${next.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (subtitleParts.isNotEmpty)
            Text(
              subtitleParts.join(' | '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      );
    } else if (subtitleParts.isNotEmpty) {
      subtitle = Text(
        subtitleParts.join(' | '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Opacity(
      opacity: hidden ? 0.45 : 1,
      child: ListTile(
        leading: ChannelLogo(channel),
        title: Text(
          app.channelName(channel),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: subtitle,
        onTap: onTap,
        onLongPress: () => showChannelActions(context, channel, folder: folder),
        trailing:
            trailing ??
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: fav ? 'Quitar de favoritos' : 'Añadir a favoritos',
                  icon: Icon(
                    fav ? Icons.star : Icons.star_border,
                    color: fav ? Colors.amber : null,
                  ),
                  onPressed: () => app.toggleFavorite(channel),
                ),
                IconButton(
                  tooltip: 'Más opciones',
                  icon: Icon(Icons.more_vert, color: cs.onSurfaceVariant),
                  onPressed: () =>
                      showChannelActions(context, channel, folder: folder),
                ),
              ],
            ),
      ),
    );
  }
}

Future<void> showChannelActions(
  BuildContext context,
  Channel c, {
  Folder? folder,
}) async {
  await showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final fav = app.isFavorite(c);
      final hidden = app.custom.hiddenChannels.contains(c.key);
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: ChannelLogo(c, size: 36),
                title: Text(app.channelName(c)),
                subtitle: Text(app.groupName(c.group)),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.play_arrow),
                title: const Text('Reproducir'),
                onTap: () {
                  Navigator.pop(ctx);
                  openPlayer(context, [c], 0);
                },
              ),
              ListTile(
                leading: const Icon(Icons.grid_view),
                title: const Text('Abrir en mosaico'),
                onTap: () {
                  Navigator.pop(ctx);
                  openMosaic(context, [c, null]);
                },
              ),
              ListTile(
                leading: Icon(fav ? Icons.star : Icons.star_border),
                title: Text(fav ? 'Quitar de favoritos' : 'Añadir a favoritos'),
                onTap: () {
                  app.toggleFavorite(c);
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('Añadir a una carpeta…'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await pickFolderAndAdd(context, c);
                },
              ),
              if (folder != null)
                ListTile(
                  leading: const Icon(Icons.folder_off_outlined),
                  title: Text('Quitar de "${folder.name}"'),
                  onTap: () {
                    app.removeFromFolder(folder, c);
                    Navigator.pop(ctx);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Renombrar'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final name = await askText(
                    context,
                    title: 'Renombrar canal',
                    initial: app.channelName(c),
                    okText: 'Guardar',
                  );
                  if (name != null) app.renameChannel(c, name);
                },
              ),
              ListTile(
                leading: Icon(
                  hidden
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                title: Text(hidden ? 'Mostrar canal' : 'Ocultar canal'),
                onTap: () {
                  app.setChannelHidden(c, !hidden);
                  Navigator.pop(ctx);
                  if (!hidden && !app.settings.showHidden) {
                    showMessage(
                      context,
                      'Canal ocultado. Puedes volver a verlo activando "Mostrar ocultos" en Ajustes.',
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.calendar_view_day_outlined),
                title: const Text('Ver programación'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => EpgPage(channel: c)),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Copiar enlace del canal'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: c.url));
                  Navigator.pop(ctx);
                  showMessage(context, 'Enlace copiado');
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> pickFolderAndAdd(BuildContext context, Channel c) async {
  final result = await showDialog<Object>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Añadir a carpeta'),
      children: [
        for (final f in app.custom.folders)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, f),
            child: ListTile(
              leading: Icon(
                f.channelKeys.contains(c.key)
                    ? Icons.folder
                    : Icons.folder_outlined,
              ),
              title: Text(f.name),
              subtitle: Text('${f.channelKeys.length} canales'),
            ),
          ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'new'),
          child: const ListTile(
            leading: Icon(Icons.add),
            title: Text('Nueva carpeta…'),
          ),
        ),
      ],
    ),
  );
  if (!context.mounted || result == null) return;
  Folder? folder;
  if (result == 'new') {
    final name = await askText(
      context,
      title: 'Nueva carpeta',
      label: 'Nombre (p. ej. "Elecciones")',
    );
    if (name == null || name.trim().isEmpty) return;
    folder = app.createFolder(name);
  } else {
    folder = result as Folder;
  }
  app.addToFolder(folder, c);
  if (context.mounted) showMessage(context, 'Añadido a "${folder.name}"');
}

/// Lista de canales con modo de edición opcional (reordenar, ocultar).
class ChannelListView extends StatelessWidget {
  const ChannelListView({
    super.key,
    required this.channels,
    this.editing = false,
    this.onReorder,
    this.folder,
    this.showGroup = false,
    this.emptyText = 'No hay canales',
  });

  final List<Channel> channels;
  final bool editing;
  final void Function(int oldIndex, int newIndex)? onReorder;
  final Folder? folder;
  final bool showGroup;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(emptyText, textAlign: TextAlign.center),
        ),
      );
    }
    if (editing && onReorder != null) {
      return ReorderableListView.builder(
        buildDefaultDragHandles: false,
        itemCount: channels.length,
        onReorderItem: onReorder!,
        itemBuilder: (context, i) {
          final c = channels[i];
          final hidden = app.custom.hiddenChannels.contains(c.key);
          return Opacity(
            key: ValueKey(c.key),
            opacity: hidden ? 0.45 : 1,
            child: ListTile(
              leading: ReorderableDragStartListener(
                index: i,
                child: const Icon(Icons.drag_handle),
              ),
              title: Text(
                app.channelName(c),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Renombrar',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      final name = await askText(
                        context,
                        title: 'Renombrar canal',
                        initial: app.channelName(c),
                        okText: 'Guardar',
                      );
                      if (name != null) app.renameChannel(c, name);
                    },
                  ),
                  if (folder == null)
                    IconButton(
                      tooltip: hidden ? 'Mostrar' : 'Ocultar',
                      icon: Icon(
                        hidden
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () => app.setChannelHidden(c, !hidden),
                    )
                  else
                    IconButton(
                      tooltip: 'Quitar de la carpeta',
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => app.removeFromFolder(folder!, c),
                    ),
                ],
              ),
            ),
          );
        },
      );
    }
    return ListView.builder(
      itemCount: channels.length,
      itemBuilder: (context, i) => ChannelTile(
        channel: channels[i],
        folder: folder,
        showGroup: showGroup,
        onTap: () => openPlayer(context, channels, i),
      ),
    );
  }
}
