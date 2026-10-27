#!/bin/sh
# Fetch the pinned official VST3 interfaces, or update with --latest or a Git revision.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIN="$ROOT/Sources/CVST3/vendor-revision.txt"
VENDOR="$ROOT/Sources/CVST3/vendor/pluginterfaces"
NOTICE="$ROOT/licenses/VST3.txt"

usage() {
  echo "Usage: scripts/vendor-vst3.sh [--latest | REVISION]"
  echo "Without arguments, restore the pinned revision. --latest follows upstream HEAD."
}
if [ "$#" -gt 1 ]; then usage >&2; exit 2; fi
case "${1:-}" in
  --help|-h) usage; exit 0 ;;
  --latest) REVISION=HEAD ;;
  "") REVISION="$(cat "$PIN")" ;;
  -*) usage >&2; exit 2 ;;
  *) REVISION="$1" ;;
esac

STAGING="$(mktemp -d "$ROOT/Sources/CVST3/.vendor-vst3.XXXXXX")"
COMPLETE=0
cleanup() {
  if [ "$COMPLETE" = 0 ] && [ -d "$STAGING/previous" ]; then
    rm -rf "$VENDOR"
    mv "$STAGING/previous" "$VENDOR"
    cp "$STAGING/previous-notice" "$NOTICE"
    cp "$STAGING/previous-pin" "$PIN"
  fi
  rm -rf "$STAGING"
}
trap cleanup 0
trap 'exit 130' INT
trap 'exit 143' TERM

git init --quiet "$STAGING/repository"
git -C "$STAGING/repository" remote add origin https://github.com/steinbergmedia/vst3_pluginterfaces.git
git -C "$STAGING/repository" fetch --quiet --depth=1 origin "$REVISION"
COMMIT="$(git -C "$STAGING/repository" rev-parse --verify 'FETCH_HEAD^{commit}')"
git -C "$STAGING/repository" archive "$COMMIT" LICENSE.txt README.md base gui test vst > "$STAGING/interfaces.tar"
mkdir "$STAGING/interfaces"
tar -xf "$STAGING/interfaces.tar" -C "$STAGING/interfaces"
if ! grep -q '^MIT License' "$STAGING/interfaces/LICENSE.txt"; then
  echo "The upstream license has changed. Review it before updating the vendor files." >&2
  exit 1
fi
test -f "$STAGING/interfaces/vst/ivstaudioprocessor.h"
printf '%s\n' "$COMMIT" > "$STAGING/revision"

# Fetch and validate everything before replacing the current tree. Keep a rollback copy.
cp "$NOTICE" "$STAGING/previous-notice"
cp "$PIN" "$STAGING/previous-pin"
if [ -d "$VENDOR" ]; then
  mv "$VENDOR" "$STAGING/previous"
else
  mkdir -p "$(dirname "$VENDOR")" "$STAGING/previous"
fi
mv "$STAGING/interfaces" "$VENDOR"
cp "$VENDOR/LICENSE.txt" "$NOTICE"
mv "$STAGING/revision" "$PIN"
COMPLETE=1
printf 'Vendored VST3 interfaces at %s\n' "$COMMIT"
echo "Review the diff, then run scripts/build.sh and scripts/test.sh --no-parallel."
