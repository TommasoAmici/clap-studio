#!/bin/sh
# Builds a self-contained static website with the media it uses.
# Usage: [WEBSITE_URL=https://your-domain/] scripts/website.sh [OUTPUT_DIRECTORY]
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/website}"
python3 - "$ROOT" "$OUT" <<'PY'
from pathlib import Path
from html import escape
import os
import re
import shutil
import sys
from urllib.parse import urljoin, urlsplit

root = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).resolve()
source = root / "website"
if output == root or output == source or output in source.parents or source in output.parents:
    raise SystemExit("Choose an output folder outside the website source.")
html = (source / "index.html").read_text()
version = re.search(r"<key>CFBundleShortVersionString</key><string>([^<]+)</string>",
                    (root / "scripts/bundle.sh").read_text())
if not version:
    raise SystemExit("Missing app version in scripts/bundle.sh.")
version = version.group(1)
site_url = os.environ.get("WEBSITE_URL", "").strip()
if site_url:
    parsed = urlsplit(site_url)
    if parsed.scheme not in ("https", "http") or not parsed.netloc or parsed.query or parsed.fragment:
        raise SystemExit("WEBSITE_URL must be a full website address without a query or fragment.")
    site_url = site_url.rstrip("/") + "/"
    html = html.replace('property="og:url" content="./"',
                        f'property="og:url" content="{escape(site_url, quote=True)}"')
    html = html.replace('content="og-image.png"',
                        f'content="{escape(urljoin(site_url, "og-image.png"), quote=True)}"')
# Gallery code must refresh too: an older script would discard the image query.
html = re.sub(r'((?:src|srcset|href|content)="[^"]+\.(?:png|svg)|src="site\.js)(")',
              lambda match: f'{match[1]}?v={escape(version, quote=True)}{match[2]}', html)
share_image = source / "og-image.png"
if not share_image.is_file() or share_image.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n":
    raise SystemExit("Missing image: website/og-image.png. Render the social preview before building.")
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
for name in ("styles.css", "responsive.css", "site.js", "mark.svg", "og-image.png"):
    shutil.copy2(source / name, output / name)
(output / "index.html").write_text(html.replace("../media/", "media/"))
print(f"Static website: {output}")
print(f"Copied {len(assets)} screenshots; no runtime service or package install is needed.")
PY
