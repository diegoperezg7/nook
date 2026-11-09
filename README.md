# Perch

App de macOS que vive en el notch: una **bandeja** donde dejar archivos, imágenes o texto
para usarlos después y un **historial del portapapeles** con búsqueda. Todo se arrastra
dentro y fuera del notch.

## Funciones

- **Bandeja**: arrastra algo al notch y queda guardado (se copia a la carpeta de la app,
  así sobrevive aunque muevas el original). Arrástralo fuera cuando lo necesites; un clic lo copia.
- **Historial del portapapeles**: texto, imágenes y archivos copiados. Búsqueda, fijar
  elementos (no rotan), clic para copiar. Ignora lo que los gestores de contraseñas
  marcan como privado (`org.nspasteboard.ConcealedType` y similares).
- **Atajo global ⌃⌘V**: abre el historial con el buscador listo; Enter copia el primer
  resultado y devuelve el foco a la app anterior para pegar con ⌘V.
- **Acciones** (menú contextual): vista previa con Quick Look (o doble clic), Compartir
  (AirDrop, Mensajes, Mail), mostrar en Finder, guardar un elemento del historial en la
  bandeja, copiar el texto de una imagen (OCR local con Vision), comprimir en .zip y
  convertir imágenes a PNG, JPEG o HEIC.
- **Vistas previas reales** con Quick Look: páginas de PDF, imágenes, documentos.
- **Copiar imágenes y documentos**: se copian como archivo (Finder, Mail) y como imagen o
  PDF (chats, documentos), así se pegan bien en cualquier app.
- **Modo sin notch**: en pantallas sin notch aparece una pastilla arriba en el centro.
- **Animación "el notch se licua"**: al acercar el ratón el notch se asoma; al entrar se
  ensancha, gotea hacia abajo y el negro se disuelve en cristal, con un destello de luz que lo
  recorre. Arrastrar algo encima hace latir el borde y el panel se hincha. Respeta "Reducir
  movimiento".
- Liquid Glass (macOS 26; material translúcido en 14-15), ES/EN, claro/oscuro, acento azul eléctrico.

## Permisos

Ninguno especial: no pide Accesibilidad ni Grabación de pantalla, y funciona en sandbox.
Desde macOS 15.4 el sistema puede preguntar por **"Pegar desde otras apps"** al leer el
portapapeles; si el acceso queda en "Preguntar" o "Denegar", el historial se pausa y la
app enseña cómo permitirlo (Ajustes del Sistema > Privacidad y seguridad).

## Desarrollo

Requisitos: Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen). macOS 14+.

```bash
xcodegen generate
xcodebuild -project Perch.xcodeproj -scheme Perch -derivedDataPath build/dd build
xcodebuild -project Perch.xcodeproj -scheme Perch -derivedDataPath build/dd test
```

Argumentos de depuración (solo Debug):

- `-PerchOpen shelf|clipboard` abre el panel al arrancar y no lo cierra (capturas).
- `-PerchReset YES` borra bandeja e historial.

## Distribución

```bash
./scripts/release.sh                                  # DMG firmado con Developer ID
NOTARY_PROFILE=keyfold-notary ./scripts/release.sh    # además notarizado y grapado
```

El DMG queda en `dist/`.

## Arquitectura

```
Perch/
  App/            PerchApp, AppDelegate (arranque, ajustes, atajo)
  Notch/          Panel, controlador (raton, apertura/cierre), forma animada, medidas
  Features/       Bandeja, historial, tarjeta, ajustes
  Services/       ItemStore (SwiftData + archivos), ClipboardMonitor, DropReader, HotKey
  DesignSystem/   AppColors, AppTypography, AppMotion
```

Decisión clave: la ventana del panel tiene siempre el tamaño abierto y nunca se
redimensiona. Redimensionarla en mitad de un arrastre impedía que el sistema entregara el
soltado. Para no bloquear la barra de menús, solo acepta ratón cuando el cursor está sobre
la forma visible (`ignoresMouseEvents`).
