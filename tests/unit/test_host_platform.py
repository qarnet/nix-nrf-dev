"""Packaged initializer/defaults and unavailable-host refusal behavior."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class HostPlatformTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.env = dict(
            os.environ,
            HOME=str(self.root / "home"),
            NRFUTIL_HOME=str(self.root / "nrfutil"),
            NIX_NRF_INIT_FAKE_LOG=str(self.root / "queries.log"),
        )
        Path(self.env["HOME"]).mkdir()

    def init(self, name, *args):
        return subprocess.run(
            [os.environ["PLATFORM_INIT"], str(self.root / name), *args],
            env=self.env,
            capture_output=True,
            text=True,
            timeout=30,
        )

    def test_default_initializer_uses_supported_host_preset(self):
        result = self.init("default", "--ncs-version", "v3.4.1")
        self.assertEqual(result.returncode, 0, result.stderr)
        backend = os.environ["PLATFORM_DEFAULT_BACKEND"]
        self.assertIn(
            f'backend = "{backend}";', (self.root / "default/flake.nix").read_text()
        )
        self.assertIn(f"backend {backend}", result.stderr)
        self.assertFalse((self.root / "queries.log").exists())

    def test_west_project_is_portable_and_generation_is_offline(self):
        result = self.init("west", "--backend", "west", "--ncs-version", "v3.4.1")
        self.assertEqual(result.returncode, 0, result.stderr)
        generated = (self.root / "west/flake.nix").read_text()
        self.assertIn('"aarch64-linux"', generated)
        self.assertIn('"x86_64-linux"', generated)
        self.assertFalse((self.root / "queries.log").exists())
        self.assertEqual(
            sorted(p.name for p in (self.root / "west").iterdir()),
            [".envrc", "flake.nix"],
        )

    def test_unavailable_nordic_host_never_acquires_or_creates(self):
        if os.environ["PLATFORM_HOST"] != "aarch64-linux":
            self.skipTest("Nordic backend is available on this host")
        for name in ("new", "existing"):
            if name == "existing":
                (self.root / name).mkdir()
                (self.root / name / "keep").write_text("sentinel")
            result = self.init(name, "--backend", "nrfutil", "--ncs-version", "latest")
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertIn("unavailable on aarch64-linux", result.stderr)
        self.assertFalse((self.root / "new").exists())
        self.assertEqual(
            list((self.root / "existing").iterdir()), [self.root / "existing/keep"]
        )
        self.assertFalse((self.root / "queries.log").exists())
        for flags in (["--yes"], ["--check"], ["--check", "--quiet"]):
            result = subprocess.run(
                [
                    os.environ["PLATFORM_NIX_NRF"],
                    "bootstrap",
                    "--ncs-version",
                    "v3.4.1",
                    *flags,
                ],
                env=self.env,
                capture_output=True,
                text=True,
                timeout=30,
            )
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn("unavailable on aarch64-linux", result.stderr)
        self.assertFalse((self.root / "nrfutil").exists())
        self.assertFalse((Path(self.env["HOME"]) / "ncs").exists())


if __name__ == "__main__":
    unittest.main()
