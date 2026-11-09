#!/bin/bash
# Compila en Release, firma con Developer ID (hardened runtime + sandbox), crea el DMG
# y, si se indica perfil de notarytool, lo notariza y grapa.
#
# Uso:
#   ./scripts/release.sh                                  # DMG firmado, sin notarizar
#   NOTARY_PROFILE=keyfold-notary ./scripts/release.sh    # firmado + notarizado
set -euo pipefail
cd "$(dirname "$0")/.."

# Basta con el tipo: solo hay un certificado Developer ID (equipo H473PHH58Y).
IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
VERSION=$(grep 'MARKETING_VERSION' project.yml | head -1 | sed -E 's/.*"(.*)".*/\1/')
DERIVED=build/dd
OUT=dist
APP="$OUT/Nook.app"
DMG="$OUT/Nook-$VERSION.dmg"

rm -rf "$OUT"
mkdir -p "$OUT"

xcodegen generate --quiet
xcodebuild -project Nook.xcodeproj -scheme Nook -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath "$DERIVED" build -quiet

ditto "$DERIVED/Build/Products/Release/Nook.app" "$APP"

# Firma explicita con Developer ID: la de Xcode es la de desarrollo.
codesign --force --options runtime --timestamp \
  --entitlements Nook/Nook.entitlements \
  --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# DMG con acceso directo a Aplicaciones.
STAGING=$(mktemp -d)
ditto "$APP" "$STAGING/Nook.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname Nook -srcfolder "$STAGING" -ov -format UDZO "$DMG" -quiet
rm -rf "$STAGING"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
else
  echo "Sin NOTARY_PROFILE: el DMG esta firmado pero no notarizado."
fi

echo "Listo: $DMG"
