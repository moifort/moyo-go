#!/bin/bash
# Assemble Moyo.app, autonome et relocalisable.
#
# Le bundle ne dépend de rien d'installé sur la machine : interpréteur Python,
# katago, modèles et configuration vivent tous à l'intérieur. C'est la condition
# du sandbox App Store, qui interdit d'aller chercher quoi que ce soit dehors.
#
# Prérequis : ./app/Scripts/build-katago.sh une fois, et vendor/python (voir README).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="$ROOT/app"
CONFIGURATION="${1:-release}"
BUNDLE="$APP_DIR/build/Moyo.app"
CONTENTS="$BUNDLE/Contents"
KATAGO="${MOYO_KATAGO_BINARY:-$ROOT/vendor/katago-src/cpp/build/katago}"
PAYLOAD="$APP_DIR/build/payload"

# Les modèles pèsent 190 Mo et ne peuvent pas vivre dans le dépôt. En local on
# reprend ceux déjà installés ; la CI les récupérera et posera ces variables.
PLAY_MODEL="${MOYO_PLAY_MODEL:-/opt/homebrew/opt/katago/share/katago/kata1-b18c384nbt-s9996604416-d4316597426.bin.gz}"
HUMAN_MODEL="${MOYO_HUMAN_MODEL_FILE:-$HOME/.katrain/b18c384nbt-humanv0.bin.gz}"
ENGINE_CONFIG="${MOYO_ENGINE_CONFIG:-$ROOT/.venv/lib/python3.13/site-packages/katrain/KataGo/analysis_config.cfg}"

VERSION="${MOYO_VERSION:-0.1.0}"
BUILD_NUMBER="${MOYO_BUILD_NUMBER:-1}"
IDENTITY="${MOYO_SIGN_IDENTITY:--}"   # « - » : signature ad-hoc, suffisante en local
INSTALLER_IDENTITY="${MOYO_INSTALLER_IDENTITY:-}"
PROFILE="${MOYO_PROVISION_PROFILE:-}"
TEAM_ID="${MOYO_TEAM_ID:-46C337T7YN}"

# Trois conditions pour un build de distribution : une identité d'application,
# une identité d'installeur, et un profil. S'il en manque une, on reste en local.
DISTRIBUTION=0
if [ "$IDENTITY" != "-" ] && [ -n "$INSTALLER_IDENTITY" ] && [ -f "$PROFILE" ]; then
  DISTRIBUTION=1
fi

for path in "$KATAGO" "$PLAY_MODEL" "$HUMAN_MODEL" "$ENGINE_CONFIG"; do
  [ -e "$path" ] || { echo "manque : $path" >&2; exit 1; }
done

echo "==> Compilation Swift ($CONFIGURATION)"
swift build --package-path "$APP_DIR" -c "$CONFIGURATION"
BINARY="$(swift build --package-path "$APP_DIR" -c "$CONFIGURATION" --show-bin-path)/Moyo"

echo "==> Chargement Python"
"$APP_DIR/Scripts/build-python-payload.sh" "$PAYLOAD" >/dev/null

echo "==> Assemblage"
rm -rf "$BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Helpers" "$CONTENTS/Resources/models"
cp "$BINARY" "$CONTENTS/MacOS/Moyo"
cp "$KATAGO" "$CONTENTS/Helpers/katago"
cp -R "$PAYLOAD/python" "$CONTENTS/Resources/python"
cp -R "$PAYLOAD/bridge" "$CONTENTS/Resources/bridge"
cp "$ENGINE_CONFIG" "$CONTENTS/Resources/analysis_config.cfg"
cp "$PLAY_MODEL" "$CONTENTS/Resources/models/play.bin.gz"
cp "$HUMAN_MODEL" "$CONTENTS/Resources/models/human.bin.gz"
cp "$APP_DIR/Resources/icon/Moyo.icns" "$CONTENTS/Resources/Moyo.icns"
# Sur macOS le profil vit *dans* le bundle, contrairement à iOS où il se dépose
# dans ~/Library/MobileDevice, et il doit y être avant la signature : signer
# d'abord puis le glisser invaliderait le sceau.
[ "$DISTRIBUTION" = "1" ] && cp "$PROFILE" "$CONTENTS/embedded.provisionprofile"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Moyo</string>
    <key>CFBundleIdentifier</key><string>com.thibaut.moyo</string>
    <key>CFBundleName</key><string>Moyo</string>
    <key>CFBundleDisplayName</key><string>Moyo</string>
    <key>CFBundleIconFile</key><string>Moyo</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.board-games</string>
    <!-- L'application n'emploie aucun chiffrement au-delà de celui du système.
         Sans cette clé, App Store Connect réclame des documents d'export à
         chaque envoi de build. -->
    <key>ITSAppUsesNonExemptEncryption</key><false/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSLocalNetworkUsageDescription</key><string>Moyo cherche l'iPhone qui filme le plateau pour lire vos coups.</string>
    <key>NSBonjourServices</key><array><string>_goboard._tcp</string></array>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <!-- macOS ne déclare aucun type pour un enregistrement de go : Moyo importe
         le sien, puis se déclare capable de le lire. -->
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
        <key>CFBundleTypeRole</key><string>Viewer</string>
        <key>LSHandlerRank</key><string>Alternate</string>
        <key>LSItemContentTypes</key><array><string>org.smart-game-format.sgf</string></array>
    </dict></array>
