#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
#
# tests/unit/test_west_workspace_fixture.py — safety/behavior unit tests for
# the shared fake-west-workspace fixture (tests/fixtures/west-workspace.py)
# used by the west quoting and shell-boundary gates.
#
# Exercises the PUBLIC CLI (west-workspace.py --workspace PATH --mode
# stdout|log) as a subprocess in temporary directories only: stdout/log mode
# structure and executable behavior, plus every safety refusal (filesystem
# root, current HOME, existing non-empty directory with sentinel preserved,
# symlink escape with target preserved, and existing non-directory path with
# file preserved). No network, no deletion outside the temp roots.
#
# Run standalone from the repo:
#   python3 tests/unit/test_west_workspace_fixture.py
# Wired as part of checks.west-bootstrap-tests (sandboxed Python stdlib); the
# derivation sets NIX_NRF_WEST_FIXTURE to the fixture store path.

import os
import pathlib
import subprocess
import sys
import tempfile
import unittest


def _resolve_fixture() -> str:
    # The sandboxed check derivation copies the test to /build root, where
    # the repo-relative fallback cannot be computed; NIX_NRF_WEST_FIXTURE is
    # set there.
    configured = os.environ.get("NIX_NRF_WEST_FIXTURE")
    if configured:
        return configured
    repo_root = pathlib.Path(__file__).resolve().parents[2]
    return str(repo_root / "tests" / "fixtures" / "west-workspace.py")


FIXTURE = _resolve_fixture()

BASE_FILES = {
    ".west/config": "[manifest]\npath = nrf\nfile = west.yml\n",
    "nrf/west.yml": "manifest:\n",
    "zephyr/zephyr-env.sh": "#!/bin/sh\n",
    "zephyr/scripts/requirements.txt": "-r requirements-base.txt\n",
    "zephyr/scripts/requirements-base.txt": "west>=0.14.0\n",
    "nrf/scripts/requirements.txt": "-r requirements-base.txt\n",
    "nrf/scripts/requirements-base.txt": "west>=1.4.0\n",
    "bootloader/mcuboot/scripts/requirements.txt": "pyelftools>=0.29\n",
}


def run_fixture(workspace, mode, env_extra=None):
    env = os.environ.copy()
    if env_extra:
        env.update(env_extra)
    return subprocess.run(
        [sys.executable, FIXTURE, "--workspace", str(workspace), "--mode", mode],
        capture_output=True,
        text=True,
        env=env,
    )


def run_executable(path, args, env_extra=None):
    env = os.environ.copy()
    if env_extra:
        env.update(env_extra)
    return subprocess.run([str(path)] + args, capture_output=True, text=True, env=env)


class WestWorkspaceFixtureTest(unittest.TestCase):
    def test_stdout_mode_creates_ready_structure(self):
        with tempfile.TemporaryDirectory() as tmp:
            ws = pathlib.Path(tmp) / "ncs" / "v3.3.0"
            proc = run_fixture(ws, "stdout")
            self.assertEqual(proc.returncode, 0, proc.stderr)
            for rel, content in BASE_FILES.items():
                self.assertEqual((ws / rel).read_text(), content, rel)
            for name in ("python", "pip", "west"):
                exe = ws / ".venv" / "bin" / name
                self.assertTrue(exe.is_file(), name)
                self.assertTrue(os.access(exe, os.X_OK), f"{name} not executable")

    def test_stdout_mode_west_behavior(self):
        with tempfile.TemporaryDirectory() as tmp:
            ws = pathlib.Path(tmp) / "ncs" / "v3.3.0"
            proc = run_fixture(ws, "stdout")
            self.assertEqual(proc.returncode, 0, proc.stderr)
            west = ws / ".venv" / "bin" / "west"
            version = run_executable(west, ["--version"])
            self.assertEqual(version.returncode, 0)
            self.assertIn("West version: v1.4.0", version.stdout)
            listing = run_executable(
                west, ["list", "--format=json"], {"ZEPHYR_BASE": "/fake/zephyr"}
            )
            self.assertEqual(listing.returncode, 0)
            self.assertIn(
                "FAKE_WEST argv=list --format=json ZEPHYR_BASE=/fake/zephyr",
                listing.stdout,
            )

    def test_log_mode_creates_structure_and_venv_log(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = pathlib.Path(tmp) / "home"
            home.mkdir()
            ws = home / "ncs" / "v3.3.0"
            proc = run_fixture(ws, "log", {"HOME": str(home)})
            self.assertEqual(proc.returncode, 0, proc.stderr)
            for rel, content in BASE_FILES.items():
                self.assertEqual((ws / rel).read_text(), content, rel)
            env = {"HOME": str(home)}
            py = run_executable(ws / ".venv" / "bin" / "python", ["-c", "pass"], env)
            self.assertEqual(py.returncode, 0)
            pip = run_executable(ws / ".venv" / "bin" / "pip", ["install"], env)
            self.assertEqual(pip.returncode, 0)
            west = run_executable(ws / ".venv" / "bin" / "west", ["list"], env)
            self.assertEqual(west.returncode, 0)
            log = (home / "venv.log").read_text()
            self.assertIn("python argv=-c pass", log)
            self.assertIn("pip argv=install", log)
            self.assertIn("west argv=list ZEPHYR_BASE=", log)
            version = run_executable(ws / ".venv" / "bin" / "west", ["--version"], env)
            self.assertEqual(version.returncode, 0)
            self.assertIn("West version: v1.4.0", version.stdout)

    def test_existing_empty_directory_is_used(self):
        with tempfile.TemporaryDirectory() as tmp:
            ws = pathlib.Path(tmp) / "ws"
            ws.mkdir()
            proc = run_fixture(ws, "stdout")
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertTrue((ws / ".west" / "config").is_file())

    def test_refuses_filesystem_root(self):
        proc = run_fixture("/", "stdout")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("filesystem root", proc.stderr)

    def test_refuses_current_home(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = pathlib.Path(tmp) / "home"
            home.mkdir()
            proc = run_fixture(home, "stdout", {"HOME": str(home)})
            self.assertEqual(proc.returncode, 1)
            self.assertIn("current HOME", proc.stderr)

    def test_refuses_existing_nonempty_directory_preserves_sentinel(self):
        with tempfile.TemporaryDirectory() as tmp:
            ws = pathlib.Path(tmp) / "ws"
            ws.mkdir()
            sentinel = ws / "sentinel.txt"
            sentinel.write_text("keep me")
            proc = run_fixture(ws, "stdout")
            self.assertEqual(proc.returncode, 1)
            self.assertIn("existing non-empty directory", proc.stderr)
            self.assertEqual(sentinel.read_text(), "keep me")

    def test_refuses_symlink_workspace_preserves_target(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            target = root / "target"
            target.mkdir()
            ws = root / "ws-link"
            ws.symlink_to(target, target_is_directory=True)
            proc = run_fixture(ws, "stdout")
            self.assertEqual(proc.returncode, 1)
            self.assertIn("symlink escape", proc.stderr)
            self.assertEqual(list(target.iterdir()), [])
            self.assertTrue(ws.is_symlink())

    def test_refuses_non_directory_path_preserves_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            ws = pathlib.Path(tmp) / "not-a-dir"
            ws.write_text("plain file")
            proc = run_fixture(ws, "stdout")
            self.assertEqual(proc.returncode, 1)
            self.assertIn("non-directory", proc.stderr)
            self.assertEqual(ws.read_text(), "plain file")


if __name__ == "__main__":
    unittest.main()
