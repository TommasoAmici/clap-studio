#!/bin/sh
# Initializes this repository's media filters; --check reads only, --media downloads the images.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CHECK=0
MEDIA=0
for arg in "$@"; do
  case "$arg" in
    --check) CHECK=1 ;;
    --media) MEDIA=1 ;;
    *) echo "Unknown Git LFS setup option: $arg. Use --check or --media." >&2; exit 2 ;;
  esac
done
if [ "$CHECK" = 1 ] && [ "$MEDIA" = 1 ]; then
  echo "--check does not download media. Choose one option." >&2
  exit 2
fi
if ! git lfs version >/dev/null 2>&1; then
  if [ "$CHECK" = 0 ] && command -v brew >/dev/null 2>&1; then
    brew install git-lfs
  else
    echo "Install Git LFS (brew install git-lfs), then rerun setup. App builds do not need the media images." >&2
    exit 1
  fi
fi
printf 'Git LFS: %s\n' "$(git lfs version)"
[ "$CHECK" = 0 ] || exit 0
if ! git lfs install --local; then
  echo "Git LFS could not initialize this repository. Keep existing hooks and run git lfs install --manual for instructions." >&2
  exit 1
fi
if [ "$MEDIA" = 1 ]; then
  git lfs pull --include="media/**"
fi