</dict>
</plist>
PLIST

WORK="$APP_DIR/build/signing"
mkdir -p "$WORK"
if [ "$DISTRIBUTION" = "1" ]; then
cat > "$WORK/app.entitlements" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <!-- Trouver l'iPhone qui filme le plateau : Bonjour et une connexion TCP sortante. -->
  <key>com.apple.security.network.client</key><true/>
  <!-- Ouvrir un SGF. L'accès vaut pour la fenêtre, pas pour le pont : c'est
       l'application qui lit le fichier et en envoie le texte. -->
  <key>com.apple.security.files.user-selected.read-only</key><true/>
  <key>com.apple.application-identifier</key><string>$TEAM_ID.com.thibaut.moyo</string>
  <key>com.apple.developer.team-identifier</key><string>$TEAM_ID</string>
</dict></plist>
PLIST
else
cat > "$WORK/app.entitlements" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <!-- Trouver l'iPhone qui filme le plateau : Bonjour et une connexion TCP sortante. -->
  <key>com.apple.security.network.client</key><true/>
  <!-- Ouvrir un SGF. L'accès vaut pour la fenêtre, pas pour le pont : c'est
       l'application qui lit le fichier et en envoie le texte. -->
  <key>com.apple.security.files.user-selected.read-only</key><true/>
</dict></plist>
PLIST
fi
# Un processus enfant qui porte la moindre entitlement en plus de ces deux-là est
# tué au démarrage par le système. Ne rien ajouter ici.
cat > "$WORK/helper.entitlements" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <!-- Trouver l'iPhone qui filme le plateau : Bonjour et une connexion TCP sortante. -->
  <key>com.apple.security.network.client</key><true/>
  <key>com.apple.security.inherit</key><true/>
</dict></plist>
PLIST

echo "==> Signature, de l'intérieur vers l'extérieur"
# Toute signature extérieure invalide les intérieures : l'ordre n'est pas négociable.
sign() { codesign --force --timestamp --options runtime --sign "$IDENTITY" "$@" ; }
[ "$IDENTITY" = "-" ] && sign() { codesign --force --sign - "$@" ; }

find "$CONTENTS/Resources/python" \( -name "*.so" -o -name "*.dylib" \) -print0 |
  while IFS= read -r -d '' lib; do sign "$lib" 2>/dev/null || true; done

# python-build-standalone ne porte pas d'Info.plist : sans --identifier, le système
# ne lui trouve pas d'identifiant de bundle et refuse de l'exécuter sous sandbox.
sign --identifier com.thibaut.moyo.python \
     --entitlements "$WORK/helper.entitlements" "$CONTENTS/Resources/python/bin/python3.13"
sign --identifier com.thibaut.moyo.katago \
     --entitlements "$WORK/helper.entitlements" "$CONTENTS/Helpers/katago"
sign --entitlements "$WORK/app.entitlements" "$BUNDLE"

codesign --verify --deep --strict "$BUNDLE"
echo "==> $BUNDLE ($(du -sm "$BUNDLE" | cut -f1) Mo, signé « $IDENTITY »)"

if [ "$DISTRIBUTION" = "1" ]; then
  echo "==> Emballage pour l'App Store"
  PKG="$APP_DIR/build/Moyo.pkg"
  # productbuild signe le paquet avec l'identité d'installeur, distincte de celle
  # qui signe l'application. App Store Connect refuse un .pkg signé autrement.
  productbuild --component "$BUNDLE" /Applications --sign "$INSTALLER_IDENTITY" "$PKG"
  pkgutil --check-signature "$PKG" >/dev/null
  echo "==> $PKG ($(du -sm "$PKG" | cut -f1) Mo)"
else
  echo "    (build local : ni profil ni identité de distribution, pas de .pkg)"
fi
