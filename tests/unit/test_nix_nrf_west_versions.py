#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
#
# tests/unit/test_nix_nrf_west_versions.py — fake-boundary unit tests for the
# west backend `nix-nrf versions` command module (bin/nix-nrf-west-versions,
# packaged by nix/west-backend/versions-command.nix).
#
# The wrapped module is exercised as a subprocess; the supported-release list
# and JSON come from the wrapper's NIX_NRF_WEST_VERSIONS /
# NIX_NRF_WEST_VERSIONS_JSON variables (baked from the sorted attr names of
# versions.nix at build time — the script source contains no release
# literals). No nrfutil, no sdk-manager, no network.
#
# Run standalone from the repo:
#   python3 tests/unit/test_nix_nrf_west_versions.py
# Wired as checks.west-versions-tests in flake.nix (sandboxed Python stdlib);
# the derivation sets NIX_NRF_WEST_VERSIONS_COMMAND to the packaged module
# executable.

import json
import os
import pathlib
import subprocess
import sys
import unittest


def _resolve_command() -> str:
    # The sandboxed check derivation copies the test to /build root, where
    # the repo-relative fallback cannot be computed; the derivation sets
    # NIX_NRF_WEST_VERSIONS_COMMAND to the packaged module executable.
    configured = os.environ.get("NIX_NRF_WEST_VERSIONS_COMMAND")
    if configured:
        return configured
    try:
        repo_root = pathlib.Path(__file__).resolve().parents[2]
    except IndexError:
        raise RuntimeError(
            "NIX_NRF_WEST_VERSIONS_COMMAND is not set and the repo root is unavailable"
        )
    return str(repo_root / "bin" / "nix-nrf-west-versions")


VERSIONS_COMMAND = _resolve_command()

# Packaged-module assertions only run when the check derivation supplies the
# built module (its baked values come from the real versions.nix).
PACKAGED = bool(os.environ.get("NIX_NRF_WEST_VERSIONS_COMMAND"))


class WestVersionsTestCase(unittest.TestCase):
    def run_versions(self, *args, env_extra=None):
        env = os.environ.copy()
        # Raw-script defaults; the packaged wrapper overrides these with the
        # baked metadata values.
        env.setdefault("NIX_NRF_WEST_VERSIONS", "v3.3.0\nv2.7.0")
        env.setdefault("NIX_NRF_WEST_VERSIONS_JSON", '["v2.7.0","v3.3.0"]')
        if env_extra:
            env.update(env_extra)
        if PACKAGED:
            # The packaged command module is a makeWrapper shell script, so
            # it must be exec'd directly (never via sys.executable).
            argv = [VERSIONS_COMMAND, *args]
        else:
            # The raw repository script is a python file without the +x bit
            # (like the other command modules); run it through the current
            # interpreter.
            argv = [sys.executable, VERSIONS_COMMAND, *args]
        return subprocess.run(argv, env=env, capture_output=True, text=True)

    # 1. No arguments: one supported version per line.
    def test_text_lists_versions_one_per_line(self):
        expected = "v3.3.0\n" if PACKAGED else "v3.3.0\nv2.7.0\n"
        proc = self.run_versions()
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout, expected)

    # 2. --json: exactly one JSON string array on stdout.
    def test_json_emits_string_array(self):
        expected = ["v3.3.0"] if PACKAGED else ["v2.7.0", "v3.3.0"]
        proc = self.run_versions("--json")
        self.assertEqual(proc.returncode, 0)
        data = json.loads(proc.stdout)
        self.assertEqual(data, expected)

    # 3. --help: backend-specific help, exit 0.
    def test_help_exits_0(self):
        proc = self.run_versions("--help")
        self.assertEqual(proc.returncode, 0)
        self.assertIn("nix-nrf versions", proc.stdout)

    # 4. Unknown option: exit 2.
    def test_unknown_option_exits_2(self):
        proc = self.run_versions("--bogus")
        self.assertEqual(proc.returncode, 2)
        self.assertIn("unknown option", proc.stderr)

    # 5. Option combinations: exit 2.
    def test_too_many_options_exits_2(self):
        proc = self.run_versions("--json", "--help")
        self.assertEqual(proc.returncode, 2)
        self.assertIn("too many options", proc.stderr)

    # 6. Packaged module (real metadata): reports exactly v3.3.0, sorted,
    #    text + parseable JSON — and never invokes nrfutil.
    @unittest.skipUnless(
        PACKAGED, "packaged module not supplied by the check derivation"
    )
    def test_packaged_command_reports_metadata_versions(self):
        proc = self.run_versions()
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout, "v3.3.0\n")

        proc = self.run_versions("--json")
        self.assertEqual(proc.returncode, 0)
        data = json.loads(proc.stdout)
        self.assertEqual(data, ["v3.3.0"])


if __name__ == "__main__":
    unittest.main()
