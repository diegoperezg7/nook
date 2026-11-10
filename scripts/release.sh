#!/bin/bash
# Compila en Release, firma con Developer ID (hardened runtime), crea el DMG y, si se
# indica perfil de notarytool, lo notariza y grapa. Deja tambien el appcast de Sparkle.
#
# Uso:
#   ./scripts/release.sh                                  # DMG firmado, sin notarizar
#   NOTARY_PROFILE=<perfil-de-notarytool> ./scripts/release.sh    # firmado + notarizado
#   DEVELOPER_ID_PROFILE=<ruta .provisionprofile> ...   # con el aviso de Concentracion
set -euo pipefail
cd "$(dirname "$0")/.."

# Basta con el tipo: solo hay un certificado Developer ID (equipo H473PHH58Y).
IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
VERSION=$(grep 'MARKETING_VERSION' project.yml | head -1 | sed -E 's/.*"(.*)".*/\1/')
DERIVED=build/dd
OUT=dist
APP="$OUT/Visor.app"
DMG="$OUT/Visor-$VERSION.dmg"

rm -rf "$OUT"
mkdir -p "$OUT"

xcodegen generate --quiet
xcodebuild -project Nook.xcodeproj -scheme Nook -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath "$DERIVED" build -quiet

ditto "$DERIVED/Build/Products/Release/Visor.app" "$APP"

# Firma explicita con Developer ID: la de Xcode es la de desarrollo.
# Los entitlements se toman de la build ya firmada por Xcode, con las variables
# ($(NOOK_APP_GROUP)...) sustituidas; el archivo del repo las lleva sin sustituir.
ENTITLEMENTS="$OUT/Visor.entitlements"
codesign -d --entitlements "$ENTITLEMENTS" --xml "$APP" 2>/dev/null
# La firma de desarrollo de Xcode añade get-task-allow (depuracion): la notarizacion lo rechaza.
/usr/libexec/PlistBuddy -c "Delete :com.apple.security.get-task-allow" "$ENTITLEMENTS" 2>/dev/null || true
# Concentracion (com.apple.developer.usernotifications.communication) es un permiso
# restringido: con Developer ID solo arranca si va dentro un perfil que lo incluya.
# Sin DEVELOPER_ID_PROFILE se quita y Visor funciona sin ese aviso.
if [ -n "${DEVELOPER_ID_PROFILE:-}" ]; then
  cp "$DEVELOPER_ID_PROFILE" "$APP/Contents/embedded.provisionprofile"
else
  /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.usernotifications.communication" "$ENTITLEMENTS" 2>/dev/null || true
  rm -f "$APP/Contents/embedded.provisionprofile"
  echo "Sin DEVELOPER_ID_PROFILE: la release va sin el aviso de Concentración."
fi
if grep -q '\$(' "$ENTITLEMENTS"; then
  echo "Entitlements con variables sin sustituir" >&2
  exit 1
fi
# Sparkle trae sus propios ejecutables: se firman de dentro afuera antes que la app.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for part in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
  codesign --force --options runtime --timestamp --preserve-metadata=entitlements \
    --sign "$IDENTITY" "$SPARKLE/$part"
done
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$IDENTITY" "$APP"
# Comprobacion final: el App Group firmado coincide con el del Info.plist.
GROUP=$(/usr/libexec/PlistBuddy -c "Print :NookAppGroup" "$APP/Contents/Info.plist")
codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q "<string>$GROUP</string>" || {
  echo "El App Group firmado no es $GROUP" >&2
  exit 1
}
codesign --verify --strict --verbose=2 "$APP"

# DMG con fondo (flecha de Visor a Aplicaciones). Finder coloca fondo e iconos en un
# DMG editable, que luego se comprime.
STAGING=$(mktemp -d)
ditto "$APP" "$STAGING/Visor.app"
ln -s /Applications "$STAGING/Applications"
mkdir "$STAGING/.background"
cp "$(dirname "$0")/dmg/background.tiff" "$STAGING/.background/background.tiff"
RW="$OUT/Visor-rw.dmg"
rm -f "$RW"
hdiutil create -volname Visor -fs HFS+ -srcfolder "$STAGING" -ov -format UDRW "$RW" -quiet
rm -rf "$STAGING"
MOUNT=$(hdiutil attach "$RW" -readwrite -noverify -noautoopen | awk -F'\t' '/\/Volumes\//{print $NF}')
VOLUME=$(basename "$MOUNT")
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 120, 840, 468}
    set opts to icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 104
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "Visor.app" of container window to {160, 160}
    set position of item "Applications" of container window to {480, 160}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
# El disco con el icono de Visor. Despues de Finder: al guardar la vista quita el
# icono propio del volumen.
cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
xcrun SetFile -a C "$MOUNT"
sync
hdiutil detach "$MOUNT" -quiet
hdiutil convert "$RW" -format UDZO -ov -o "$DMG" -quiet
rm -f "$RW"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
else
  echo "Sin NOTARY_PROFILE: el DMG esta firmado pero no notarizado."
fi

# Appcast de Sparkle: se sube como archivo de la release (la app lo lee de
# releases/latest/download/appcast.xml). Firma EdDSA con la clave del Llavero.
BUILD=$(grep 'CURRENT_PROJECT_VERSION' project.yml | head -1 | sed -E 's/.*"(.*)".*/\1/')
SIGN_UPDATE="$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
SIGNATURE=$("$SIGN_UPDATE" --account nook "$DMG")
cat > "$OUT/appcast.xml" <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Visor</title>
    <item>
      <title>Visor $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.2</sparkle:minimumSystemVersion>
      <enclosure url="https://github.com/diegoperezg7/visor/releases/download/v$VERSION/Visor-$VERSION.dmg" $SIGNATURE type="application/octet-stream"/>
    </item>
  </channel>
</rss>
APPCAST

echo "Listo: $DMG y $OUT/appcast.xml (subir los dos a la release v$VERSION)"
