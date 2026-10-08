#!/bin/sh
# Builds a release ClapStudio.app in ./build (ad-hoc signed, not sandboxed).
#   scripts/bundle.sh            -> build/ClapStudio.app
#   open build/ClapStudio.app
set -e
. "$(dirname "$0")/env.sh"
cd "$ROOT"
swift build -c release --product ClapStudio

APP="build/ClapStudio.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/ClapStudio" "$APP/Contents/MacOS/ClapStudio"

# Bundle whichever Core ML models have been exported (tools/export_clap.py, tools/export_model.py).
MODELS="$HOME/Library/Application Support/ClapStudio/Models"
for item in CLAPAudio.mlpackage CLAPText.mlpackage CNN14Trunk.mlpackage clap_vocab.json clap_merges.txt; do
  [ -e "$MODELS/$item" ] && cp -R "$MODELS/$item" "$APP/Contents/Resources/" && echo "Bundled $item"
done

# App icon: render clap.icon (Icon Composer) to an .icns; no Xcode needed.
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
swift scripts/render-icon.swift clap.icon "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" && rm -rf "$ICONSET"

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
  <key>CFBundleShortVersionString</key><string>0.3.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 && echo "Signed (ad-hoc)"
echo "Built $APP"
