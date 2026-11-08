import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'common.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctrl = TextEditingController();
  List<Channel> _results = const [];

  void _run(String q) => setState(() => _results = app.search(q));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          onChanged: _run,
          decoration: const InputDecoration(
            hintText: 'Buscar canal o grupo…',
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_ctrl.text.isNotEmpty)
            IconButton(
              tooltip: 'Borrar',
              icon: const Icon(Icons.clear),
              onPressed: () {
                _ctrl.clear();
                _run('');
              },
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) => ChannelListView(
          channels: _results,
          showGroup: true,
          emptyText: _ctrl.text.isEmpty
              ? 'Escribe el nombre de un canal'
              : 'No se han encontrado canales',
        ),
      ),
    );
  }
}

/// Diálogo para elegir un canal (se usa en el mosaico).
Future<Channel?> pickChannel(BuildContext context) {
  return showDialog<Channel>(
    context: context,
    builder: (ctx) => const Dialog(
      insetPadding: EdgeInsets.all(16),
      child: SizedBox(width: 560, height: 640, child: _ChannelPicker()),
    ),
  );
}

class _ChannelPicker extends StatefulWidget {
  const _ChannelPicker();

  @override
  State<_ChannelPicker> createState() => _ChannelPickerState();
}

class _ChannelPickerState extends State<_ChannelPicker> {
  final _ctrl = TextEditingController();
  late List<Channel> _list = _initial();

  List<Channel> _initial() {
    final favs = app.favoriteChannels();
    return favs.isNotEmpty ? favs : app.allChannels.take(300).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            onChanged: (q) => setState(
                () => _list = q.trim().isEmpty ? _initial() : app.search(q)),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar canal (se muestran tus favoritos)',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: _list.isEmpty
              ? const Center(child: Text('Sin resultados'))
              : ListView.builder(
                  itemCount: _list.length,
                  itemBuilder: (context, i) {
                    final c = _list[i];
                    return ListTile(
                      leading: ChannelLogo(c, size: 36),
                      title: Text(app.channelName(c),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(app.groupName(c.group),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(context, c),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
          ),
        ),
      ],
    );
  }
}
