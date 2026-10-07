#!/usr/bin/env python3
"""Exercise the read-only requirement probe through its subprocess interface."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

PROBE = os.environ.get(
    "NIX_NRF_WEST_REQUIREMENT_PROBE",
    str(
        Path(__file__).resolve().parents[2]
        / "bin/backends/west/check-python-requirements.py"
    ),
)


class RequirementsProbeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.workspace = self.root / "workspace with spaces"
        self.workspace.mkdir()
        self.site = self.root / "site"
        dist = self.site / "nix_nrf_probe_fixture-2.1.dist-info"
        dist.mkdir(parents=True)
        (dist / "METADATA").write_text(
            "Metadata-Version: 2.1\nName: nix-nrf-probe-fixture\nVersion: 2.1\n"
        )

    def probe(self, text):
        req = self.workspace / "requirements.txt"
        req.write_text(text)
        before = {p: p.read_bytes() for p in self.workspace.rglob("*") if p.is_file()}
        result = subprocess.run(
            [sys.executable, "-B", PROBE, str(self.workspace), json.dumps([str(req)])],
            env={**os.environ, "PYTHONPATH": str(self.site)},
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(
            before,
            {p: p.read_bytes() for p in self.workspace.rglob("*") if p.is_file()},
        )
        return result

    def test_installed_versions_markers_extras_and_index_directives(self):
        result = self.probe(
            "--index-url https://invalid.example\n"
            "nix-nrf-probe-fixture[optional]>=2,<3 # selected root\n"
            "nix-nrf-missing-fixture; python_version < '0'\n"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_reports_missing_and_incompatible_roots(self):
        result = self.probe("nix-nrf-missing-fixture\nnix-nrf-probe-fixture>=3\n")
        self.assertEqual(result.returncode, 1)
        self.assertIn("nix-nrf-missing-fixture: not installed", result.stdout)
        self.assertIn("installed 2.1, requires >=3", result.stdout)

    def test_recursive_includes_and_cycles(self):
        included = self.workspace / "nested requirements.txt"
        included.write_text(
            "--requirement=requirements.txt\nnix-nrf-probe-fixture==2.1\n"
        )
        result = self.probe('-r "nested requirements.txt"\n')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_escape_and_symlink_escape(self):
        outside = self.root / "outside.txt"
        outside.write_text("nix-nrf-probe-fixture\n")
        (self.workspace / "linked.txt").symlink_to(outside)
        for include in ("../outside.txt", "linked.txt"):
            with self.subTest(include=include):
                result = self.probe(f"-r {include}\n")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("requirement include escapes workspace", result.stderr)

    def test_rejects_excessive_depth(self):
        for i in range(18):
            (self.workspace / f"{i}.txt").write_text(f"-r {i + 1}.txt\n")
        result = self.probe("-r 0.txt\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("exceeds depth limit", result.stderr)

    def test_invalid_or_missing_requirement_file_fails(self):
        for text in ("not a requirement\n", "-r absent.txt\n"):
            with self.subTest(text=text):
                self.assertNotEqual(self.probe(text).returncode, 0)


if __name__ == "__main__":
    unittest.main()
