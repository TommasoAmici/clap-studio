#!/usr/bin/env python3
"""Allow publication only when the app version exceeds the latest stable release."""
import argparse
import json
import os
from pathlib import Path
import re
import sys
from urllib.error import HTTPError
from urllib.request import Request, urlopen


def version_numbers(version):
    if not isinstance(version, str) or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("The app version must have three numbers, such as 0.29.0.")
    return tuple(int(part) for part in version.split("."))


def bundle_version(script):
    matches = re.findall(r"<key>CFBundleShortVersionString</key>\s*<string>([^<]+)</string>",
                         script.read_text())
    if len(matches) != 1:
        raise ValueError("The bundle script must declare exactly one app version.")
    version_numbers(matches[0])
    return matches[0]


def request_json(path):
    request = Request("https://api.github.com" + path, headers={
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "ClapStudio-release",
    })
    token = os.environ.get("GH_TOKEN")
    if token:
        request.add_header("Authorization", "Bearer " + token)
    try:
        with urlopen(request, timeout=20) as response:
            data = response.read(1024 * 1024 + 1)
    except HTTPError as error:
        error.close()
        raise
    if len(data) > 1024 * 1024:
        raise ValueError("GitHub returned too much release data.")
    return json.loads(data)


def latest_release(repository):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("The repository must have the form owner/name.")
    try:
        latest = request_json(f"/repos/{repository}/releases/latest")
        if not isinstance(latest, dict):
            raise ValueError("GitHub returned unreadable release details.")
        return latest
    except HTTPError as error:
        if error.code != 404:
            raise
        # A 404 can also mean missing repository access, so verify it exists.
        repo = request_json(f"/repos/{repository}")
        if (not isinstance(repo, dict) or not isinstance(repo.get("full_name"), str)
                or repo["full_name"].lower() != repository.lower()):
            raise ValueError("GitHub did not confirm access to the release repository.")
        return None


def should_publish(version, latest):
    candidate = version_numbers(version)
    if latest is None:
        return True
    if (not isinstance(latest, dict) or latest.get("draft") is not False
            or latest.get("prerelease") is not False
            or not isinstance(latest.get("published_at"), str) or not latest["published_at"]):
        raise ValueError("GitHub did not return a published stable release.")
    tag = latest.get("tag_name")
    match = re.fullmatch(r"v?([0-9]+\.[0-9]+\.[0-9]+)(?:-build\.[0-9]+)?", tag or "") if isinstance(tag, str) else None
    if not match:
        raise ValueError("The previous release tag has no readable app version.")
    return candidate > version_numbers(match[1])


def check(version, repository, output=None):
    version_numbers(version)
    latest = latest_release(repository)
    publish = should_publish(version, latest)
    previous = latest["tag_name"] if latest else "no published release"
    action = "Allowing publication of" if publish else "Skipping"
    print(f"{action} app version {version}; previous release: {previous}.", file=sys.stderr)
    if output:
        with output.open("a") as file:
            file.write(f"publish={str(publish).lower()}\nversion={version}\n")
    return publish


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", help="Use the built app's version for the final check.")
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY", "TommasoAmici/clap-studio"))
    parser.add_argument("--github-output", type=Path)
    args = parser.parse_args()
    try:
        version = args.version if args.version is not None else bundle_version(Path(__file__).resolve().parent / "bundle.sh")
        publish = check(version, args.repository, args.github_output)
    except (OSError, ValueError) as error:
        print(f"Could not verify the release version: {error}", file=sys.stderr)
        raise SystemExit(1)
    print(str(publish).lower())


if __name__ == "__main__":
    main()
