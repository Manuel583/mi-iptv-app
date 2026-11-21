// Subtítulos en directo generados dentro de la app a partir del sonido del
// canal. El reconocimiento lo hace el propio teléfono (Android 13 o superior),
// gratis. Aquí están: el estado, la capa que los dibuja sobre el vídeo y la
// pantalla para elegir su diseño.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../native.dart';

bool get liveCaptionsPlatform => !kIsWeb && Platform.isAndroid;

// ------------------------------------------------------------------ Diseño

class CaptionStyle {
  CaptionStyle({
    this.fontSize = 24,
    this.textColor = 0xFFFFFFFF,
    this.bgOpacity = 0.6,
    this.top = false,
    this.lines = 2,
    this.bold = true,
    this.outline = false,
    this.language = 'es-ES',
  });

  double fontSize;
  int textColor;
  double bgOpacity;
  bool top;
  int lines;
  bool bold;
  bool outline;
  String language;

  static const languages = {
    'es-ES': 'Español (España)',
    'es-US': 'Español (Latinoamérica)',
  };

  static const colors = <int, String>{
    0xFFFFFFFF: 'Blanco',
    0xFFFFEB3B: 'Amarillo',
    0xFF80DEEA: 'Celeste',
    0xFFA5D6A7: 'Verde',
  };

  Map<String, dynamic> toJson() => {
    'fontSize': fontSize,
    'textColor': textColor,
    'bgOpacity': bgOpacity,
    'top': top,
    'lines': lines,
    'bold': bold,
    'outline': outline,
    'language': language,
  };

  static CaptionStyle fromJson(Map<String, dynamic> j) {
    final s = CaptionStyle();
    s.fontSize = ((j['fontSize'] ?? s.fontSize) as num).toDouble();
    s.textColor = (j['textColor'] ?? s.textColor) as int;
    s.bgOpacity = ((j['bgOpacity'] ?? s.bgOpacity) as num).toDouble();
    s.top = (j['top'] ?? s.top) as bool;
    s.lines = (j['lines'] ?? s.lines) as int;
    s.bold = (j['bold'] ?? s.bold) as bool;
    s.outline = (j['outline'] ?? s.outline) as bool;
    final lang = (j['language'] ?? s.language) as String;
    s.language = languages.containsKey(lang) ? lang : 'es-ES';
    return s;
  }

  static CaptionStyle get current =>
      CaptionStyle.fromJson(app.settings.liveCaptionStyle);

  void save() => app.updateSettings((s) => s.liveCaptionStyle = toJson());

  TextStyle textStyle() => TextStyle(
    fontSize: fontSize,
    height: 1.25,
    color: Color(textColor),
    fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
    shadows: outline
        ? const [
            Shadow(blurRadius: 3, color: Colors.black),
            Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black),
          ]
        : null,
  );
}

// ------------------------------------------------------------------ Estado

class LiveCaptions {
  LiveCaptions._();

  static final active = ValueNotifier<bool>(false);

  /// Texto que se ve ahora (frases definitivas recientes + la parcial).
  static final text = ValueNotifier<String>('');

  /// Aviso temporal (descargando idioma, errores...).
  static final notice = ValueNotifier<String?>(null);

  static final List<String> _finals = [];
  static String _partial = '';
  static Timer? _clearTimer;
  static bool _hooked = false;

  static void _hook() {
    if (_hooked) return;
    _hooked = true;
    NativeBridge.onCaptionText = (t, isFinal) {
      if (!active.value) return;
      if (isFinal) {
        _finals.add(t.trim());
        if (_finals.length > 4) _finals.removeAt(0);
        _partial = '';
      } else {
        _partial = t.trim();
      }
      _publish();
    };
    NativeBridge.onCaptionStatus = (status, message) {
      switch (status) {
        case 'downloading':
          notice.value =
              'Descargando el español en el teléfono (solo la primera vez). '
              'Mientras tanto se usa el reconocimiento de Google por internet.';
          break;
        case 'listening':
          if (notice.value?.startsWith('Activando') ?? false) {
            notice.value = null;
          }
          break;
        case 'stopped':
          _reset();
          notice.value = 'Subtítulos detenidos';
          break;
        case 'error':
          _reset();
          notice.value = message ?? 'Los subtítulos han fallado';
          break;
      }
    };
  }

