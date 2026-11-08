import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'common.dart';

enum BrowseMode { groups, countries }

/// Navegación por grupos o por países. En pantallas anchas muestra
/// las categorías a la izquierda y los canales a la derecha.
class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key, required this.mode});
  final BrowseMode mode;

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  String? _selected;
  bool _editingGroups = false;
  final _filter = TextEditingController();

  bool get _isGroups => widget.mode == BrowseMode.groups;

  List<GroupInfo> _categories() {
    final list = _isGroups
        ? app.groups(includeHidden: _editingGroups)
        : app.countries();
    final q = _filter.text.trim().toLowerCase();
    if (q.isEmpty || _editingGroups) return list;
    return list.where((g) => g.name.toLowerCase().contains(q)).toList();
  }

  @override
  void didUpdateWidget(covariant BrowsePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      _selected = null;
      _editingGroups = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final cats = _categories();
        if (wide) {
          final sel = cats.any((c) => c.key == _selected)
              ? _selected
              : (cats.isNotEmpty ? cats.first.key : null);
          return Row(
            children: [
              SizedBox(
                width: 320,
                child: _categoryPanel(cats, sel, onOpen: (k) {
                  setState(() => _selected = k);
                }),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: sel == null
                    ? const Center(child: Text('Sin canales'))
                    : CategoryChannels(
                        key: ValueKey('${widget.mode}|$sel'),
                        mode: widget.mode,
                        categoryKey: sel,
                        embedded: true,
                      ),
              ),
            ],
          );
        }
        return _categoryPanel(cats, null, onOpen: (k) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => CategoryChannels(mode: widget.mode, categoryKey: k),
          ));
        });
      },
    );
  }

  Widget _categoryPanel(List<GroupInfo> cats, String? selected,
      {required void Function(String) onOpen}) {
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: _editingGroups
                ? Text('Arrastra para ordenar | ojo para ocultar',
                    style: Theme.of(context).textTheme.bodySmall)
                : TextField(
                    controller: _filter,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.filter_list),
                      hintText: _isGroups ? 'Filtrar grupos' : 'Filtrar países',
                      border: const OutlineInputBorder(),
                    ),
                  ),
          ),
          if (_isGroups)
            IconButton(
              tooltip: _editingGroups ? 'Terminar edición' : 'Editar grupos',
              icon: Icon(_editingGroups ? Icons.check : Icons.edit_outlined),
              onPressed: () => setState(() => _editingGroups = !_editingGroups),
            ),
        ],
      ),
    );

    if (_editingGroups) {
      return Column(
        children: [
          header,
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: cats.length,
              onReorderItem: app.reorderGroups,
              itemBuilder: (context, i) {
                final g = cats[i];
                return Opacity(
                  key: ValueKey(g.key),
                  opacity: g.hidden ? 0.45 : 1,
                  child: ListTile(
                    leading: ReorderableDragStartListener(
                        index: i, child: const Icon(Icons.drag_handle)),
                    title: Text(g.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Renombrar',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () async {
                            final n = await askText(context,
                                title: 'Renombrar grupo',
                                initial: g.name,
                                okText: 'Guardar');
                            if (n != null) app.renameGroup(g.key, n);
                          },
                        ),
                        IconButton(
                          tooltip: g.hidden ? 'Mostrar' : 'Ocultar',
                          icon: Icon(g.hidden
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          onPressed: () => app.setGroupHidden(g.key, !g.hidden),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextButton.icon(
              icon: const Icon(Icons.restart_alt),
              label: const Text('Restablecer orden original'),
              onPressed: () async {
                if (await confirm(context, 'Restablecer orden',
                    'Se recuperará el orden original de grupos y canales.')) {
                  app.resetGroupOrder();
                }
              },
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        header,
        Expanded(
          child: cats.isEmpty
              ? const Center(child: Text('No hay canales todavía'))
              : ListView.builder(
                  itemCount: cats.length,
                  itemBuilder: (context, i) {
                    final g = cats[i];
                    return Opacity(
                      opacity: g.hidden ? 0.45 : 1,
                      child: ListTile(
                        selected: g.key == selected,
                        leading: Icon(_isGroups
                            ? Icons.folder_open_outlined
                            : Icons.flag_outlined),
                        title: Text(g.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Text('${g.count}'),
                        onTap: () => onOpen(g.key),
                        onLongPress: _isGroups
                            ? () => _groupActions(g)
                            : null,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _groupActions(GroupInfo g) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(g.name)),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Renombrar grupo'),
              onTap: () async {
                Navigator.pop(ctx);
                final n = await askText(context,
                    title: 'Renombrar grupo', initial: g.name, okText: 'Guardar');
                if (n != null) app.renameGroup(g.key, n);
              },
            ),
            ListTile(
              leading: Icon(g.hidden
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
              title: Text(g.hidden ? 'Mostrar grupo' : 'Ocultar grupo'),
              onTap: () {
                Navigator.pop(ctx);
                app.setGroupHidden(g.key, !g.hidden);
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_vert),
              title: const Text('Ordenar u ocultar grupos'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _editingGroups = true);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Canales de un grupo o país.
class CategoryChannels extends StatefulWidget {
  const CategoryChannels({
    super.key,
    required this.mode,
    required this.categoryKey,
    this.embedded = false,
  });

  final BrowseMode mode;
  final String categoryKey;
  final bool embedded;

  @override
  State<CategoryChannels> createState() => _CategoryChannelsState();
}

class _CategoryChannelsState extends State<CategoryChannels> {
  bool _editing = false;
  final _filter = TextEditingController();

  bool get _isGroup => widget.mode == BrowseMode.groups;

  List<Channel> _channels() {
    final list = _isGroup
        ? app.channelsInGroup(widget.categoryKey, includeHidden: _editing)
        : app.channelsInCountry(widget.categoryKey);
    final q = _filter.text.trim().toLowerCase();
    if (q.isEmpty || _editing) return list;
    return list
        .where((c) => app.channelName(c).toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final channels = _channels();
        final title = _isGroup
            ? app.groupName(widget.categoryKey)
            : widget.categoryKey;
        final actions = [
          IconButton(
            tooltip: 'Ver en mosaico',
            icon: const Icon(Icons.grid_view),
            onPressed: channels.isEmpty
                ? null
                : () => openMosaic(context, channels.take(4).toList()),
          ),
          if (_isGroup)
            IconButton(
              tooltip: _editing ? 'Terminar edición' : 'Ordenar, renombrar u ocultar',
              icon: Icon(_editing ? Icons.check : Icons.edit_outlined),
              onPressed: () => setState(() => _editing = !_editing),
            ),
        ];
        final body = Column(
          children: [
            if (!_editing)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: TextField(
                  controller: _filter,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar en esta lista',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            if (_editing)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text('Arrastra para ordenar | lápiz para renombrar | ojo para ocultar',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            Expanded(
              child: ChannelListView(
                channels: channels,
                editing: _editing,
                showGroup: !_isGroup,
                onReorder: _isGroup
                    ? (o, n) =>
                        app.reorderChannelsInGroup(widget.categoryKey, o, n)
                    : null,
              ),
            ),
          ],
        );
        if (widget.embedded) {
          return Column(
            children: [
              Material(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('$title (${channels.length})',
                            style: Theme.of(context).textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      ...actions,
                    ],
                  ),
                ),
              ),
              Expanded(child: body),
            ],
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text(title), actions: actions),
          body: body,
        );
      },
    );
  }
}
