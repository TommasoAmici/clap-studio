#!/bin/sh
# Renders the app's window to a PNG (toolbar included), whatever Space the window is on. Most views need no
# screen capture permission; --native and --update use existing access for system-rendered layers.
# Builds a debug app, launches it, waits for the library to load and quits.
#   scripts/snapshot.sh [out.png] [--select] [--map] [--delay SECONDS]
#     --update  show the update prompt using a local example release (no network; needs existing screen capture access)
#     --update-long-notes  show the update prompt with long example notes scrolled to the end
#     --update-no-notes  show the update prompt for an older release without notes
#     --update-restart  show the restart prompt without installing or restarting (needs existing screen capture access)
#     --update-download  show download activity without contacting GitHub
#     --update-install  show verification and installation activity without installing
#     --native  capture native glass layers at the display's resolution (needs existing screen capture access)
#     --effects open the VST3 Effects drawer for two samples (uses a scratch library)
#     --join open the Join Samples sheet for eight samples (use a scratch library)
#     --join-preset with --join: show the preset name controls
#     --join-folder capture the native folder chooser without saving files (needs existing screen capture access)
#     --effects-save with --effects: show the native Save dialog for one sample
#     --effects-plugin PATH  with --effects: load a test VST3 bundle
#     --effects-amplifier  with --effects: add the built-in amplifier
#     --effects-low-pass  with --effects: add the built-in low-pass filter
#     --effects-erosion  with --effects: add the built-in erosion
#     --effects-high-pass  with --effects: add the built-in high-pass filter
#     --effects-reverb  with --effects: add the built-in reverb
#     --effects-last-control  scroll the effect card to its last control
#     --select  select the first sample (shows the inspector's contents)
#     --map     show the Map tab
#     --edit    with --select: edit the selected sample (reversed, -3 dB, low-pass; changes the library, so set CLAP_DATA_DIR to a copy)
#     --like NAME [--words "dark, no reverb"]  show sounds like the first sample named NAME, adjusted by the words
#     --places  show the Places tab
#     --no-inspector  start with the inspector hidden
#     --drums  open the drum machine with three samples
#     --drum-bars N  with --drums: set the pattern's length
#     --drum-bar N   with --drums: show this bar (counting from 1)
#     --drum-midi FILE  replace the drum pattern with a MIDI file (changes the saved pattern: use a scratch library)
#     --melody  open the melody with two samples and a few notes
#     --melody-bars N  with --melody: repeat the notes up to N bars (to check a long melody draws)
#     --width PX  resize the window to this width first (down to its minimum)
#     --height PX  resize the window to this height in points
#     --scale N  render bitmap captures at N pixels per point (1–4); --update uses the display's resolution
#     --appearance light|dark  force this app's appearance without changing macOS settings
#     --standard-effects  exercise custom panels' glass path (native controls still follow macOS settings)
#     --reduce-transparency  exercise custom panels' opaque fallback without changing macOS settings
#     --increase-contrast  exercise custom panels' high-contrast fallback without changing macOS settings
#     --reduce-motion  disable snapshot animations without changing macOS settings
#     --map-selection  with --map: select three dots to show the floating selection actions
#     --media  reset the drawers and choose suitable sounds from a seeded media library;
#              with --usb, show its scratch demonstration Squid stick instead of a connected drive
#     --animate  write a silent looping GIF of live drums/melody playback (give it a .gif output path)
# Set CLAP_SNAPSHOT_EXECUTABLE to an already-built debug executable to skip compilation.
#     --send-collection [big]  with --nested and --usb: open Send to Squid for that collection (big: nine samples in one sub-collection)
#     --nested  make a collection with two sub-collections and pick it (changes the library: use a scratch one)
#     --usb NAME  show a set ("default" or its name) of the first Squid drive; --rename edits its first bank's name;
#                 "pool" shows the Pool and "pool/Breaks/707" a folder of it; --close Breaks/707 folds a Pool folder shut;
#                 --send Breaks opens the Send sheet for that Pool folder ("-" for the Pool)
#                 --send-bank [pick|N] opens the Send sheet for a bank with five (or N) samples (pick: the second on channel 6);
#                 --send-join with it: join the samples before sending;
#                 --send-same N with it: send to channel N of the following banks;
#                 --send-crowded with it: pretend banks 2 to 40 are full, so the sheet lists many warnings
#     --settings  capture the Settings window (Sidebar tab) instead of the main window
#     --sidebar-order A,B,..  --sidebar-hidden A,B  --sidebar-collapsed A,B  lay the sidebar out for this run only (section ids:
#                 filters, collections, categories, moods, tags, usbDrives, folders; launch arguments, so your preferences are not changed)
# Uses the library already on this Mac. The image is a debug-build rendering: close to the real window, but views
# drawn by AppKit (focus rings, some toolbar styling) may differ a little.
set -e
. "$(dirname "$0")/env.sh"
cd "$ROOT"
OUT=/tmp/clap-snapshot.png
case "${1:-}" in ""|--*) ;; *) OUT="$1"; shift ;; esac
DELAY=9
LAUNCH_ARGS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --update) export CLAP_SNAPSHOT_UPDATE=1 ;;
    --update-long-notes) export CLAP_SNAPSHOT_UPDATE=1; export CLAP_SNAPSHOT_UPDATE_NOTES=long ;;
    --update-no-notes) export CLAP_SNAPSHOT_UPDATE=1; export CLAP_SNAPSHOT_UPDATE_NOTES=none ;;
    --native) export CLAP_SNAPSHOT_NATIVE=1 ;;
    --update-restart) export CLAP_SNAPSHOT_UPDATE=1; export CLAP_SNAPSHOT_UPDATE_RESTART=1 ;;
    --update-download) export CLAP_SNAPSHOT_UPDATE_PROGRESS=download ;;
    --update-install) export CLAP_SNAPSHOT_UPDATE_PROGRESS=install ;;
    --effects) export CLAP_SNAPSHOT_EFFECTS=1 ;;
    --join) export CLAP_SNAPSHOT_JOIN=1 ;;
    --join-preset) export CLAP_SNAPSHOT_JOIN=1; export CLAP_SNAPSHOT_JOIN_PRESET=1 ;;
    --join-folder) export CLAP_SNAPSHOT_JOIN=1; export CLAP_SNAPSHOT_JOIN_FOLDER=1 ;;
    --effects-save) export CLAP_SNAPSHOT_EFFECTS=1; export CLAP_SNAPSHOT_EFFECTS_SAVE=1 ;;
    --effects-plugin) shift; export CLAP_SNAPSHOT_EFFECTS_PLUGIN="$1" ;;
    --effects-amplifier) export CLAP_SNAPSHOT_EFFECTS=1; export CLAP_SNAPSHOT_EFFECTS_AMPLIFIER=1 ;;
    --effects-low-pass) export CLAP_SNAPSHOT_EFFECTS=1; export CLAP_SNAPSHOT_EFFECTS_LOW_PASS=1 ;;
    --effects-erosion) export CLAP_SNAPSHOT_EFFECTS=1; export CLAP_SNAPSHOT_EFFECTS_EROSION=1 ;;
    --effects-high-pass) export CLAP_SNAPSHOT_EFFECTS=1; export CLAP_SNAPSHOT_EFFECTS_HIGH_PASS=1 ;;
    --effects-reverb) export CLAP_SNAPSHOT_EFFECTS=1; export CLAP_SNAPSHOT_EFFECTS_REVERB=1 ;;
    --effects-last-control) export CLAP_SNAPSHOT_EFFECTS_LAST=1 ;;
    --select) export CLAP_SNAPSHOT_SELECT=1 ;;
    --map) export CLAP_SNAPSHOT_MAP=1 ;;
    --map-selection) export CLAP_SNAPSHOT_MAP_SELECTION=1 ;;
    --edit) export CLAP_SNAPSHOT_EDIT=1 ;;
    --nested) export CLAP_SNAPSHOT_NESTED=1 ;;
    --usb) shift; export CLAP_SNAPSHOT_USB="$1" ;;
    --like) shift; export CLAP_SNAPSHOT_LIKE="$1" ;;
    --words) shift; export CLAP_SNAPSHOT_WORDS="$1" ;;
    --places) export CLAP_SNAPSHOT_PLACES=1 ;;
    --drums) export CLAP_SNAPSHOT_DRUMS=1 ;;
    --drum-bars) shift; export CLAP_SNAPSHOT_DRUM_BARS="$1" ;;
    --drum-bar) shift; export CLAP_SNAPSHOT_DRUM_BAR="$1" ;;
    --drum-midi) shift; export CLAP_SNAPSHOT_DRUM_MIDI="$1" ;;
    --melody) export CLAP_SNAPSHOT_MELODY=1 ;;
    --melody-bars) shift; export CLAP_SNAPSHOT_MELODY_BARS="$1" ;;
    --no-inspector) export CLAP_SNAPSHOT_NO_INSPECTOR=1 ;;
    --width) shift; export CLAP_SNAPSHOT_WIDTH="$1" ;;
    --height) shift; export CLAP_SNAPSHOT_HEIGHT="$1" ;;
    --scale) shift; export CLAP_SNAPSHOT_SCALE="$1" ;;
    --appearance) shift
      case "$1" in light|dark) export CLAP_SNAPSHOT_APPEARANCE="$1" ;;
        *) echo "appearance must be light or dark" >&2; exit 2 ;; esac ;;
    --standard-effects)
      export CLAP_SNAPSHOT_REDUCE_TRANSPARENCY=0
      export CLAP_SNAPSHOT_INCREASE_CONTRAST=0
      export CLAP_SNAPSHOT_REDUCE_MOTION=0 ;;
    --reduce-transparency) export CLAP_SNAPSHOT_REDUCE_TRANSPARENCY=1 ;;
    --increase-contrast) export CLAP_SNAPSHOT_INCREASE_CONTRAST=1 ;;
    --reduce-motion) export CLAP_SNAPSHOT_REDUCE_MOTION=1 ;;
    --media) export CLAP_SNAPSHOT_MEDIA=1 ;;
    --animate) export CLAP_SNAPSHOT_ANIMATE=1 ;;
    --close) shift; export CLAP_SNAPSHOT_CLOSE="$1" ;;
    --send) shift; export CLAP_SNAPSHOT_SEND="$1" ;;
    --send-bank) export CLAP_SNAPSHOT_SEND_BANK=1
      case "${2:-}" in pick|[0-9]*) export CLAP_SNAPSHOT_SEND_BANK="$2"; shift ;; esac ;;
    --send-collection) export CLAP_SNAPSHOT_SEND_COLLECTION=1
      case "${2:-}" in big) export CLAP_SNAPSHOT_SEND_COLLECTION=big; shift ;; esac ;;
    --send-join) export CLAP_SNAPSHOT_SEND_JOIN=1 ;;
    --send-same) shift; export CLAP_SNAPSHOT_SEND_SAME="$1" ;;
    --send-crowded) export CLAP_SNAPSHOT_SEND_CROWDED=1 ;;
    --rename) export CLAP_SNAPSHOT_RENAME=1 ;;
    --settings) export CLAP_SNAPSHOT_SETTINGS=1 ;;
    --sidebar-order) shift; LAUNCH_ARGS="$LAUNCH_ARGS -sidebar.order ($1)" ;;
    --sidebar-hidden) shift; LAUNCH_ARGS="$LAUNCH_ARGS -sidebar.hidden ($1)" ;;
    --sidebar-collapsed) shift; LAUNCH_ARGS="$LAUNCH_ARGS -sidebar.collapsed ($1)" ;;
    --delay) shift; DELAY="$1" ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done
