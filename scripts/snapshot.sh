#!/bin/sh
# Renders the running app's window to a PNG (toolbar included) with no screen capture permission, whatever Space
# the window is on. Builds a debug app, launches it, waits for the library to load and quits.
#   scripts/snapshot.sh [out.png] [--select] [--map] [--delay SECONDS]
#     --select  select the first sample (shows the inspector's contents)
#     --map     show the Map tab
#     --edit    with --select: edit the selected sample (reversed, -3 dB, low-pass; changes the library, so set CLAP_DATA_DIR to a copy)
#     --like NAME [--words "dark, no reverb"]  show sounds like the first sample named NAME, adjusted by the words
#     --places  show the Places tab
#     --no-inspector  start with the inspector hidden
#     --drums  open the drum machine with three samples
#     --drum-bars N  with --drums: set the pattern's length
#     --drum-bar N   with --drums: show this bar (counting from 1)
#     --melody  open the melody with two samples and a few notes
#     --melody-bars N  with --melody: repeat the notes up to N bars (to check a long melody draws)
#     --width PX  resize the window to this width first (down to its minimum)
#     --usb NAME  show a set ("default" or its name) of the first Squid drive; --rename edits its first bank's name;
#                 "pool" shows the Pool and "pool/Breaks/707" a folder of it; --close Breaks/707 folds a Pool folder shut;
#                 --send Breaks opens the Send sheet for that Pool folder ("-" for the Pool)
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
    --edit) export CLAP_SNAPSHOT_EDIT=1 ;;
    --usb) shift; export CLAP_SNAPSHOT_USB="$1" ;;
    --like) shift; export CLAP_SNAPSHOT_LIKE="$1" ;;
    --words) shift; export CLAP_SNAPSHOT_WORDS="$1" ;;
    --places) export CLAP_SNAPSHOT_PLACES=1 ;;
    --drums) export CLAP_SNAPSHOT_DRUMS=1 ;;
    --drum-bars) shift; export CLAP_SNAPSHOT_DRUM_BARS="$1" ;;
    --drum-bar) shift; export CLAP_SNAPSHOT_DRUM_BAR="$1" ;;
    --melody) export CLAP_SNAPSHOT_MELODY=1 ;;
    --melody-bars) shift; export CLAP_SNAPSHOT_MELODY_BARS="$1" ;;
    --no-inspector) export CLAP_SNAPSHOT_NO_INSPECTOR=1 ;;
    --width) shift; export CLAP_SNAPSHOT_WIDTH="$1" ;;
    --close) shift; export CLAP_SNAPSHOT_CLOSE="$1" ;;
    --send) shift; export CLAP_SNAPSHOT_SEND="$1" ;;
    --rename) export CLAP_SNAPSHOT_RENAME=1 ;;
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
