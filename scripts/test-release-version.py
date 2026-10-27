#!/usr/bin/env python3
"""Checks that publication requires a newer app version and a readable release."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError


spec = importlib.util.spec_from_file_location("release_version", Path(__file__).with_name("check-release-version.py"))
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


def release(tag):
    return {"tag_name": tag, "draft": False, "prerelease": False,
            "published_at": "2026-10-27T12:00:00Z"}


def http_error(code):
    error = HTTPError("https://api.github.com/example", code, "Failure", {}, None)
    error.close()
    return error


class ReleaseVersionTests(unittest.TestCase):
    def test_cli_uses_existing_credentials_and_reads_the_http_status(self):
        response = subprocess.CompletedProcess([], 0, stdout=(
            b'HTTP/2.0 200 OK\r\nContent-Type: application/json\r\n\r\n'
            + json.dumps(release("v0.28.0")).encode()), stderr=b"")
        with patch.object(guard.shutil, "which", return_value="/tools/gh"), patch.object(
            guard.subprocess, "run", return_value=response
        ) as run, patch.object(guard, "request_data") as direct:
            self.assertEqual(guard.request_json("/repos/example/app/releases/latest"),
                             release("v0.28.0"))
            direct.assert_not_called()
            command = run.call_args.args[0]
            self.assertEqual(command[:5], ["/tools/gh", "api", "--hostname", "github.com", "--include"])
            self.assertEqual(run.call_args.kwargs["timeout"], 20)

    def test_cli_errors_keep_their_status_and_never_fall_back_to_anonymous_requests(self):
        for code in [404, 401, 403, 429, 500]:
            response = subprocess.CompletedProcess([], 1, stdout=(
                f'HTTP/2.0 {code} Failure\n\n{{"message": "Failure"}}'.encode()), stderr=b"")
            with self.subTest(code=code), patch.object(guard.shutil, "which", return_value="gh"), \
                    patch.object(guard.subprocess, "run", return_value=response), \
                    patch.object(guard, "request_data") as direct:
                with self.assertRaises(HTTPError) as error:
                    guard.request_json("/repos/example/app/releases/latest")
                self.assertEqual(error.exception.code, code)
                error.exception.close()
                direct.assert_not_called()

    def test_incomplete_cli_output_and_timeouts_cannot_enable_publication(self):
        for code, output in [(1, b""), (0, b"{}"), (1, b"HTTP/2.0 200 OK\n\n{}"),
                             (0, b"HTTP/2.0 200 OK\n\nnot JSON")]:
            response = subprocess.CompletedProcess([], code, stdout=output, stderr=b"")
            with self.subTest(output=output), patch.object(guard.shutil, "which", return_value="gh"), \
                    patch.object(guard.subprocess, "run", return_value=response), \
                    self.assertRaises((OSError, ValueError)):
                guard.request_json("/repos/example/app/releases/latest")
        with patch.object(guard.shutil, "which", return_value="gh"), patch.object(
            guard.subprocess, "run", side_effect=subprocess.TimeoutExpired("gh", 20)
        ), self.assertRaises(OSError):
            guard.request_json("/repos/example/app/releases/latest")

    def test_direct_https_remains_available_without_the_cli_and_size_is_limited(self):
        with patch.object(guard.shutil, "which", return_value=None), patch.object(
            guard, "request_data", return_value=b'{"tag_name": "v0.28.0"}'
        ) as direct:
            self.assertEqual(guard.request_json("/example"), {"tag_name": "v0.28.0"})
            direct.assert_called_once_with("/example")
        with patch.object(guard.shutil, "which", return_value=None), patch.object(
            guard, "request_data", return_value=b"x" * (1024 * 1024 + 1)
        ), self.assertRaises(ValueError):
            guard.request_json("/example")

    def test_newer_version_publishes_even_when_build_number_is_smaller(self):
        for version, tag in [("0.29.0", "v0.28.0-build.999"),
                             ("0.10.0", "v0.9.9"),
                             ("1.0.0", "v0.99.99-build.999")]:
            with self.subTest(version=version, tag=tag):
                self.assertTrue(guard.should_publish(version, release(tag)))

    def test_same_or_older_version_never_publishes_another_build(self):
        for version, tag in [("0.28.0", "v0.28.0-build.1"),
                             ("0.28.0", "0.28.0"),
                             ("0.27.9", "v0.28.0-build.1"),
                             ("0.9.9", "v0.10.0")]:
            with self.subTest(version=version, tag=tag):
                self.assertFalse(guard.should_publish(version, release(tag)))

    def test_only_valid_published_stable_releases_can_be_compared(self):
        invalid = [[], {}, release("v0.28"), release("v0.28.0-beta.1"),
                   release("v0.28.0-build.bad")]
        for field, value in [("draft", True), ("prerelease", True),
                             ("published_at", None), ("tag_name", 123)]:
            item = release("v0.28.0")
            item[field] = value
            invalid.append(item)
        for item in invalid:
            with self.subTest(item=item), self.assertRaises(ValueError):
                guard.should_publish("0.29.0", item)

    def test_invalid_candidate_stops_before_any_release_decision(self):
        for version in ["", "v0.29.0", "0.29", "0.29.0-build.1", "0.29.0\n"]:
            with self.subTest(version=version), self.assertRaises(ValueError):
                guard.should_publish(version, release("v0.28.0"))
            with self.subTest(version=version), patch.object(guard, "latest_release") as lookup:
                with self.assertRaises(ValueError):
                    guard.check(version, "TommasoAmici/clap-studio")
                lookup.assert_not_called()

    def test_missing_release_is_allowed_only_for_a_readable_repository(self):
        missing = http_error(404)
        with patch.object(guard, "request_json", side_effect=[
            missing, {"full_name": "TommasoAmici/clap-studio"}
        ]):
            self.assertIsNone(guard.latest_release("TommasoAmici/clap-studio"))
            self.assertTrue(guard.should_publish("0.29.0", None))
        for response in [missing, {"full_name": "other/repository"}, {"full_name": 123}, {}, []]:
            with self.subTest(response=response), patch.object(
                guard, "request_json", side_effect=[missing, response]
            ), self.assertRaises((ValueError, HTTPError)):
                guard.latest_release("TommasoAmici/clap-studio")

    def test_api_failures_and_bad_responses_never_become_first_release(self):
        for error in [http_error(code) for code in [401, 403, 429, 500]] + [URLError("offline")]:
            with self.subTest(error=error), patch.object(
                guard, "request_json", side_effect=error
            ), self.assertRaises((HTTPError, URLError)):
                guard.latest_release("TommasoAmici/clap-studio")
        for response in [None, [], "unreadable"]:
            with self.subTest(response=response), patch.object(
                guard, "request_json", return_value=response
            ), self.assertRaises(ValueError):
                guard.latest_release("TommasoAmici/clap-studio")
        with self.assertRaises(ValueError):
            guard.should_publish("0.29.0", {})

    def test_declared_bundle_version_is_the_candidate(self):
        with tempfile.TemporaryDirectory() as folder:
            script = Path(folder) / "bundle.sh"
            script.write_text('<key>CFBundleShortVersionString</key><string>0.28.0</string>')
            self.assertEqual(guard.bundle_version(script), "0.28.0")
            for source in ["", script.read_text() * 2,
                           '<key>CFBundleShortVersionString</key><string>bad</string>']:
                script.write_text(source)
                with self.subTest(source=source), self.assertRaises(ValueError):
                    guard.bundle_version(script)

    def test_output_is_written_only_after_a_successful_check(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / "output"
            with patch.object(guard, "latest_release", return_value=release("v0.28.0")):
                guard.check("0.29.0", "TommasoAmici/clap-studio", output)
            self.assertEqual(output.read_text(), "publish=true\nversion=0.29.0\n")
            output.unlink()
            with patch.object(guard, "latest_release", side_effect=URLError("offline")):
                with self.assertRaises(URLError):
                    guard.check("0.29.0", "TommasoAmici/clap-studio", output)
            self.assertFalse(output.exists(), "An unavailable release check cannot enable publication")


if __name__ == "__main__":
    unittest.main()
