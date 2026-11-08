// Detección del país de un canal a partir de sus datos.

const String noCountry = 'Sin país';
const String arabCountries = 'Países árabes';

/// Código ISO -> nombre en español, más nombres alternativos (en inglés y
/// códigos de 3 letras) que suelen aparecer en las listas.
const Map<String, List<String>> _countries = {
  'Afganistán': ['af', 'afg', 'afghanistan'],
  'Albania': ['al', 'alb', 'albania'],
  'Alemania': ['de', 'deu', 'ger', 'germany', 'deutschland'],
  'Arabia Saudí': ['sa', 'sau', 'ksa', 'saudi arabia', 'saudi'],
  'Argelia': ['dz', 'dza', 'algeria'],
  'Argentina': ['ar', 'arg', 'argentina'],
  'Armenia': ['am', 'arm', 'armenia'],
  'Australia': ['au', 'aus', 'australia'],
  'Austria': ['at', 'aut', 'austria'],
  'Azerbaiyán': ['az', 'aze', 'azerbaijan'],
  'Bahréin': ['bh', 'bhr', 'bahrain'],
  'Bélgica': ['be', 'bel', 'belgium'],
  'Bielorrusia': ['by', 'blr', 'belarus'],
  'Bolivia': ['bo', 'bol', 'bolivia'],
  'Bosnia y Herzegovina': ['ba', 'bih', 'bosnia', 'bosnia and herzegovina'],
  'Brasil': ['br', 'bra', 'brazil', 'brasil'],
  'Bulgaria': ['bg', 'bgr', 'bulgaria'],
  'Canadá': ['ca', 'can', 'canada'],
  'Chile': ['cl', 'chl', 'chile'],
  'China': ['cn', 'chn', 'china'],
  'Chipre': ['cy', 'cyp', 'cyprus'],
  'Colombia': ['co', 'col', 'colombia'],
  'Corea del Sur': ['kr', 'kor', 'south korea', 'korea'],
  'Costa Rica': ['cr', 'cri', 'costa rica'],
  'Croacia': ['hr', 'hrv', 'croatia'],
  'Cuba': ['cu', 'cub', 'cuba'],
  'Dinamarca': ['dk', 'dnk', 'denmark'],
  'Ecuador': ['ec', 'ecu', 'ecuador'],
  'Egipto': ['eg', 'egy', 'egypt'],
  'El Salvador': ['sv', 'slv', 'el salvador'],
  'Emiratos Árabes Unidos': ['ae', 'are', 'uae', 'united arab emirates'],
  'Eslovaquia': ['sk', 'svk', 'slovakia'],
  'Eslovenia': ['si', 'svn', 'slovenia'],
  'España': ['es', 'esp', 'spa', 'spain', 'españa', 'espana'],
  'Estados Unidos': [
    'us',
    'usa',
    'united states',
    'united states of america',
    'eeuu',
    'ee.uu.',
    'ee. uu.',
  ],
  'Estonia': ['ee', 'est', 'estonia'],
  'Filipinas': ['ph', 'phl', 'philippines'],
  'Finlandia': ['fi', 'fin', 'finland'],
  'Francia': ['fr', 'fra', 'france'],
  'Georgia': ['ge', 'geo', 'georgia'],
  'Grecia': ['gr', 'grc', 'greece'],
  'Guatemala': ['gt', 'gtm', 'guatemala'],
  'Honduras': ['hn', 'hnd', 'honduras'],
  'Hungría': ['hu', 'hun', 'hungary'],
  'India': ['in', 'ind', 'india'],
  'Indonesia': ['id', 'idn', 'indonesia'],
  'Irak': ['iq', 'irq', 'iraq'],
  'Irán': ['ir', 'irn', 'iran'],
  'Irlanda': ['ie', 'irl', 'ireland'],
  'Islandia': ['is', 'isl', 'iceland'],
  'Israel': ['il', 'isr', 'israel'],
  'Italia': ['it', 'ita', 'italy'],
  'Japón': ['jp', 'jpn', 'japan'],
  'Jordania': ['jo', 'jor', 'jordan'],
  'Kazajistán': ['kz', 'kaz', 'kazakhstan'],
  'Kosovo': ['xk', 'kosovo'],
  'Kuwait': ['kw', 'kwt', 'kuwait'],
  'Letonia': ['lv', 'lva', 'latvia'],
  'Líbano': ['lb', 'lbn', 'lebanon'],
  'Libia': ['ly', 'lby', 'libya'],
  'Lituania': ['lt', 'ltu', 'lithuania'],
  'Luxemburgo': ['lu', 'lux', 'luxembourg'],
  'Macedonia del Norte': ['mk', 'mkd', 'north macedonia', 'macedonia'],
  'Malta': ['mt', 'mlt', 'malta'],
  'Marruecos': ['ma', 'mar', 'morocco'],
  'México': ['mx', 'mex', 'mexico', 'méxico'],
  'Moldavia': ['md', 'mda', 'moldova'],
  'Montenegro': ['me', 'mne', 'montenegro'],
  'Nicaragua': ['ni', 'nic', 'nicaragua'],
  'Nigeria': ['ng', 'nga', 'nigeria'],
  'Noruega': ['no', 'nor', 'norway'],
  'Nueva Zelanda': ['nz', 'nzl', 'new zealand'],
  'Omán': ['om', 'omn', 'oman'],
  'Países Bajos': ['nl', 'nld', 'netherlands', 'holland'],
  'Pakistán': ['pk', 'pak', 'pakistan'],
  'Palestina': ['ps', 'pse', 'palestine'],
  'Panamá': ['pa', 'pan', 'panama'],
  'Paraguay': ['py', 'pry', 'paraguay'],
  'Perú': ['pe', 'per', 'peru'],
  'Polonia': ['pl', 'pol', 'poland'],
  'Portugal': ['pt', 'prt', 'portugal'],
  'Puerto Rico': ['pr', 'pri', 'puerto rico'],
  'Qatar': ['qa', 'qat', 'qatar'],
  'Reino Unido': ['uk', 'gb', 'gbr', 'united kingdom', 'great britain'],
  'República Checa': ['cz', 'cze', 'czech republic', 'czechia'],
  'República Dominicana': ['do', 'dom', 'dominican republic'],
  'Rumanía': ['ro', 'rou', 'romania'],
  'Rusia': ['ru', 'rus', 'russia'],
  'Serbia': ['rs', 'srb', 'serbia'],
  'Siria': ['sy', 'syr', 'syria'],
  'Sudáfrica': ['za', 'zaf', 'south africa'],
  'Suecia': ['se', 'swe', 'sweden'],
  'Suiza': ['ch', 'che', 'switzerland'],
  'Tailandia': ['th', 'tha', 'thailand'],
  'Taiwán': ['tw', 'twn', 'taiwan'],
  'Túnez': ['tn', 'tun', 'tunisia'],
  'Turquía': ['tr', 'tur', 'turkey', 'türkiye', 'turkiye'],
  'Ucrania': ['ua', 'ukr', 'ukraine'],
  'Uruguay': ['uy', 'ury', 'uruguay'],
  'Venezuela': ['ve', 'ven', 'venezuela'],
  'Vietnam': ['vn', 'vnm', 'vietnam'],
  'Yemen': ['ye', 'yem', 'yemen'],
  'Internacional': ['int', 'international', 'world', 'worldwide'],
};

