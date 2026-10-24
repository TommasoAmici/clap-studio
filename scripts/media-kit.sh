#!/bin/sh
# Regenerates eighteen 3200 × 2000 PNGs and two 1600 × 1000 animated GIFs with synthetic samples.
# Usage: scripts/media-kit.sh [OUTPUT_DIRECTORY]
# Runs sequentially: do not run another snapshot or media-kit capture at the same time.
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
"$SWIFT" build -c release --product ClapMediaSeed
"$SWIFT" build --product ClapStudio
BIN="$("$SWIFT" build --show-bin-path)"
SEED_BIN="$("$SWIFT" build -c release --show-bin-path)"
"$SEED_BIN/ClapMediaSeed" "$CLAP_DATA_DIR"
# A separate process name also gives this unbundled demo app its own preference domain.
# It never reads or changes the installed app's window, tempo or drawer preferences.
cp "$BIN/ClapStudio" "$SCRATCH/ClapStudioMedia"
export CLAP_SNAPSHOT_EXECUTABLE="$SCRATCH/ClapStudioMedia"
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
    scripts/snapshot.sh "$OUT/$view-$appearance.png" --media \
      --appearance "$appearance" --width 1600 --height 1000 --scale 2 "$@"
  done
  scripts/snapshot.sh "$OUT/ensemble-playing-$appearance.gif" --media --animate \
    --appearance "$appearance" --width 1600 --height 1000 --scale 1 --drums --melody --select
done
echo "Media kit saved in $OUT"
