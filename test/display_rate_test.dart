import 'package:flutter_test/flutter_test.dart';
import 'package:mi_iptv/display_rate.dart';

void main() {
  test('25 fps en 50 Hz encaja y en 60 Hz no', () {
    expect(syncFor(25, 50).quality, SyncQuality.perfect);
    expect(syncFor(25, 50).repeats, 2);
    expect(syncFor(25, 60).quality, SyncQuality.bad);
    expect(syncFor(50, 60).quality, SyncQuality.bad);
    expect(syncFor(60, 60).quality, SyncQuality.perfect);
    expect(syncFor(30, 90).quality, SyncQuality.perfect);
  });

  test('60 fps en 59,94 Hz va casi bien', () {
    final r = syncFor(60, 59.94);
    expect(r.quality, SyncQuality.almost);
    expect(r.skipEverySeconds, closeTo(16.7, 0.5));
  });

  test('sin datos no se sabe', () {
    expect(syncFor(0, 60).quality, SyncQuality.unknown);
  });

  test('elige el modo de pantalla que encaja', () {
    expect(bestModeFor(25, [60, 50, 144], 60), 50);
    expect(bestModeFor(50, [60, 100, 120], 60), 100);
    expect(bestModeFor(30, [60, 90], 90), 90); // ya encaja: no lo cambia
    expect(bestModeFor(30, [60, 90], 120), 60); // empate: el más bajo
    expect(bestModeFor(25, [60, 90], 60), isNull); // Pixel 7: no hay 50 Hz
    expect(bestModeFor(23.976, [60, 48, 120], 60), 48);
  });
}
