# Mi IPTV

Reproductor IPTV personal para **Windows**, **Android** y **televisores Samsung**, hecho con Flutter y el motor de vídeo libmpv (media_kit). Reproduce canales `http`, HLS (`.m3u8`) y MPEG-TS (`.ts`).

## Descargar e instalar

Cada vez que se guarda un cambio en este repositorio, GitHub compila la aplicación sola y publica los archivos en **Releases** (columna derecha de la página del repositorio, o en `https://github.com/Manuel583/mi-iptv-app/releases`). Descarga siempre la versión de arriba del todo (la marcada como *Latest*).

| Archivo | Para qué sirve |
|---|---|
| `mi-iptv-windows-instalador.exe` | Instalador de Windows (recomendado) |
| `mi-iptv-windows-portable.zip` | Versión de Windows sin instalar: descomprimir y abrir `mi_iptv.exe` |
| `mi-iptv-android.apk` | Aplicación para el móvil Android |
| `mi-iptv-samsung-tv.wgt` | Aplicación para televisores Samsung (Tizen, modelos de 2017 en adelante) |

### Windows
1. Descarga `mi-iptv-windows-instalador.exe` y ábrelo.
2. Si aparece "Windows protegió su PC", pulsa **Más información** y luego **Ejecutar de todas formas** (sale porque la aplicación no está firmada por una empresa).
3. Sigue el asistente. Se crea un acceso directo "Mi IPTV" en el menú Inicio (y en el escritorio si lo marcas).

### Android
1. En el móvil, abre esta página de Releases en el navegador y descarga `mi-iptv-android.apk`.
2. Abre el archivo descargado. La primera vez el móvil pedirá permiso para "instalar aplicaciones desconocidas" desde el navegador: actívalo y vuelve atrás.
3. Pulsa **Instalar**. Si Google Play Protect avisa, elige **Instalar de todas formas**.
4. Para actualizar, descarga el APK nuevo e instálalo encima: se conservan tus listas y ajustes.

### Samsung TV

Samsung no deja instalar aplicaciones fuera de su tienda salvo con el **modo desarrollador**. Se hace una sola vez y lleva unos 20 minutos. Necesitas un PC con Windows en la misma red wifi que la tele y una cuenta de Samsung (gratis).

**1. Activar el modo desarrollador en la tele**
1. En el PC, abre el menú Inicio, escribe `cmd`, ábrelo y escribe `ipconfig`. Apunta la "Dirección IPv4" (algo como `192.168.1.35`).
2. En la tele, abre **Aplicaciones** (Apps) desde el menú de inicio.
3. Con el mando, pulsa **1 2 3 4 5**. Si tu mando no tiene números, pulsa el botón 123 y escríbelos en la pantalla.
4. Activa **Developer mode** (modo desarrollador), escribe la IP del PC y pulsa **OK**.
5. Reinicia la tele: mantén pulsado el botón de encendido hasta que se apague y vuelva a encenderse.

**2. Instalar la aplicación desde el PC**
1. Descarga `mi-iptv-samsung-tv.wgt` de Releases.
2. Descarga e instala **Apps2Samsung** (antes "Samsung Jellyfin Installer"): https://github.com/Apps2Samsung/Apps2Samsung/releases (la versión marcada como recomendada). Es una herramienta gratuita y de código abierto que hace por ti la parte difícil: crea el certificado de Samsung y firma e instala la aplicación.
3. Ábrela, deja que encuentre tu tele y elige instalar un archivo propio (`.wgt`): selecciona `mi-iptv-samsung-tv.wgt`.
4. La primera vez te pedirá entrar con tu cuenta de Samsung en el navegador para crear el certificado. Después, las actualizaciones se instalan igual y sin volver a pedirlo.
5. La aplicación "Mi IPTV" aparece en **Aplicaciones** de la tele.

Si algo falla: comprueba que la IP escrita en la tele es la del PC, apaga la tele desenchufándola 15 segundos y vuelve a probar.

