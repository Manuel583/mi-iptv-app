# Mi IPTV

Reproductor IPTV personal para **Windows** y **Android**, hecho con Flutter y el motor de vídeo libmpv (media_kit). Reproduce canales `http`, HLS (`.m3u8`) y MPEG-TS (`.ts`).

## Descargar e instalar

Cada vez que se guarda un cambio en este repositorio, GitHub compila la aplicación sola y publica los archivos en **Releases** (columna derecha de la página del repositorio, o en `https://github.com/Manuel583/mi-iptv-app/releases`). Descarga siempre la versión de arriba del todo (la marcada como *Latest*).

| Archivo | Para qué sirve |
|---|---|
| `mi-iptv-windows-instalador.exe` | Instalador de Windows (recomendado) |
| `mi-iptv-windows-portable.zip` | Versión de Windows sin instalar: descomprimir y abrir `mi_iptv.exe` |
| `mi-iptv-android.apk` | Aplicación para el móvil Android |

### Windows
1. Descarga `mi-iptv-windows-instalador.exe` y ábrelo.
2. Si aparece "Windows protegió su PC", pulsa **Más información** y luego **Ejecutar de todas formas** (sale porque la aplicación no está firmada por una empresa).
3. Sigue el asistente. Se crea un acceso directo "Mi IPTV" en el menú Inicio (y en el escritorio si lo marcas).

### Android
1. En el móvil, abre esta página de Releases en el navegador y descarga `mi-iptv-android.apk`.
2. Abre el archivo descargado. La primera vez el móvil pedirá permiso para "instalar aplicaciones desconocidas" desde el navegador: actívalo y vuelve atrás.
3. Pulsa **Instalar**. Si Google Play Protect avisa, elige **Instalar de todas formas**.
4. Para actualizar, descarga el APK nuevo e instálalo encima: se conservan tus listas y ajustes.

## Uso rápido

- **Añadir una lista**: Ajustes > Mis listas > Añadir lista (enlace M3U, archivo M3U o servidor + usuario + contraseña de Xtream Codes).
- **Guía (EPG)**: se usa la incluida en la lista; puedes añadir más enlaces XMLTV en Ajustes > Guías de programación.
- **Actualizar**: botón de flechas circulares arriba, y automáticamente cada X horas (Ajustes > Actualizar automáticamente) mientras la aplicación está abierta.
- **Organizar**: estrella = favorito; tres puntos de un canal = carpetas, renombrar, ocultar. Lápiz en grupos o canales = ordenar arrastrando, renombrar y ocultar.
- **Pasar la configuración del PC al móvil**: Ajustes > Exportar configuración (en el PC) y Ajustes > Importar configuración (en el móvil). El archivo contiene tus contraseñas: no lo compartas.

### Atajos de teclado (Windows)

| Tecla | Acción |
|---|---|
| ↓ / ↑ (o AvPág / RePág) | Canal siguiente / anterior |
| ← / → | Bajar / subir volumen |
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
- Firma del APK: si existen los secretos `ANDROID_KEYSTORE` (clave en base64) y `ANDROID_KEYSTORE_PASSWORD` en Settings > Secrets and variables > Actions, todas las versiones se firman igual y se actualizan encima. Sin ellos se usa una firma temporal distinta en cada compilación (para actualizar habría que desinstalar antes).