final Map<String, String> _lookup = () {
  final m = <String, String>{};
  _countries.forEach((name, aliases) {
    m[name.toLowerCase()] = name;
    for (final a in aliases) {
      m[a] = name;
    }
  });
  return m;
}();

const _arabAliases = {'arab', 'arabic', 'arb', 'ara', 'arabia', 'árabe'};

final _prefixRe = RegExp(
  r'^\s*[\[\(|]?\s*([A-Za-zÀ-ÿ. ]{2,24}?)\s*(?:[\]\)|:]|\s-\s|\s–\s|\s\|)',
);
final _leadingCodeRe = RegExp(r'^\s*([A-Z]{2,3})\s+\S');

/// Nombre del país (en español) de un código o nombre, o null.
String? countryFromToken(String token, {bool groupContext = false}) {
  final t = token.trim().toLowerCase();
  if (t.isEmpty) return null;
  if (groupContext && (t == 'ar' || _arabAliases.contains(t))) {
    // En los grupos de listas comerciales "AR" suele significar árabe.
    return arabCountries;
  }
  if (_arabAliases.contains(t)) return arabCountries;
  return _lookup[t];
}

/// Deduce el país de un canal.
String detectCountry({
  String tvgCountry = '',
  String tvgId = '',
  String group = '',
  String name = '',
}) {
  // 1) Atributo tvg-country (ej. "ES" o "ES;PT").
  if (tvgCountry.trim().isNotEmpty) {
    final first = tvgCountry.split(RegExp(r'[;,|]')).first;
    final c = countryFromToken(first);
    if (c != null) return c;
  }
  // 2) El grupo completo es un país (ej. "Spain", "España").
  final gc = _lookup[group.trim().toLowerCase()];
  if (gc != null) return gc;
  // 3) Prefijo del grupo o del nombre: "ES: Noticias", "|UK| BBC", "[US] CNN".
  for (final text in [group, name]) {
    final m = _prefixRe.firstMatch(text);
    if (m != null) {
      final c = countryFromToken(m.group(1)!, groupContext: true);
      if (c != null) return c;
    }
    final m2 = text == group ? _leadingCodeRe.firstMatch(text) : null;
    if (m2 != null) {
      final c = countryFromToken(m2.group(1)!, groupContext: true);
      if (c != null) return c;
    }
  }
  // 4) Sufijo del identificador de guía: "La1.es", "CNN.us@HD".
  if (tvgId.isNotEmpty) {
    var id = tvgId;
    final at = id.indexOf('@');
    if (at > 0) id = id.substring(0, at);
    final dot = id.lastIndexOf('.');
    if (dot > 0 && dot < id.length - 1) {
      final suffix = id.substring(dot + 1).toLowerCase();
      if (suffix.length == 2) {
        final c = _lookup[suffix];
        if (c != null) return c;
      }
    }
  }
  return noCountry;
}
