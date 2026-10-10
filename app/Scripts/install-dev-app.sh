#!/bin/bash
# Installe une Moyo de développement dans ~/Applications, qui ouvre les .sgf du Finder.
#
# Le vrai bundle (build-app.sh) demande un KataGo compilé en statique, vingt minutes
# de compilation. Celui-ci n'embarque rien : il lance le pont depuis le dépôt et
# KataGo depuis Homebrew, sans sandbox, et LSEnvironment lui donne les chemins
# quand le Finder le lance — là où aucune variable d'environnement ne parvient.
#
# Il déclare le type SGF comme le vrai bundle, au rang Default : sur un Mac où rien
# d'autre ne revendique les .sgf, un double-clic les ouvre dans Moyo.
#
# Prérequis : le .venv du dépôt, `brew install katago`, ./app/Scripts/fetch-models.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="$ROOT/app"
BUNDLE="${MOYO_DEV_BUNDLE:-$HOME/Applications/Moyo.app}"
MODELS="${MOYO_MODEL_CACHE:-$HOME/.cache/moyo/models}"
KATAGO="${MOYO_KATAGO:-/opt/homebrew/bin/katago}"
CONFIG="$ROOT/.venv/lib/python3.13/site-packages/katrain/KataGo/analysis_config.cfg"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

for path in "$ROOT/.venv/bin/python" "$KATAGO" "$MODELS/play.bin.gz" "$MODELS/human.bin.gz" "$CONFIG"; do
  [ -e "$path" ] || { echo "manque : $path" >&2; exit 1; }
done

echo "==> Compilation Swift (debug)"
swift build --package-path "$APP_DIR"
BINARY="$(swift build --package-path "$APP_DIR" --show-bin-path)/Moyo"

echo "==> Assemblage de $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BINARY" "$BUNDLE/Contents/MacOS/Moyo"
cp "$APP_DIR/Resources/icon/Moyo.icns" "$BUNDLE/Contents/Resources/Moyo.icns"

# Les types de document reprennent ceux de build-app.sh : les deux doivent rester
# d'accord, sans quoi le Finder ne saurait pas quelle Moyo ouvre quoi.
cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Moyo</string>
    <key>CFBundleIdentifier</key><string>com.thibaut.moyo.dev</string>
    <key>CFBundleName</key><string>Moyo</string>
    <key>CFBundleDisplayName</key><string>Moyo</string>
    <key>CFBundleIconFile</key><string>Moyo</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.0.0-dev</string>
    <key>CFBundleVersion</key><string>0</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSLocalNetworkUsageDescription</key><string>Moyo cherche l'iPhone qui filme le plateau pour lire vos coups.</string>
    <key>NSBonjourServices</key><array><string>_goboard._tcp</string></array>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>LSEnvironment</key>
    <dict>
        <key>MOYO_DEV_ROOT</key><string>$ROOT</string>
        <key>MOYO_KATAGO</key><string>$KATAGO</string>
        <key>MOYO_MODEL</key><string>$MODELS/play.bin.gz</string>
        <key>MOYO_HUMAN_MODEL</key><string>$MODELS/human.bin.gz</string>
        <key>MOYO_CONFIG</key><string>$CONFIG</string>
    </dict>
    <key>UTImportedTypeDeclarations</key>
    <array><dict>
        <key>UTTypeIdentifier</key><string>org.smart-game-format.sgf</string>
        <key>UTTypeDescription</key><string>Partie de go (SGF)</string>
        <key>UTTypeConformsTo</key><array><string>public.plain-text</string></array>
        <key>UTTypeTagSpecification</key>
        <dict><key>public.filename-extension</key><array><string>sgf</string></array></dict>
    </dict></array>
    <key>CFBundleDocumentTypes</key>
    <array><dict>
        <key>CFBundleTypeName</key><string>Partie de go (SGF)</string>
        <key>CFBundleTypeRole</key><string>Editor</string>
        <key>LSHandlerRank</key><string>Default</string>
        <key>LSItemContentTypes</key><array><string>org.smart-game-format.sgf</string></array>
    </dict></array>
</dict>
</plist>
PLIST

codesign --force --sign - "$BUNDLE"

echo "==> Enregistrement auprès de Launch Services"
"$LSREGISTER" -f "$BUNDLE"
echo "==> $BUNDLE"
