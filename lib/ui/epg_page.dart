import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'common.dart';

const _days = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

class EpgPage extends StatelessWidget {
  const EpgPage({super.key, required this.channel});
  final Channel channel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Programación | ${app.channelName(channel)}')),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final list = app.programmesFor(channel);
          if (list == null || list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  app.epgLoading
                      ? 'Cargando la guía…'
                      : 'No hay guía de programación para este canal.\n\n'
                          'Puedes añadir un enlace de guía (XMLTV) en Ajustes o en la configuración de la lista.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final now = DateTime.now();
          final visible = list.where((p) => p.stop.isAfter(now)).toList();
          return ListView.builder(
            itemCount: visible.length,
            itemBuilder: (context, i) {
              final p = visible[i];
              final live = p.isNow(now);
              final showDay = i == 0 || visible[i - 1].start.day != p.start.day;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showDay)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text(
                        '${_days[p.start.weekday - 1]} ${p.start.day}/${p.start.month}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ListTile(
                    selected: live,
                    leading: Text(hhmm(p.start),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    title: Text(p.title.isEmpty ? 'Sin título' : p.title),
                    subtitle: live
                        ? LinearProgressIndicator(value: p.progress(now))
                        : (p.desc.isEmpty
                            ? null
                            : Text(p.desc,
                                maxLines: 2, overflow: TextOverflow.ellipsis)),
                    onTap: p.desc.isEmpty
                        ? null
                        : () => showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text(p.title),
                                content: SingleChildScrollView(
                                  child: Text(
                                      '${hhmm(p.start)} - ${hhmm(p.stop)}\n\n${p.desc}'),
                                ),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('Cerrar')),
                                ],
                              ),
                            ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