if [ -n "${CLAP_SNAPSHOT_EXECUTABLE:-}" ]; then
  EXECUTABLE="$CLAP_SNAPSHOT_EXECUTABLE"
else
  "$SWIFT" build --product ClapStudio >/dev/null
  "$SWIFT" build --product ClapVSTHost >/dev/null
  EXECUTABLE="$("$SWIFT" build --show-bin-path)/ClapStudio"
fi
rm -f "$OUT"
CLAP_SNAPSHOT="$OUT" CLAP_SNAPSHOT_DELAY="$DELAY" "$EXECUTABLE" $LAUNCH_ARGS >/dev/null 2>&1 &
PID=$!
# The app quits itself after writing the image; wait a little longer than its delay, then make sure it is gone.
i=0
LIMIT=$((DELAY + 20))
# A native animation photographs the loop in several passes.
[ -n "${CLAP_SNAPSHOT_ANIMATE:-}" ] && [ -n "${CLAP_SNAPSHOT_NATIVE:-}" ] && LIMIT=$((DELAY + 100))
while [ ! -s "$OUT" ] && [ "$i" -lt "$LIMIT" ]; do
  kill -0 "$PID" 2>/dev/null || break
  sleep 1; i=$((i + 1))
done
kill "$PID" 2>/dev/null || true
if [ -s "$OUT" ]; then
  echo "$OUT"
else
  echo "no image was written" >&2
  [ -n "${CLAP_SNAPSHOT_NATIVE:-}${CLAP_SNAPSHOT_UPDATE:-}" ] &&
    echo "Native captures need the Mac awake and unlocked, and screen capture access for this terminal (System Settings > Privacy & Security > Screen & System Audio Recording)." >&2
  exit 1
fi
