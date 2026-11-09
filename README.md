<p align="center">
  <img src="docs/images/icono.png" width="128" alt="Icono de Nook">
</p>

<h1 align="center">Nook</h1>

<p align="center">
  <strong>El notch de tu Mac convertido en un sitio útil.</strong><br>
  Bandeja de archivos, historial del portapapeles, calendario, correo, agentes de IA,
  temporizadores y avisos del sistema, todo a un gesto del ratón.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.2%2B-1F5BFF" alt="macOS 14.2+">
  <img src="https://img.shields.io/badge/Swift-SwiftUI%20%2B%20AppKit-1F5BFF" alt="Swift">
  <img src="https://img.shields.io/badge/firmada-Developer%20ID%20%2B%20notarizada-4C7DFF" alt="Firmada y notarizada">
  <img src="https://img.shields.io/badge/idiomas-ES%20%7C%20EN-4C7DFF" alt="ES y EN">
</p>

<p align="center">
  <img src="docs/images/bandeja.png" width="720" alt="Panel de Nook abierto bajo el notch con cuatro archivos en la bandeja">
</p>

---

## Cómo funciona

Pasa el ratón por el notch y el panel sale de él con un muelle suave. Cerrado, el notch
mide exactamente lo mismo que el recorte de la pantalla (MacBook Air y MacBook Pro); cuando
pasa algo, se ensancha lo justo para avisarte a los lados y vuelve a su sitio.

Arriba están las pestañas (bandeja, portapapeles, capturas, calendario, agentes) y, a la
derecha, el volumen por app, el reloj con temporizadores y alarmas, y el menú.

## Bandeja

Arrastra archivos, imágenes o texto al notch y se quedan a mano, con su vista previa real,
hasta que los saques arrastrando. Nook guarda una copia, así que siguen ahí aunque borres el
original o reinicies el Mac.

- **Cesta al agitar:** agita el ratón mientras arrastras archivos y aparece una cesta flotante.
- **Vista previa grande y Quick Look**, compartir por AirDrop, comprimir en `.zip`, convertir
  imágenes (PNG, JPEG, HEIC) y copiar el texto de una imagen (OCR local).
- Con más de los que caben, las tarjetas pasan en **carrusel**: flechas a los lados y
  desplazamiento lateral.

## Historial del portapapeles

<p align="center">
  <img src="docs/images/historial.png" width="720" alt="Historial del portapapeles con buscador y filtros por tipo">
</p>

Todo lo que copias queda guardado (texto, enlaces, imágenes y archivos) con el icono de la
app de origen. Filtra por tipo, busca, incluso dentro de las imágenes, y fija lo importante.

- <kbd>⌃</kbd> <kbd>⌘</kbd> <kbd>V</kbd> desde cualquier app abre el historial; al elegir, se
  pega directamente donde estabas.
- Lo que los gestores de contraseñas marcan como privado no se guarda. Nunca se borra solo.

## Agentes de IA

<p align="center">
  <img src="docs/images/agentes.png" width="720" alt="Pestaña de agentes con dos sesiones de Claude Code en curso y el consumo restante">
</p>

Las sesiones de agentes de código abiertas en tu Mac, con su estado (en curso, esperando,
terminado), el proyecto y el consumo que queda en la ventana de 5 horas y en la semana.

## Calendario, recordatorios y correo

- **Calendario** de Apple con todas tus cuentas de *Cuentas de Internet*, incluido Microsoft
  365/Outlook. Entrada rápida en lenguaje natural ("Café con Ana mañana a las 10").
- **Recordatorios del día**: vencidos, de hoy y sin fecha, con su casilla para completarlos.
  Si escribes algo sin fecha en la entrada rápida, se guarda como recordatorio.
- **Controles de reunión**: cuenta atrás antes de cada reunión y botón para unirte.
- **Correo sin leer** de Mail o de Outlook clásico: quién te escribe y el asunto, y un aviso
  en el notch al llegar uno nuevo.

## Avisos en el notch

Volumen, batería y cargador, auriculares y altavoces Bluetooth (con su batería), Bloq Mayús,
conexión y VPN, descargas terminadas, micrófono o cámara en uso, notificaciones del sistema,
temporizadores y alarmas. Cada aviso se puede desactivar en Ajustes.

## Atajos y herramientas

| Atajo | Qué hace |
|---|---|
| <kbd>⌥</kbd> <kbd>Espacio</kbd> | **Lanzador**: abre apps y archivos, calcula (`15% de 80`) y convierte unidades (`10 km en mi`). |
| <kbd>⌃</kbd> <kbd>⌘</kbd> <kbd>V</kbd> | Historial del portapapeles. |
| <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>Espacio</kbd> | Anillo de acciones junto al cursor. |
| <kbd>⌃</kbd> <kbd>⌥</kbd> + flechas | Ajustar ventanas: mitades, cuartos, tercios, maximizar y centrar. |

Además: acciones al seleccionar texto (copiar, buscar, traducir, a la bandeja), dictado,
captura de una zona con OCR y volumen por app.

## Permisos

Nook funciona sin permisos especiales; cada uno desbloquea algo concreto y se pide solo
cuando lo activas:

| Permiso | Para qué |
|---|---|
| Calendarios y Recordatorios | Eventos, reuniones y recordatorios del día. |
| Accesibilidad | Pegar desde el historial, ajustar ventanas, texto seleccionado, controles de reunión. |
| Acceso total al disco | Leer las notificaciones del sistema (solo las nuevas; no se guardan). |
| Automatización (Mail / Outlook) | Ver los correos sin leer. |
| Grabación de audio del sistema | Volumen por app. |

Nada sale de tu Mac: no hay servidores ni analítica.

## Instalar

Descarga el DMG de la última versión, arrastra Nook a Aplicaciones y ábrelo. Está firmado con
Developer ID y notarizado por Apple, así que se abre sin avisos de Gatekeeper.

## Compilar

Requisitos: Xcode 26 o posterior y [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen generate
xcodebuild -project Nook.xcodeproj -scheme Nook -derivedDataPath build/dd build
xcodebuild -project Nook.xcodeproj -scheme Nook -derivedDataPath build/dd test
```

La build Debug usa su propio identificador y sus propios datos, así que probarla no toca la
bandeja ni el historial de la app instalada. Argumentos solo de Debug:

- `-NookOpen shelf|clipboard|screenshots|calendar|agents|mail` abre esa pestaña al arrancar.
- `-hideFromCaptures NO` deja ver el panel en capturas de pantalla.
- `-mailEnabled NO`, `-captureClipboard NO` desactivan el correo y el historial.

## Distribución

```bash
NOTARY_PROFILE=keyfold-notary ./scripts/release.sh   # DMG firmado, notarizado y grapado
```

El DMG queda en `dist/`.
