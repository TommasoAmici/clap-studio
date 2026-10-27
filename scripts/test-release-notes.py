#!/usr/bin/env python3
"""Checks the notes included in each automatically published build."""
import importlib.util
from pathlib import Path
import unittest


spec = importlib.util.spec_from_file_location("release_notes", Path(__file__).with_name("release-notes.py"))
notes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notes)


class ReleaseNotesTests(unittest.TestCase):
    def test_build_includes_pending_changes_and_its_version_only(self):
        changelog = """# Changelog
## Unreleased
- Show download activity.
## 0.28.0
### Added
- Bounce VST3 effects.
## 0.27.0
- Native glass controls.
"""
        result = notes.release_notes(changelog, "0.28.0")
        self.assertIn("Show download activity.", result)
        self.assertIn("Bounce VST3 effects.", result)
        self.assertNotIn("Native glass controls.", result)
        self.assertLess(result.index("Show download activity"), result.index("Bounce VST3 effects"))

    def test_empty_pending_section_does_not_add_an_empty_heading(self):
        result = notes.release_notes("# Changelog\n## Unreleased\n\n## 1.0.0\n- Play samples.\n", "1.0.0")
        self.assertEqual(result, "## 1.0.0\n\n- Play samples.\n")

    def test_missing_empty_or_duplicate_version_stops_release(self):
        for changelog in [
            "## Unreleased\n- New work.\n",
            "## 1.0.0\n\n## 0.9.0\n- Old work.\n",
            "## 1.0.0\n- First.\n## 1.0.0\n- Second.\n",
        ]:
            with self.subTest(changelog=changelog), self.assertRaises(ValueError):
                notes.release_notes(changelog, "1.0.0")


if __name__ == "__main__":
    unittest.main()
