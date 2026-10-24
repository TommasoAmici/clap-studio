#!/bin/sh
# Builds a self-contained static website with the media it uses.
# Usage: scripts/website.sh [OUTPUT_DIRECTORY] (default: build/website)
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/website}"
python3 - "$ROOT" "$OUT" <<'PY'
from pathlib import Path
import re
import shutil
import sys

root = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).resolve()
source = root / "website"
if output == root or output == source or output in source.parents or source in output.parents:
    raise SystemExit("Choose an output folder outside the website source.")
html = (source / "index.html").read_text()
assets = set(re.findall(r"\.\./media/([a-z-]+\.png)", html))
# The music selector can load each of these after the initial page.
assets.update(f"{view}-{theme}.png" for view in ("drums", "melody") for theme in ("light", "dark"))
for name in sorted(assets):
    image = root / "media" / name
    if not image.is_file() or image.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"Missing image: media/{name}. Download the media files with Git LFS first.")
output.mkdir(parents=True, exist_ok=True)
images = output / "media"
images.mkdir(exist_ok=True)
for name in assets:
    shutil.copy2(root / "media" / name, images / name)
for name in ("styles.css", "responsive.css", "site.js", "mark.svg"):
    shutil.copy2(source / name, output / name)
(output / "index.html").write_text(html.replace("../media/", "media/"))
print(f"Static website: {output}")
print(f"Copied {len(assets)} screenshots; no runtime service or package install is needed.")
PY
