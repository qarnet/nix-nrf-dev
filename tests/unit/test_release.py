#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
#
# tests/unit/test_release.py — regression suite for the release consistency
# contract (release.json + CHANGELOG.md) and the scripts/release.py utility.
#
# The real repository files must pass; every contract element has an
# independent negative proof; notes no-overwrite is proven through a
# temporary directory. The real manifest/changelog are only ever read.
#
# Run standalone from the repo:  python3 tests/unit/test_release.py
# Wired as part of checks.release-consistency in
# nix/flake/checks/release.nix (sandboxed Python stdlib): the derivation
# copies release.json, CHANGELOG.md, scripts/release.py, and this test into
# a build-dir layout, so repo-root detection keeps working there.

import importlib.util
import pathlib
import subprocess
import sys
import tempfile
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
RELEASE_SCRIPT = REPO_ROOT / "scripts" / "release.py"
RELEASE_JSON = REPO_ROOT / "release.json"
CHANGELOG = REPO_ROOT / "CHANGELOG.md"

_spec = importlib.util.spec_from_file_location("nix_nrf_release", RELEASE_SCRIPT)
release = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(release)

VERSION = "0.1.0"
HEADING = "## [0.1.0]"
UNRELEASED = "## [Unreleased]"
TABLE_ROW = "| [0.1.0](#010) |"


def synthetic_changelog(version="9.9.9"):
    """A contract-satisfying fixture; the real CHANGELOG.md passes too."""
    anchor = version.replace(".", "")
    return (
        "# Changelog\n"
        "\n"
        "| Version | Date | Highlights |\n"
        "|---|---|---|\n"
        "| [{0}](#{1}) | 2026-01-01 | summary |\n"
        "\n"
        "## [Unreleased]\n"
        "\n"
        "- placeholder\n"
        "\n"
        "## [{0}]\n"
        "\n"
        "- feature body line\n"
    ).format(version, anchor)


class RealFileContractTest(unittest.TestCase):
    def test_real_manifest_and_changelog_pass(self):
        manifest = RELEASE_JSON.read_text()
        changelog = CHANGELOG.read_text()
        self.assertEqual(release.collect_errors(manifest, changelog), [])

    def test_real_version_is_0_1_0(self):
        version, diags = release.load_release_json(RELEASE_JSON.read_text())
        self.assertEqual(diags, [])
        self.assertEqual(version, VERSION)

    def test_version_command_prints_only_version(self):
        proc = subprocess.run(
            [sys.executable, str(RELEASE_SCRIPT), "version"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stdout, VERSION + "\n")
        self.assertEqual(proc.stderr, "")

    def test_check_command_passes_on_real_files(self):
        proc = subprocess.run(
            [sys.executable, str(RELEASE_SCRIPT), "check"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_extracted_release_notes_nonempty_with_first_release_content(self):
        body = release.current_release_body(CHANGELOG.read_text(), VERSION)
        self.assertIsNotNone(body)
        self.assertTrue(body.strip())
        for needle in [
            "mkNrfShell",
            "x86_64-linux",
            "nrfutil",
            "west",
            "init-project",
            "OpenOCD",
            "plugdev",
            "v3.3.0",
        ]:
            self.assertIn(needle, body)
        self.assertIn("Key limitations", body)


class ManifestNegativeTest(unittest.TestCase):
    def assert_rejected(self, text, needle):
        version, diags = release.load_release_json(text)
        self.assertIsNone(version)
        self.assertTrue(
            any(needle in d for d in diags),
            "expected a diagnostic containing {0!r}, got {1}".format(needle, diags),
        )

    def test_rejects_malformed_json(self):
        self.assert_rejected('{"version": ', "malformed JSON")

    def test_rejects_non_object_manifest(self):
        self.assert_rejected('["0.1.0"]', "must be a JSON object")
        self.assert_rejected('"0.1.0"', "must be a JSON object")

    def test_rejects_missing_version_key(self):
        self.assert_rejected("{}", 'exactly the "version" key')

    def test_rejects_extra_keys(self):
        self.assert_rejected(
            '{"version": "0.1.0", "ncsVersion": "v3.3.0"}',
            'exactly the "version" key',
        )

    def test_rejects_non_string_version(self):
        self.assert_rejected('{"version": 1}', "must be a string")
        self.assert_rejected('{"version": null}', "must be a string")

    def test_rejects_leading_v(self):
        self.assert_rejected('{"version": "v0.1.0"}', "not strict stable SemVer")

    def test_rejects_partial_semver(self):
        self.assert_rejected('{"version": "0.1"}', "not strict stable SemVer")
        self.assert_rejected('{"version": "0"}', "not strict stable SemVer")

    def test_rejects_prerelease_metadata(self):
        self.assert_rejected('{"version": "0.1.0-rc1"}', "not strict stable SemVer")

    def test_rejects_build_metadata(self):
        self.assert_rejected('{"version": "0.1.0+build5"}', "not strict stable SemVer")


class ChangelogContractNegativeTest(unittest.TestCase):
    def assert_single_violation(self, text, needle):
        diags = release.check_changelog_contract(text, "9.9.9")
        self.assertEqual(len(diags), 1, diags)
        self.assertIn(needle, diags[0])

    def test_synthetic_fixture_passes(self):
        self.assertEqual(
            release.check_changelog_contract(synthetic_changelog(), "9.9.9"), []
        )

    def test_rejects_missing_table_row(self):
        row = "| [9.9.9](#999) |"
        text = "\n".join(
            l for l in synthetic_changelog().splitlines() if not l.startswith(row)
        )
        self.assert_single_violation(text, "release table must contain a row")

    def test_rejects_missing_current_heading(self):
        text = "\n".join(
            l for l in synthetic_changelog().splitlines() if l != "## [9.9.9]"
        )
        self.assert_single_violation(text, 'exact heading "## [9.9.9]"')

    def test_rejects_missing_unreleased_heading(self):
        text = "\n".join(
            l for l in synthetic_changelog().splitlines() if l != "## [Unreleased]"
        )
        self.assert_single_violation(text, 'heading "## [Unreleased]"')

    def test_rejects_wrong_ordering(self):
        lines = synthetic_changelog().splitlines()
        u = lines.index("## [Unreleased]")
        r = lines.index("## [9.9.9]")
        lines[u], lines[r] = lines[r], lines[u]
        self.assert_single_violation(
            "\n".join(lines), 'must appear before the "## [9.9.9]" heading'
        )

    def test_rejects_empty_current_body(self):
        text = synthetic_changelog().replace(
            "## [9.9.9]\n\n- feature body line\n", "## [9.9.9]\n"
        )
        self.assert_single_violation(text, "must be nonempty")


class NotesCommandTest(unittest.TestCase):
    def test_notes_writes_body_and_refuses_overwrite(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = pathlib.Path(tmp) / "notes.md"
            proc = subprocess.run(
                [
                    sys.executable,
                    str(RELEASE_SCRIPT),
                    "notes",
                    "--output",
                    str(out),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr)
            content = out.read_text()
            self.assertTrue(content.strip())
            self.assertIn("mkNrfShell", content)
            # No-overwrite: second run must refuse and leave the file alone.
            before = out.read_text()
            proc = subprocess.run(
                [
                    sys.executable,
                    str(RELEASE_SCRIPT),
                    "notes",
                    "--output",
                    str(out),
                ],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("refusing to overwrite", proc.stderr)
            self.assertEqual(out.read_text(), before)


if __name__ == "__main__":
    unittest.main()
