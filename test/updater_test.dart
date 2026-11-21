import 'package:flutter_test/flutter_test.dart';
import 'package:mi_iptv/updater.dart';

void main() {
  test('compara versiones', () {
    expect(compareVersions('1.0.10', '1.0.9'), greaterThan(0));
    expect(compareVersions('v1.0.5', '1.0.5'), 0);
    expect(compareVersions('1.0.4', '1.0.5'), lessThan(0));
    expect(compareVersions('1.1.0', '1.0.99'), greaterThan(0));
  });

  test('elige el archivo del sistema en la release', () {
    final r = ReleaseInfo.fromJson({
      'tag_name': 'v1.0.7',
      'name': 'Mi IPTV 1.0.7',
      'body': 'Notas',
      'assets': [
        {
          'name': 'mi-iptv-windows-instalador.exe',
          'url': 'https://a/1',
          'size': 10,
        },
        {'name': 'mi-iptv-android.apk', 'url': 'https://a/2', 'size': 20},
      ],
    }, asset: 'mi-iptv-android.apk');
    expect(r.version, '1.0.7');
    expect(r.assetApiUrl, 'https://a/2');
    expect(r.assetSize, 20);
    expect(r.isNewer, isTrue); // en pruebas la versión instalada es 0.0.0
  });
}
