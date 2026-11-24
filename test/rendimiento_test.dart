// Pruebas de rendimiento con una lista enorme (como las de muchos
// proveedores IPTV): 120.000 canales y 80.000 películas.
// Se ejecutan con: flutter test test/rendimiento_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_iptv/app_state.dart';
import 'package:mi_iptv/models.dart';

const _palabras = [
  'Deportes',
  'Noticias',
  'Cine',
  'Música',
  'Infantil',
  'Documentales',
  'Fútbol',
  'Series',
  'Cocina',
  'Viajes',
];

List<Channel> _listaEnorme() {
  final out = <Channel>[];
  for (var i = 0; i < 120000; i++) {
    final g = 'ES | ${_palabras[i % _palabras.length]} ${i % 400}';
    out.add(
      Channel(
        key: 'big|$g|Canal $i',
        sourceId: 'big',
        name: 'Canal ${_palabras[(i ~/ 7) % _palabras.length]} $i HD',
        url: 'http://example.com/$i.ts',
        group: g,
        country: i.isEven ? 'España' : 'Portugal',
      ),
    );
  }
  for (var i = 0; i < 80000; i++) {
    final g = 'Películas ${i % 200}';
    out.add(
      Channel(
        key: 'big|$g|Película $i',
        sourceId: 'big',
        name: 'Película número $i (${1950 + i % 75})',
        url: 'http://example.com/movie/$i.mp4',
        group: g,
        kind: ContentKind.movie,
      ),
    );
  }
  return out;
}

int _ms(void Function() f) {
  final sw = Stopwatch()..start();
  f();
  return sw.elapsedMilliseconds;
}

void main() {
  test('La app va fluida con 200.000 canales y películas', () {
    final src = PlaylistSource(
      id: 'big',
      name: 'Enorme',
      type: SourceType.m3uUrl,
    );
    app.debugSetData(src, _listaEnorme());

    // Primera búsqueda (prepara el índice) y luego escribir letra a letra.
    final primera = _ms(() => app.search('c'));
    var peorTecla = 0;
    var texto = '';
    for (final letra in 'canal deportes 12'.split('')) {
      texto += letra;
      final t = _ms(() => app.search(texto));
      if (t > peorTecla) peorTecla = t;
    }
    expect(app.search('canal deportes 12'), isNotEmpty);
    expect(app.search('pelicula 1999'), isNotEmpty); // sin tilde también vale

    // Cambiar una opción y volver a pintar las listas varias veces.
    final opcion = _ms(() {
      app.updateSettings((s) => s.showStats = !s.showStats);
      for (var i = 0; i < 5; i++) {
        app.groups();
        app.countries();
        app.movieGroups();
        app.smartFolders();
        app.channelsInGroup('ES | Deportes 0');
      }
    });

    // ignore: avoid_print
    print(
      'Rendimiento | primera búsqueda: $primera ms | peor tecla: $peorTecla ms'
      ' | cambiar una opción y redibujar: $opcion ms',
    );
    expect(peorTecla, lessThan(150));
    expect(opcion, lessThan(1500));
  });
}
