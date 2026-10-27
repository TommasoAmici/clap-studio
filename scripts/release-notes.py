#!/usr/bin/env python3
"""Print the changelog notes for a version, including changes in later builds."""
import argparse
from pathlib import Path
import re
import sys


def release_notes(changelog: str, version: str) -> str:
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("The release version must have three numbers, such as 0.28.0.")
    sections = {}
    current = None
    for line in changelog.splitlines():
        if line.startswith("## "):
            current = line[3:].strip()
            if current in sections:
                raise ValueError(f"Duplicate changelog section: {current}.")
            sections[current] = []
        elif current is not None:
            sections[current].append(line)
    released = "\n".join(sections.get(version, [])).strip()
    if not released:
        raise ValueError(f"Add changelog notes for {version} before publishing it.")
    pending = "\n".join(sections.get("Unreleased", [])).strip()
    parts = []
    if pending:
        parts.append(f"## Changes in this build\n\n{pending}")
    parts.append(f"## {version}\n\n{released}")
    return "\n\n".join(parts) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("--changelog", type=Path, default=Path(__file__).resolve().parent.parent / "CHANGELOG.md")
    args = parser.parse_args()
    try:
        print(release_notes(args.changelog.read_text(), args.version), end="")
    except (OSError, ValueError) as error:
        print(f"Could not prepare release notes: {error}", file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
