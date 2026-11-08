// Guía de programación (EPG) en formato XMLTV.
import 'dart:convert';
import 'dart:io';

import 'package:xml/xml_events.dart';

import 'models.dart';
import 'parsers.dart' show normalizeText;

class EpgData {
  EpgData(this.programmes, this.nameToId);
  EpgData.empty() : programmes = {}, nameToId = {};

  /// id de canal (en minúsculas) -> programas ordenados por hora.
  final Map<String, List<Programme>> programmes;

  /// nombre normalizado -> id de canal (en minúsculas).
  final Map<String, String> nameToId;

  bool get isEmpty => programmes.isEmpty;

  void merge(EpgData other) {
    other.programmes.forEach((id, list) {
      final existing = programmes[id];
      if (existing == null || existing.isEmpty) {
        programmes[id] = list;
      }
    });
    other.nameToId.forEach((k, v) => nameToId.putIfAbsent(k, () => v));
  }

  /// Busca la programación de un canal (por tvg-id o por nombre).
  List<Programme>? lookup(Channel c) {
    if (c.tvgId.isNotEmpty) {
      final p = programmes[c.tvgId.toLowerCase()];
      if (p != null) return p;
    }
    for (final n in [c.tvgName, c.name]) {
      if (n.isEmpty) continue;
      final id = nameToId[epgNameKey(n)];
      if (id != null) {
        final p = programmes[id];
        if (p != null) return p;
      }
    }
    return null;
  }
}

/// Clave para comparar nombres de canal: sin tildes, espacios ni sufijos HD.
String epgNameKey(String name) {
  var s = normalizeText(name);
  s = s.replaceAll(RegExp(r'\b(fhd|uhd|hd|sd|4k|hevc|h265)\b'), '');
  s = s.replaceAll(RegExp(r'^[a-z]{2,3}\s*[:|]\s*'), '');
  return s.replaceAll(RegExp(r'[^a-z0-9]'), '');
}

/// Convierte "20240101183000 +0100" en fecha.
DateTime? parseXmltvDate(String s) {
  final t = s.trim();
  if (t.length < 12) return null;
  try {
    final y = int.parse(t.substring(0, 4));
    final mo = int.parse(t.substring(4, 6));
    final d = int.parse(t.substring(6, 8));
    final h = int.parse(t.substring(8, 10));
    final mi = int.parse(t.substring(10, 12));
    final sec = t.length >= 14 ? int.tryParse(t.substring(12, 14)) ?? 0 : 0;
    var dt = DateTime.utc(y, mo, d, h, mi, sec);
    final tz = RegExp(r'([+-])(\d{2}):?(\d{2})').firstMatch(t.substring(12));
    if (tz != null) {
      final sign = tz.group(1) == '-' ? -1 : 1;
      final off = Duration(
        hours: int.parse(tz.group(2)!),
        minutes: int.parse(tz.group(3)!),
      );
      dt = sign == 1 ? dt.subtract(off) : dt.add(off);
    }
    return dt.toLocal();
  } catch (_) {
    return null;
  }
}

/// Lee un archivo XMLTV (también comprimido .gz) quedándose sólo con los
/// programas entre [from] y [to]. Pensado para ejecutarse en segundo plano.
Future<EpgData> parseXmltvFile(String path, DateTime from, DateTime to) async {
  final file = File(path);
  final head = await file.openRead(0, 2).fold<List<int>>([], (a, b) => a + b);
  Stream<List<int>> bytes = file.openRead();
  if (head.length == 2 && head[0] == 0x1f && head[1] == 0x8b) {
    bytes = bytes.transform(gzip.decoder);
  }
  final text = bytes.transform(const Utf8Decoder(allowMalformed: true));
  return parseXmltvStream(text, from, to);
}

Future<EpgData> parseXmltvStream(
  Stream<String> text,
  DateTime from,
  DateTime to,
) async {
  final programmes = <String, List<Programme>>{};
  final nameToId = <String, String>{};

  String? currentChannelId;
  String? progChannel;
  DateTime? progStart;
  DateTime? progStop;
  String title = '';
  String desc = '';
  String? textTarget; // 'display-name' | 'title' | 'desc'
  final buf = StringBuffer();
  var keep = false;

  await for (final events in text.toXmlEvents()) {
    for (final e in events) {
      if (e is XmlStartElementEvent) {
        switch (e.name) {
          case 'channel':
            currentChannelId = _attr(e, 'id')?.toLowerCase();
            break;
          case 'display-name':
            if (currentChannelId != null && !e.isSelfClosing) {
              textTarget = 'display-name';
              buf.clear();
            }
            break;
          case 'programme':
            progChannel = _attr(e, 'channel')?.toLowerCase();
            progStart = parseXmltvDate(_attr(e, 'start') ?? '');
            progStop = parseXmltvDate(_attr(e, 'stop') ?? '');
            title = '';
            desc = '';
            keep =
                progChannel != null &&
                progStart != null &&
                (progStop ?? progStart.add(const Duration(hours: 1))).isAfter(
                  from,
                ) &&
                progStart.isBefore(to);
            break;
          case 'title':
            if (keep && title.isEmpty && !e.isSelfClosing) {
              textTarget = 'title';
              buf.clear();
            }
            break;
          case 'desc':
            if (keep && desc.isEmpty && !e.isSelfClosing) {
              textTarget = 'desc';
              buf.clear();
            }
            break;
        }
      } else if (e is XmlTextEvent) {
        if (textTarget != null) buf.write(e.value);
      } else if (e is XmlCDATAEvent) {
        if (textTarget != null) buf.write(e.value);
      } else if (e is XmlEndElementEvent) {
        switch (e.name) {
          case 'display-name':
            if (textTarget == 'display-name' && currentChannelId != null) {
              final k = epgNameKey(buf.toString());
              if (k.isNotEmpty) {
                nameToId.putIfAbsent(k, () => currentChannelId!);
              }
            }
            textTarget = null;
            break;
          case 'channel':
            currentChannelId = null;
            break;
          case 'title':
            if (textTarget == 'title') title = buf.toString().trim();
            textTarget = null;
            break;
          case 'desc':
            if (textTarget == 'desc') desc = buf.toString().trim();
            textTarget = null;
            break;
          case 'programme':
            if (keep) {
              final start = progStart!;
              final stop = progStop ?? start.add(const Duration(hours: 1));
              (programmes[progChannel!] ??= []).add(
                Programme(start, stop, title, desc),
              );
            }
            keep = false;
            break;
        }
      }
    }
  }
  for (final list in programmes.values) {
    list.sort((a, b) => a.start.compareTo(b.start));
  }
  return EpgData(programmes, nameToId);
}

String? _attr(XmlStartElementEvent e, String name) {
  for (final a in e.attributes) {
    if (a.name == name) return a.value;
  }
  return null;
}

/// Programa en emisión y siguiente.
(Programme?, Programme?) nowAndNext(List<Programme>? list, DateTime now) {
  if (list == null || list.isEmpty) return (null, null);
  // Búsqueda binaria del primer programa que termina después de "now".
  var lo = 0, hi = list.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (list[mid].stop.isAfter(now)) {
      hi = mid;
    } else {
      lo = mid + 1;
    }
  }
  if (lo >= list.length) return (null, null);
  final cur = list[lo];
  if (cur.isNow(now)) {
    return (cur, lo + 1 < list.length ? list[lo + 1] : null);
  }
  return (null, cur);
}
