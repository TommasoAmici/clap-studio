#!/bin/sh
# Checks portable website output and refusal of missing or unhydrated media.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT" <<'PY'
from html.parser import HTMLParser
from pathlib import Path
import os
import shutil
import struct
import subprocess
import sys
import tempfile

root = Path(sys.argv[1]).resolve()

class LocalFiles(HTMLParser):
    def __init__(self):
        super().__init__()
        self.paths = set()
        self.metadata = {}

    def handle_starttag(self, tag, attributes):
        values = dict(attributes)
        if tag == "meta":
            key = values.get("property", values.get("name"))
            self.metadata[key] = values.get("content")
        for name, value in attributes:
            if name not in ("src", "srcset", "href") or not value:
                continue
            if value.startswith(("https:", "#")):
                continue
            self.paths.add(value)

with tempfile.TemporaryDirectory(prefix="clap-site-test-") as scratch:
    scratch = Path(scratch)
    output = scratch / "portable"
    subprocess.run([str(root / "scripts/website.sh"), str(output)], check=True)
    document = (output / "index.html").read_text()
    files = LocalFiles()
    files.feed(document)
    assert files.paths, "The exported page must have its local assets."
    for name in files.paths:
        assert (output / name).is_file(), f"Missing portable asset: {name}"
    card = output / "og-image.png"
    assert card.read_bytes() == (root / "website/og-image.png").read_bytes(), "The share image must be exported unchanged."
    assert struct.unpack(">II", card.read_bytes()[16:24]) == (1200, 630), "The share image must fit a large link preview."
    assert files.metadata["twitter:card"] == "summary_large_image", "Shared links must request a large preview."
    assert files.metadata["og:image"] == files.metadata["twitter:image"], "Both preview formats must use the same image."
    assert files.metadata["og:image:width"] == "1200" and files.metadata["og:image:height"] == "630"
    published = scratch / "published"
    subprocess.run([str(root / "scripts/website.sh"), str(published)], check=True,
                   env={**os.environ, "WEBSITE_URL": "https://example.com/clap/"})
    previews = LocalFiles()
    previews.feed((published / "index.html").read_text())
    assert previews.metadata["og:image"] == "https://example.com/clap/og-image.png", "Preview images need a public URL, including any site subfolder."
    assert previews.metadata["twitter:image"] == previews.metadata["og:image"]
    assert previews.metadata["og:url"] == "https://example.com/clap/"
    assert (published / "og-image.png").is_file(), "An absolute image URL must still have its file in the export."
    assert "../media/" not in document, "An export must not need the repository next to it."
    for image in (output / "media").glob("*.png"):
        assert image.read_bytes() == (root / "media" / image.name).read_bytes(), "Screenshots must be copied unchanged."
    for view in ("drums", "melody", "ensemble"):
        for theme in ("light", "dark"):
            assert (output / "media" / f"{view}-{theme}.png").is_file(), "Each music choice must work in either appearance."

    fixture = scratch / "fixture"
    (fixture / "scripts").mkdir(parents=True)
    shutil.copy2(root / "scripts/website.sh", fixture / "scripts/website.sh")
    shutil.copytree(root / "website", fixture / "website")
    shutil.copytree(output / "media", fixture / "media")
    image = fixture / "media/map-light.png"
    image.write_text("version https://git-lfs.github.com/spec/v1\noid sha256:example\nsize 123\n")
    refused = scratch / "unhydrated"
    result = subprocess.run([str(fixture / "scripts/website.sh"), str(refused)], capture_output=True, text=True)
    assert result.returncode != 0 and "Git LFS" in result.stderr, "A Git LFS pointer must not become a published image."
    assert not refused.exists(), "An incomplete media checkout must fail before making output."
    image.unlink()
    result = subprocess.run([str(fixture / "scripts/website.sh"), str(refused)], capture_output=True, text=True)
    assert result.returncode != 0 and "Missing image" in result.stderr, "Missing media must stop the build."
    result = subprocess.run([str(fixture / "scripts/website.sh"), str(fixture / "website")], capture_output=True, text=True)
    assert result.returncode != 0 and "outside" in result.stderr, "The build must not overwrite its website source."
    (fixture / "website/og-image.png").unlink()
    result = subprocess.run([str(fixture / "scripts/website.sh"), str(refused)], capture_output=True, text=True)
    assert result.returncode != 0 and "og-image.png" in result.stderr, "A missing share image must stop the build."

print("Website export checks passed.")
PY