**Alternativa oficial**: Tizen Studio de Samsung (https://developer.samsung.com/smarttv/develop/getting-started/setting-up-sdk/installing-tv-sdk.html), con su "Certificate Manager" (perfil Samsung, tipo TV) y su "Device Manager". Es más pesado y técnico.

**Primer uso en la tele**
- La forma más cómoda de tener tus listas es **importar la configuración del móvil**: en el móvil, Ajustes > Exportar configuración; sube el archivo a Google Drive y compártelo con "Cualquier persona con el enlace"; en la tele, Ajustes y listas > Importar la configuración, y escribe el enlace. Se pasan listas, favoritos, carpetas, nombres y canales ocultos. Después deja de compartir el archivo (lleva tus contraseñas).
- También puedes añadir una lista M3U o los datos de Xtream Codes escribiendo con el mando.

**Botones del mando**

| Botón | En la lista de canales | Viendo un canal |
|---|---|---|
| ▲ ▼ | Moverse | Canal anterior / siguiente |
| CH+ / CH- | Pasar página | Canal anterior / siguiente |
| ◀ ▶ | Cambiar de columna | ◀ abre la lista de canales |
| OK | Ver el canal | Mostrar la información (y la guía si es Xtream) |
| Números | | Ir al canal con ese número |
| Rojo | Favorito | Favorito |
| Verde | Buscar | |
| Amarillo | Actualizar listas | Cambiar idioma de audio |
| Azul | Ajustes y listas | |
| Volver | Atrás (dos veces para salir) | Volver a la lista |

Limitaciones de esta primera versión de la tele: la guía de programación solo aparece con listas Xtream Codes (no con guías XMLTV), y no hay mosaico ni miniventana.

## Uso rápido

- **Añadir una lista**: Ajustes > Mis listas > Añadir lista (enlace M3U, archivo M3U o servidor + usuario + contraseña de Xtream Codes).
- **Guía (EPG)**: se usa la incluida en la lista; puedes añadir más enlaces XMLTV en Ajustes > Guías de programación.
- **Actualizar**: botón de flechas circulares arriba, y automáticamente cada X horas (Ajustes > Actualizar automáticamente) mientras la aplicación está abierta.
- **Organizar**: estrella = favorito; tres puntos de un canal = carpetas, renombrar, ocultar. Lápiz en grupos o canales = ordenar arrastrando, renombrar y ocultar.
- **Pasar la configuración del PC al móvil**: Ajustes > Exportar configuración (en el PC) y Ajustes > Importar configuración (en el móvil). El archivo contiene tus contraseñas: no lo compartas.

### Canales, películas y series

La app separa sola lo que hay en tus listas:
- **Canales**: emisiones en directo.
- **Películas**: archivos de vídeo (`.mp4`, `.mkv`...), direcciones con `/movie/` o grupos de vídeo bajo demanda (VOD). En Xtream Codes se descargan del apartado de películas del servidor.
- **Series**: capítulos con `S01E02`, `1x02` o "Temporada 2 Capítulo 5" en el nombre, o direcciones con `/series/`. Se agrupan por serie y por temporada. En Xtream Codes los capítulos se piden al abrir cada serie.

Los menús Películas y Series solo aparecen si alguna lista tiene películas o series. En la tele están dentro de la columna de categorías ("Películas ▶" y "Series ▶").

### Carpetas automáticas: Fútbol y TDT

En **Carpetas** (y en la tele, en la columna de categorías) hay dos carpetas que se rellenan solas cada vez que se actualizan las listas:
- **Fútbol**: DAZN (salvo F1, baloncesto...), LaLiga, M+ LaLiga, Liga de Campeones, Gol, Real Madrid TV, Barça TV, Premier League, etc., y todos los canales de grupos llamados "Fútbol".
- **TDT**: los canales de la TDT española, nacionales (La 1, La 2, 24h, Clan, Teledeporte, Antena 3, Cuatro, Telecinco, laSexta, Neox, Nova, Mega, FDF, Energy, Divinity, Be Mad, Boing, Trece, DMAX, DKISS, Ten, Paramount Network, Real Madrid TV, Gol Play...) y autonómicos (TV3, Telemadrid, Canal Sur, À Punt, TVG, ETB, Aragón TV, CMM, IB3, TPA, 7RM, Canal Extremadura, CyLTV, Navarra TV...).

### Retroceder en directo, grabar y emitir (Android y Windows)

- **Retroceder en directo**: la app guarda los últimos minutos del canal (15 por defecto, se cambia en Ajustes > Retroceder en directo). Con los botones de 10 s, la barra de tiempo o pausando, vas hacia atrás; el botón **Ir al directo** te devuelve. Al cambiar de canal se empieza de cero.
- **Películas, capítulos y grabaciones**: barra para adelantar y atrasar, y la app recuerda por dónde ibas.
- **Imagen y sonido** (botón de controles deslizantes): volumen hasta 200 %, igualar volumen, retraso del sonido, velocidad, brillo, contraste, color, zoom, formato y tamaño o retraso de subtítulos.
- **Grabar**: botón rojo. Se guarda al pulsarlo otra vez, al cambiar de canal o al salir. Android: carpeta *Películas/Mi IPTV*. Windows: *Vídeos\Mi IPTV*. Se ven en el botón **Grabaciones** de arriba. Solo graba mientras el canal está abierto. Si la señal se corta, sigue en un archivo "(parte 2)".
- **Emitir en la tele**: botón de emitir. Busca teles DLNA (Samsung, LG, Sony...) y Chromecast en la misma wifi. La tele descarga el canal por su cuenta; si no lo abre, activa "Pasar la señal por este dispositivo" (entonces el móvil o PC tiene que seguir con la app abierta). Las Samsung no siempre aceptan canales .m3u8 por DLNA; para ellas lo mejor es la app de la tele. En Windows también puedes duplicar la pantalla con **Windows + K**.

### Guía de programación

- **Rejilla**: botón de la guía arriba (icono de líneas de tiempo). Canales en filas y horas en columnas, con una línea roja en la hora actual. Arriba eliges grupo, favoritos o carpeta, y el día.
- **Ahora | después**: debajo de cada canal aparece lo que echan y lo siguiente.
- **Xtream**: si un canal no viene en la guía completa, la app pide su programación al servidor.

### Grabación programada (Android y Windows)

Toca un programa de la guía y pulsa **Grabar**. Se graba aunque la app esté cerrada, desde 2 minutos antes hasta 5 después (se cambia en Ajustes > Grabaciones programadas). La lista está en el botón de calendario de la guía o de Grabaciones.

- **Android**: el móvil despierta la app a la hora exacta y aparece un aviso "Grabando" con el botón **Parar y guardar**. Conviene permitir que la app funcione sin ahorro de batería (te lo pide la lista de programadas).
- **Windows**: se crea una tarea en el Programador de tareas (carpeta *Mi IPTV*). A la hora indicada se abre una ventanita minimizada que graba. El PC tiene que estar encendido o en suspensión (puede despertarse solo si Windows lo permite).
- **Límites**: el aparato tiene que estar encendido y con Internet. Si tu proveedor solo permite una conexión, no veas otro canal mientras graba. La tele Samsung no puede grabar.

### Pistas de audio y subtítulos

- En el reproductor, botones de **audio** y **subtítulos** (teclas A y S en Windows). La app recuerda el idioma que eliges y lo usa en los demás canales. También se elige en Ajustes > Idioma de audio preferido y Subtítulos de la emisión.
- En la tele: botón **amarillo** = idioma de audio, **azul** = subtítulos.

### Sincronizar con Google Drive (móvil, PC y tele)

Ajustes > **Sincronizar con Google Drive** > Conectar. La app muestra un código: abre google.com/device en el móvil o el PC, escríbelo y acepta. Desde ese momento, tus listas, favoritos, carpetas, nombres y ajustes pasan solos entre aparatos (cada 15 minutos y al abrir la app). Se guarda en una carpeta privada de tu Drive que no aparece entre tus archivos. Lo propio de cada aparato (aceleración, imagen flotante, grabaciones) no se comparte.

**Una sola vez: crear el permiso de Google (gratis, unos 15 minutos)**

1. Entra en [console.cloud.google.com](https://console.cloud.google.com) con tu cuenta de Google y crea un proyecto llamado *Mi IPTV*.
2. Menú > *APIs y servicios* > *Biblioteca*: busca **Google Drive API** y pulsa **Habilitar**.
3. Menú > *Google Auth Platform* > **Empezar**: nombre *Mi IPTV*, tu correo, público **Externo**, acepta.
4. *Público* > **Publicar aplicación** (estado "En producción"). Así el permiso no caduca a los 7 días. No hace falta verificación porque solo pide acceso a su propia carpeta.
5. *Clientes* > **Crear cliente** > tipo **TV y dispositivos de entrada limitada** > nombre *Mi IPTV*. Copia el **ID de cliente** y el **Secreto del cliente**.
6. En GitHub: repositorio > *Settings* > *Secrets and variables* > *Actions* > **New repository secret**. Crea `GOOGLE_CLIENT_ID` y `GOOGLE_CLIENT_SECRET` con esos valores. Las próximas versiones los llevarán dentro. (Si no quieres esperar, puedes pegarlos a mano en la app, en la pantalla de sincronizar.)

### Atajos de teclado (Windows)

| Tecla | Acción |
|---|---|
| ↓ / ↑ (o AvPág / RePág) | Canal siguiente / anterior |
| ← / → | Atrás / adelante 10 s (con Mayúsculas, 60 s) |
| + / - | Subir / bajar volumen |
| D | Volver al directo |
| R | Grabar / parar grabación |
| C | Emitir en la tele |
| Espacio | Pausa |
| F o Intro | Pantalla completa |
| M | Silencio |
| A / S | Cambiar pista de audio / subtítulos |
| P | Miniventana siempre visible |
| L | Lista de canales |
| Esc | Salir de pantalla completa o de la miniventana |
| 1 a 4 (en mosaico) | Elegir qué canal suena |

En Android: desliza hacia arriba o abajo sobre el vídeo para cambiar de canal.

## Para quien mantenga el código

- Código de la aplicación: carpeta `lib/`.
- Compilación automática: `.github/workflows/compilar.yml`.
- Instalador de Windows: `installer/mi-iptv.iss` (Inno Setup).
- Versión para Samsung TV: carpeta `tizen/` (aplicación web de Tizen en JavaScript, con el reproductor AVPlay de Samsung). Se puede probar en un navegador abriendo `tizen/index.html` desde un servidor local (el vídeo HLS/TS solo se reproduce en la tele). Pruebas: `node --test tizen/test/parsers.test.js`. El `.wgt` que genera GitHub va sin firmar: lo firma con el certificado de Samsung de cada usuario la herramienta de instalación.
- Firma del APK: si existen los secretos `ANDROID_KEYSTORE` (clave en base64) y `ANDROID_KEYSTORE_PASSWORD` en Settings > Secrets and variables > Actions, todas las versiones se firman igual y se actualizan encima. Sin ellos se usa una firma temporal distinta en cada compilación (para actualizar habría que desinstalar antes).
