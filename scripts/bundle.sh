#!/bin/sh
# Builds a release ClapStudio.app in ./build (ad-hoc signed, not sandboxed).
#   scripts/bundle.sh            -> build/ClapStudio.app
#   NON_COMMERCIAL=0 scripts/bundle.sh   -> the same without the features whose licenses forbid commercial use
#                                           (bird species: BirdNET is CC BY-NC-SA 4.0)
#   open build/ClapStudio.app
set -e
. "$(dirname "$0")/env.sh"
cd "$ROOT"
swift build -c release --product ClapStudio

APP="build/ClapStudio.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/ClapStudio" "$APP/Contents/MacOS/ClapStudio"

# Bundle whichever Core ML models have been exported (tools/export_clap.py, tools/export_model.py,
# tools/export_birdnet.py).
MODELS="$HOME/Library/Application Support/ClapStudio/Models"
ITEMS="CLAPAudio.mlpackage CLAPText.mlpackage CNN14Trunk.mlpackage clap_vocab.json clap_merges.txt"
[ "$NON_COMMERCIAL" = "0" ] || ITEMS="$ITEMS BirdNET.mlpackage BirdNETLocation.mlpackage birdnet_labels.txt"
for item in $ITEMS; do
  [ -e "$MODELS/$item" ] && cp -R "$MODELS/$item" "$APP/Contents/Resources/" && echo "Bundled $item"
done
# BirdNET is CC BY-NC-SA 4.0: its notice travels with it.
[ "$NON_COMMERCIAL" = "0" ] || ! [ -e "$APP/Contents/Resources/BirdNET.mlpackage" ] || cp licenses/BirdNET.txt "$APP/Contents/Resources/BirdNET-LICENSE.txt"

# App icon: render clap.icon (Icon Composer) to an .icns; no Xcode needed.
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
swift scripts/render-icon.swift clap.icon "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" && rm -rf "$ICONSET"
# The dark appearance of the icon, which the app shows in the Dock while macOS is in dark mode (needs Icon Composer).
if swift scripts/render-icon.swift clap.icon "$ICONSET" Dark >/dev/null 2>&1; then
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIconDark.icns"
  echo "Bundled the dark icon"
fi
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Clap Studio</string>
  <key>CFBundleDisplayName</key><string>Clap Studio</string>
  <key>CFBundleIdentifier</key><string>app.clapstudio.ClapStudio</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>ClapStudio</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.21.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Clap Studio listens when you press Listen, to find library sounds like what you play or sing into the microphone. Nothing is kept or sent anywhere.</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 && echo "Signed (ad-hoc)"
echo "Built $APP"