  static void _publish() {
    text.value = [..._finals, if (_partial.isNotEmpty) _partial].join(' ');
    _clearTimer?.cancel();
    // Si nadie habla durante un rato, se borra el texto de la pantalla.
    _clearTimer = Timer(const Duration(seconds: 6), () {
      _finals.clear();
      _partial = '';
      text.value = '';
    });
  }

  static void _reset() {
    active.value = false;
    _finals.clear();
    _partial = '';
    _clearTimer?.cancel();
    text.value = '';
  }

  /// Enciende los subtítulos. Devuelve un mensaje para el usuario si falla.
  static Future<String?> start() async {
    _hook();
    if (active.value) return null;
    if (!await NativeBridge.captionsSupported()) {
      return 'Este teléfono no permite subtítulos en directo '
          '(hace falta Android 13 o superior y el reconocimiento de voz de Google).';
    }
    notice.value = 'Activando subtítulos...';
    final r = await NativeBridge.startCaptions(CaptionStyle.current.language);
    if (r == 'ok') {
      active.value = true;
      return null;
    }
    notice.value = null;
    if (r == 'denied') {
      return 'Sin permiso no se puede escuchar el sonido del canal.';
    }
    if (r == 'cancelled') return null;
    if (r == 'unsupported') {
      return 'Este teléfono no permite subtítulos en directo.';
    }
    return 'No se pudieron activar los subtítulos (${r.replaceFirst('error:', '')}).';
  }

  static Future<void> stop() async {
    if (!active.value && notice.value == null) return;
    _reset();
    notice.value = null;
    await NativeBridge.stopCaptions();
  }

  static Future<String?> toggle() =>
      active.value ? stop().then((_) => null) : start();
}

// ------------------------------------------------------------------ Capa

/// Dibuja los subtítulos sobre el vídeo con el diseño elegido.
/// Va dentro de un Positioned.fill del reproductor.
class LiveCaptionOverlay extends StatelessWidget {
  const LiveCaptionOverlay({super.key, required this.controlsVisible});

  final bool controlsVisible;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        LiveCaptions.text,
        LiveCaptions.notice,
        app,
      ]),
      builder: (context, _) {
        final style = CaptionStyle.current;
        final t = LiveCaptions.text.value;
        final notice = LiveCaptions.notice.value;
        if (t.isEmpty && notice == null) return const SizedBox.shrink();
        final pad = MediaQuery.paddingOf(context);
        // Deja sitio a los controles cuando están visibles.
        final offset = controlsVisible ? 110.0 : 24.0;
        return IgnorePointer(
          child: Align(
            alignment: style.top ? Alignment.topCenter : Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16 + pad.left,
                style.top ? offset + pad.top : 0,
                16 + pad.right,
                style.top ? 0 : offset + pad.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (notice != null && t.isEmpty)
                    _Box(
                      opacity: 0.7,
                      child: Text(
                        notice,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  if (t.isNotEmpty) CaptionText(text: t, style: style),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.child, required this.opacity});
  final Widget child;
  final double opacity;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    ),
  );
}

/// Muestra solo las últimas líneas que caben, para que el texto nuevo
/// siempre se vea y el antiguo vaya subiendo y desapareciendo.
class CaptionText extends StatelessWidget {
  const CaptionText({super.key, required this.text, required this.style});

  final String text;
  final CaptionStyle style;

  @override
  Widget build(BuildContext context) {
    final ts = style.textStyle();
    return LayoutBuilder(
      builder: (context, box) {
        final maxW = box.maxWidth - 24;
        final visible = _lastLines(text, ts, maxW, style.lines, context);
        return _Box(
          opacity: style.bgOpacity,
          child: Text(visible, textAlign: TextAlign.center, style: ts),
        );
      },
    );
  }

