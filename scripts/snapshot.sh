#!/bin/sh
# Renders the running app's window to a PNG (toolbar included) with no screen capture permission, whatever Space
# the window is on. Builds a debug app, launches it, waits for the library to load and quits.
#   scripts/snapshot.sh [out.png] [--select] [--map] [--delay SECONDS]
#     --select  select the first sample (shows the inspector's contents)
#     --map     show the Map tab
# Uses the library already on this Mac. The image is a debug-build rendering: close to the real window, but views
# drawn by AppKit (focus rings, some toolbar styling) may differ a little.
set -e
. "$(dirname "$0")/env.sh"
cd "$ROOT"
OUT=/tmp/clap-snapshot.png
case "${1:-}" in ""|--*) ;; *) OUT="$1"; shift ;; esac
DELAY=9
while [ $# -gt 0 ]; do
  case "$1" in
    --select) export CLAP_SNAPSHOT_SELECT=1 ;;
    --map) export CLAP_SNAPSHOT_MAP=1 ;;
    --delay) shift; DELAY="$1" ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done
swift build --product ClapStudio >/dev/null
rm -f "$OUT"
CLAP_SNAPSHOT="$OUT" CLAP_SNAPSHOT_DELAY="$DELAY" "$(swift build --show-bin-path)/ClapStudio" >/dev/null 2>&1 &
PID=$!
# The app quits itself after writing the image; wait a little longer than its delay, then make sure it is gone.
i=0
while [ ! -s "$OUT" ] && [ "$i" -lt $((DELAY + 20)) ]; do sleep 1; i=$((i + 1)); done
kill "$PID" 2>/dev/null || true
[ -s "$OUT" ] && echo "$OUT" || { echo "no image was written" >&2; exit 1; }
