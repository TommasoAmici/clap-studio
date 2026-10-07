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

# Bundle the Core ML model when it has been exported (see tools/export_model.py).
MODEL="$HOME/Library/Application Support/ClapStudio/Models/CNN14Trunk.mlpackage"
[ -d "$MODEL" ] && cp -R "$MODEL" "$APP/Contents/Resources/" && echo "Bundled CNN14Trunk model"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Clap Studio</string>
  <key>CFBundleDisplayName</key><string>Clap Studio</string>
  <key>CFBundleIdentifier</key><string>app.clapstudio.ClapStudio</string>
  <key>CFBundleExecutable</key><string>ClapStudio</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
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
