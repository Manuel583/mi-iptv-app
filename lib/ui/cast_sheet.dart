import 'dart:async';

import 'package:flutter/material.dart';

import '../cast.dart';

/// Busca teles en casa y devuelve la elegida y si la señal pasa por aquí.
class CastSheet extends StatefulWidget {
  const CastSheet({super.key, required this.needsRelay});

  /// El canal necesita datos especiales (User-Agent, Referer).
  final bool needsRelay;

  @override
  State<CastSheet> createState() => _CastSheetState();
}

class _CastSheetState extends State<CastSheet> {
  final _devices = <CastDevice>[];
  StreamSubscription<CastDevice>? _sub;
  bool _searching = false;
  late bool _relay = widget.needsRelay;

  @override
  void initState() {
    super.initState();
    _search();
  }

  void _search() {
    _sub?.cancel();
    for (final d in _devices) {
      d.close();
    }
    setState(() {
      _devices.clear();
      _searching = true;
    });
    _sub = discoverCastDevices().listen(
      (d) {
        if (!mounted) return;
        if (_devices.any((x) => x.id == d.id)) return;
        setState(() => _devices.add(d));
      },
      onDone: () {
        if (mounted) setState(() => _searching = false);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('Emitir en la tele'),
              subtitle: const Text(
                'La tele y este dispositivo tienen que estar en la misma wifi',
              ),
              trailing: _searching
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      tooltip: 'Buscar otra vez',
                      icon: const Icon(Icons.refresh),
                      onPressed: _search,
                    ),
            ),
            const Divider(height: 1),
            if (_devices.isEmpty)
              ListTile(
                leading: const Icon(Icons.search),
                title: Text(
                  _searching
                      ? 'Buscando teles…'
                      : 'No he encontrado ninguna tele',
                ),
                subtitle: _searching
                    ? null
                    : const Text(
                        'Comprueba que la tele está encendida. En las Samsung, '
                        'activa en Ajustes | Conexión | Administrador de '
                        'dispositivos externos | "Notificación de acceso" o '
                        '"Compartir contenido".',
                      ),
              ),
            for (final d in _devices)
              ListTile(
                leading: Icon(
                  d.kind == CastKind.chromecast ? Icons.cast : Icons.tv,
                ),
                title: Text(d.name),
                subtitle: Text(
                  d.kind == CastKind.chromecast
                      ? 'Chromecast'
                      : 'DLNA | ${d.host}',
                ),
                onTap: () {
                  _sub?.cancel();
                  for (final x in _devices) {
                    if (x != d) x.close();
                  }
                  Navigator.pop(context, (
                    d,
                    _relay || d.kind == CastKind.chromecast,
                  ));
                },
              ),
            const Divider(height: 1),
            SwitchListTile(
              title: const Text('Pasar la señal por este dispositivo'),
              subtitle: const Text(
                'Actívalo si la tele no abre el canal. Este dispositivo tiene '
                'que seguir encendido y con la app abierta mientras emites. '
                'En Chromecast se usa siempre.',
              ),
              value: _relay,
              onChanged: (v) => setState(() => _relay = v),
            ),
          ],
        ),
      ),
    );
  }
}