  static String _lastLines(
    String text,
    TextStyle ts,
    double maxW,
    int lines,
    BuildContext context,
  ) {
    if (maxW <= 0) return text;
    final words = text.split(RegExp(r'\s+'));
    final scaler = MediaQuery.textScalerOf(context);
    bool fits(int from) {
      final tp = TextPainter(
        text: TextSpan(text: words.sublist(from).join(' '), style: ts),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout(maxWidth: maxW);
      final n = tp.computeLineMetrics().length;
      tp.dispose();
      return n <= lines;
    }

    if (fits(0)) return text;
    // Búsqueda binaria del primer palabra que deja el texto en N líneas.
    var lo = 0, hi = words.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (fits(mid)) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return words.sublist(lo).join(' ');
  }
}

// ------------------------------------------------------------------ Ajustes

class CaptionStylePage extends StatefulWidget {
  const CaptionStylePage({super.key});

  @override
  State<CaptionStylePage> createState() => _CaptionStylePageState();
}

class _CaptionStylePageState extends State<CaptionStylePage> {
  late CaptionStyle s = CaptionStyle.current;

  void _set(void Function() fn) {
    setState(fn);
    s.save();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Subtítulos en directo')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // Vista previa
          Container(
            height: 200,
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: [Color(0xFF37474F), Color(0xFF102027)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 12,
                  right: 12,
                  top: s.top ? 12 : null,
                  bottom: s.top ? null : 12,
                  child: CaptionText(
                    text:
                        'Buenas noches, estas son las noticias más importantes '
                        'del día. El Gobierno ha aprobado hoy el nuevo plan.',
                    style: s,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Se encienden con el botón de subtítulos (CC) del reproductor. '
              'El teléfono escucha solo el sonido de Mi IPTV y escribe el texto '
              'al momento. Es gratis y, con el idioma descargado, funciona sin '
              'internet.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('Idioma del canal'),
            trailing: DropdownButton<String>(
              value: s.language,
              onChanged: (v) => _set(() => s.language = v ?? s.language),
              items: [
                for (final e in CaptionStyle.languages.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.format_size),
            title: const Text('Tamaño de letra'),
            subtitle: Slider(
              value: s.fontSize,
              min: 14,
              max: 48,
              divisions: 17,
              label: s.fontSize.round().toString(),
              onChanged: (v) => _set(() => s.fontSize = v),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.format_color_text),
            title: const Text('Color del texto'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final e in CaptionStyle.colors.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      avatar: CircleAvatar(backgroundColor: Color(e.key)),
                      selected: s.textColor == e.key,
                      onSelected: (_) => _set(() => s.textColor = e.key),
                    ),
                ],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.rectangle_outlined),
            title: const Text('Fondo'),
            subtitle: Slider(
              value: s.bgOpacity,
              min: 0,
              max: 1,
              divisions: 10,
              label: '${(s.bgOpacity * 100).round()} %',
              onChanged: (v) => _set(() => s.bgOpacity = v),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.vertical_align_center),
            title: const Text('Posición'),
            trailing: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Abajo')),
                ButtonSegment(value: true, label: Text('Arriba')),
              ],
              selected: {s.top},
              onSelectionChanged: (v) => _set(() => s.top = v.first),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.format_line_spacing),
            title: const Text('Líneas visibles'),
            trailing: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('1')),
                ButtonSegment(value: 2, label: Text('2')),
                ButtonSegment(value: 3, label: Text('3')),
              ],
              selected: {s.lines},
              onSelectionChanged: (v) => _set(() => s.lines = v.first),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.format_bold),
            title: const Text('Letra en negrita'),
            value: s.bold,
            onChanged: (v) => _set(() => s.bold = v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.blur_on),
            title: const Text('Sombra alrededor de las letras'),
            subtitle: const Text('Útil si quitas el fondo'),
            value: s.outline,
            onChanged: (v) => _set(() => s.outline = v),
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('Volver al diseño original'),
            onTap: () => _set(() => s = CaptionStyle()),
          ),
        ],
      ),
    );
  }
}
