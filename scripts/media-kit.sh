#!/bin/sh
# Regenerates eighteen 3400 × 2000 PNGs and two 1700 × 1000 animated GIFs with synthetic samples.
# Usage: scripts/media-kit.sh [OUTPUT_DIRECTORY]
# The PNGs are native captures of the window (as macOS draws it, glass included), so they match the real app.
# That needs screen capture access for your terminal and a Retina display; keep the window's Space in view.
# The GIFs are native too: the loop repeats exactly, so several passes each photograph the frames they reach.
# The Mac must stay awake and unlocked while it runs.
# Runs sequentially: do not run another snapshot or media-kit capture at the same time.
# Set CLAP_SWIFTPM_DISABLE_SANDBOX=1 when an outer sandbox prevents SwiftPM's sandbox.
set -e
. "$(dirname "$0")/env.sh"
set -u
cd "$ROOT"
OUT="${1:-$ROOT/media}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/clap-media-XXXXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT HUP INT TERM
export CLAP_DATA_DIR="$SCRATCH/library"
export CLAP_MODELS_DIR="$SCRATCH/models"
export CLAP_NO_INDEX=1
mkdir -p "$CLAP_MODELS_DIR"
swift_build() {
  if [ "${CLAP_SWIFTPM_DISABLE_SANDBOX:-0}" = 1 ]; then
    "$SWIFT" build --disable-sandbox "$@"
  else
    "$SWIFT" build "$@"
  fi
}
swift_build -c release --product ClapMediaSeed
swift_build --product ClapStudio
BIN="$(swift_build --show-bin-path)"
SEED_BIN="$(swift_build -c release --show-bin-path)"
"$SEED_BIN/ClapMediaSeed" "$CLAP_DATA_DIR"
# A separate process name also gives this unbundled demo app its own preference domain.
# It never reads or changes the installed app's window, tempo or drawer preferences.
cp "$BIN/ClapStudio" "$SCRATCH/ClapStudioMedia"
# With only the Command Line Tools, SwiftPM records macOS SDK 14 in the binary, and macOS then draws the old
# toolbar and sidebar instead of Liquid Glass. Record the SDK that built it, as Xcode (and the release build) do.
if [ "${SDK_VERSION%%.*}" -ge 26 ]; then
  xcrun vtool -set-build-version macos 14.0 "$SDK_VERSION" -replace \
    -output "$SCRATCH/ClapStudioMedia" "$SCRATCH/ClapStudioMedia" 2>/dev/null
  codesign --force --sign - "$SCRATCH/ClapStudioMedia" 2>/dev/null
fi
export CLAP_SNAPSHOT_EXECUTABLE="$SCRATCH/ClapStudioMedia"
# Native captures show a black window if the display sleeps: wake it and keep it awake until the script ends.
caffeinate -u -t 1
caffeinate -d -i -w $$ &
# The Liquid Glass layout needs about 1700 points of width; narrower windows clip the sidebar and inspector.
POINTS_WIDE=1700; PIXELS_WIDE=$((POINTS_WIDE * 2))
for appearance in light dark; do
  for view in library map drums melody ensemble places squid-banks squid-pool squid-send; do
    case "$view" in
      library) set -- --select ;;
      map) set -- --map --select ;;
      drums) set -- --drums --select ;;
      melody) set -- --melody --select ;;
      ensemble) set -- --drums --melody --select ;;
      places) set -- --places --select ;;
      squid-banks) set -- --usb Studio --select ;;
      squid-pool) set -- --usb pool --select ;;
      squid-send) set -- --usb pool/Drums/Kicks --select --send Drums/Kicks ;;
    esac
    # --native captures the window as macOS draws it, so the images match what you see when using the app.
    scripts/snapshot.sh "$OUT/$view-$appearance.png" --media --native \
      --appearance "$appearance" --width "$POINTS_WIDE" --height 1000 "$@"
    WIDTH="$(sips -g pixelWidth "$OUT/$view-$appearance.png" | awk '/pixelWidth/ { print $2 }')"
    if [ "$WIDTH" != "$PIXELS_WIDE" ]; then
      echo "$view-$appearance.png is $WIDTH pixels wide, not $PIXELS_WIDE: run on a Retina display with the default scaled resolution." >&2
      exit 1
    fi
  done
  scripts/snapshot.sh "$OUT/ensemble-playing-$appearance.gif" --media --native --animate \
    --appearance "$appearance" --width "$POINTS_WIDE" --height 1000 --scale 1 --drums --melody --select
done
echo "Media kit saved in $OUT"
