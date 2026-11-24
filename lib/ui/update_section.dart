// Apartado "Actualizaciones" de Ajustes (Android y Windows).
import 'package:flutter/material.dart';

import '../updater.dart';
import 'common.dart';

class UpdateSection extends StatelessWidget {
  const UpdateSection({super.key, required this.header});

  final Widget header;

  @override
  Widget build(BuildContext context) {
    if (!Updater.supported) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: updater,
      builder: (context, _) {
        final r = updater.latest;
        final String status;
        if (updater.checking) {
          status = 'Comprobando…';
        } else if (r != null && r.isNewer) {
          status = 'Hay una versión nueva: ${r.version}. Pulsa para instalarla';
        } else if (r != null) {
          status = 'Tienes la última versión';
        } else {
          status = 'Pulsa para comprobar si hay una versión nueva';
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            ListTile(
              leading: Icon(
                r != null && r.isNewer
                    ? Icons.system_update
                    : Icons.system_update_alt,
                color: r != null && r.isNewer
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              title: Text('Buscar actualización (tienes la $appVersion)'),
              subtitle: Text(status),
              trailing: updater.checking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: () => updater.startUpdate(context),
            ),
            ListTile(
              leading: const Icon(Icons.key_outlined),
              title: const Text('Permiso de lectura de GitHub (opcional)'),
              subtitle: Text(
                updater.hasToken
                    ? 'Guardado sólo en este aparato. Pulsa para cambiarlo o quitarlo'
                    : 'Sólo hace falta si el repositorio de la app es privado',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _editToken(context),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editToken(BuildContext context) async {
    final v = await askText(
      context,
      title: 'Permiso de lectura de GitHub',
      label: updater.hasToken
          ? 'Pega uno nuevo, o déjalo vacío para quitarlo'
          : 'Pega aquí el código que empieza por github_pat_',
      okText: 'Guardar',
    );
    if (v == null || !context.mounted) return;
    final t = v.trim();
    if (t.isEmpty && !updater.hasToken) return;
    if (t.isNotEmpty) showMessage(context, 'Comprobando el permiso…');
    try {
      await updater.setToken(t);
      if (!context.mounted) return;
      if (t.isEmpty) {
        showMessage(context, 'Permiso quitado de este aparato');
      } else {
        final r = updater.latest;
        showMessage(
          context,
          r != null && r.isNewer
              ? 'Permiso guardado. Hay una versión nueva (${r.version}).'
              : 'Permiso guardado. Tienes la última versión.',
        );
      }
    } on UpdateError catch (e) {
      if (context.mounted) showMessage(context, e.message);
    }
  }
}
