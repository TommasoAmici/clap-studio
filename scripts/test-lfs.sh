#!/bin/sh
# Checks media tracking, image-free CI checkout and offline restoration in disposable repositories.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="$(mktemp -d /tmp/clap-lfs-test.XXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT HUP INT TERM
git lfs version >/dev/null 2>&1 || { echo "Install Git LFS before running this check." >&2; exit 1; }
git init -q "$SCRATCH/source"
cp "$ROOT/.gitattributes" "$SCRATCH/source/.gitattributes"
cd "$SCRATCH/source"
git config user.name "Clap LFS test"
git config user.email "test@clap.invalid"
git lfs install --local >/dev/null

for path in media/example.png media/nested/example.gif media/photo.jpg media/photo.jpeg media/photo.webp media/photo.avif; do
    [ "$(git check-attr filter -- "$path")" = "$path: filter: lfs" ] || {
        echo "Media image is not tracked by LFS: $path" >&2
        exit 1
    }
done
for path in media/README.md Sources/icon.png; do
    [ "$(git check-attr filter -- "$path")" = "$path: filter: unspecified" ] || {
        echo "A file outside the media images was marked for LFS: $path" >&2
        exit 1
    }
done

mkdir -p media/nested Sources
printf '\211PNG\r\n\032\noriginal demo pixels\n' > media/example.png
printf 'GIF89aoriginal demo animation\n' > media/nested/example.gif
printf 'The media documentation stays in Git.\n' > media/README.md
printf 'Application icon stays in Git.\n' > Sources/icon.png
git add .
git commit -qm "test media tracking"
git show HEAD:media/example.png > "$SCRATCH/pointer"
git lfs pointer --check --strict --file="$SCRATCH/pointer"
git show HEAD:media/README.md > "$SCRATCH/document"
cmp media/README.md "$SCRATCH/document"
git show HEAD:Sources/icon.png > "$SCRATCH/icon"
cmp Sources/icon.png "$SCRATCH/icon"

# A bare remote has the Git pointers but no LFS storage: an image download would fail.
git clone -q --bare --no-local "$SCRATCH/source" "$SCRATCH/remote.git"
GIT_LFS_SKIP_SMUDGE=1 git -c filter.lfs.process="git-lfs filter-process" \
    -c filter.lfs.required=true clone -q --no-local "$SCRATCH/remote.git" "$SCRATCH/ci"
cmp "$SCRATCH/pointer" "$SCRATCH/ci/media/example.png"
[ "$(find "$SCRATCH/ci/.git/lfs/objects" -type f 2>/dev/null | wc -l | tr -d ' ')" = 0 ] || {
    echo "CI checkout downloaded images." >&2
    exit 1
}

# Objects can be supplied from the local cache without changing image bytes.
mkdir -p "$SCRATCH/ci/.git/lfs"
cp -R "$SCRATCH/source/.git/lfs/objects" "$SCRATCH/ci/.git/lfs/"
git -C "$SCRATCH/ci" lfs install --local >/dev/null
git -C "$SCRATCH/ci" lfs checkout >/dev/null
cmp "$SCRATCH/source/media/example.png" "$SCRATCH/ci/media/example.png"
cmp "$SCRATCH/source/media/nested/example.gif" "$SCRATCH/ci/media/nested/example.gif"
[ -z "$(git -C "$SCRATCH/ci" status --porcelain)" ] || {
    echo "Restoring the media changed the checkout." >&2
    exit 1
}
echo "LFS media checks passed."
