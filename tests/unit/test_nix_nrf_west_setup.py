#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
#
# tests/unit/test_nix_nrf_west_setup.py — fake-boundary unit tests for the
# west backend setup helper (bin/nix-nrf-west-setup).
#
# Exercises the helper as a subprocess through public-style args and
# environment against temporary fake python/venv/west/pip boundaries. No
# network, no real workspace, no real venv: the fake "Nix python" creates a
# fake .venv whose python/pip/west record every invocation, the fake west
# materializes the workspace files west init would create, and markers force
# failures. Two logs separate read-only probes from mutations so "no
# mutation" assertions stay exact:
#   probes.log     — venv import checks and west --version (read-only)
#   mutations.log  — venv creation, pip installs, west init/update
#
# Run standalone from the repo:  python3 tests/unit/test_nix_nrf_west_setup.py
# Wired as checks.west-setup-tests in flake.nix (sandboxed Python stdlib);
# the derivation sets NIX_NRF_WEST_SETUP_SCRIPT to the copied script.

import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

REQUIREMENTS = "\n".join(
    [
        "zephyr/scripts/requirements.txt",
        "nrf/scripts/requirements.txt",
        "bootloader/mcuboot/scripts/requirements.txt",
    ]
)


def _resolve_setup_script() -> str:
    configured = os.environ.get("NIX_NRF_WEST_SETUP_SCRIPT")
    if configured:
        return configured
    try:
        repo_root = pathlib.Path(__file__).resolve().parents[2]
    except IndexError:
        raise RuntimeError(
            "NIX_NRF_WEST_SETUP_SCRIPT is not set and the repo root is unavailable"
        )
    return str(repo_root / "bin" / "nix-nrf-west-setup")


SETUP_SCRIPT = _resolve_setup_script()

# Fake "Nix python" (NIX_NRF_WEST_PYTHON): when invoked `-m venv <dir>`,
# materializes <dir>/bin/{python,pip,west} recorder scripts (direct
# interpreter shebang, since /usr/bin/env is absent in the Nix build sandbox).
FAKE_CREATOR = r"""import os
import pathlib
import sys

args = sys.argv[1:]
assert args[:2] == ["-m", "venv"], args
bin_dir = pathlib.Path(args[2]) / "bin"
bin_dir.mkdir(parents=True, exist_ok=True)

RECORDER = r'''import os
import pathlib
import sys

def log(name):
    with open(os.environ["FAKE_WEST_SETUP_LOG_DIR"] + "/" + name, "a") as fh:
        fh.write(pathlib.Path(sys.argv[0]).name + " " + " ".join(sys.argv[1:]) + "\n")

args = sys.argv[1:]
%(body)s
'''

PY = RECORDER % {"body": r'''
if args[:2] == ["-m", "pip"]:
    log("mutations.log")
    if os.path.exists(os.environ["FAKE_WEST_SETUP_LOG_DIR"] + "/fail_pip"):
        print("fake pip: forced failure", file=sys.stderr)
        sys.exit(1)
    sys.exit(0)
if args == ["-c", "import west, yaml, elftools, zcbor, nrfregtool"]:
    log("probes.log")
    sys.exit(0)
log("probes.log")
sys.exit(0)
'''}
PIP = RECORDER % {"body": r'''
log("mutations.log")
if os.path.exists(os.environ["FAKE_WEST_SETUP_LOG_DIR"] + "/fail_pip"):
    print("fake pip: forced failure", file=sys.stderr)
    sys.exit(1)
sys.exit(0)
'''}
WEST = RECORDER % {"body": r'''
if args == ["--version"]:
    log("probes.log")
    version_file = os.environ["FAKE_WEST_SETUP_LOG_DIR"] + "/west_version"
    if os.path.exists(version_file):
        sys.stdout.write(open(version_file).read())
    else:
        sys.stdout.write("West version: v1.4.0\n")
    sys.exit(0)
if args[0] == "init":
    log("mutations.log")
    if os.path.exists(os.environ["FAKE_WEST_SETUP_LOG_DIR"] + "/noop_init"):
        sys.exit(0)
    ws = pathlib.Path(args[-1])
    (ws / ".west").mkdir(parents=True, exist_ok=True)
    (ws / ".west" / "config").write_text("[manifest]\npath = nrf\nfile = west.yml\n")
    (ws / "nrf").mkdir(parents=True, exist_ok=True)
    (ws / "nrf" / "west.yml").write_text("manifest:\n")
    (ws / "zephyr" / "scripts").mkdir(parents=True, exist_ok=True)
    (ws / "zephyr" / "zephyr-env.sh").write_text("#!/bin/sh\n")
    (ws / "zephyr" / "scripts" / "requirements-base.txt").write_text("west>=0.14.0\n")
    (ws / "zephyr" / "scripts" / "requirements.txt").write_text(
        "-r requirements-base.txt\n"
    )
    (ws / "nrf" / "scripts").mkdir(parents=True, exist_ok=True)
    (ws / "nrf" / "scripts" / "requirements-base.txt").write_text("west>=1.4.0\n")
    (ws / "nrf" / "scripts" / "requirements.txt").write_text(
        "-r requirements-base.txt\n"
    )
    (ws / "bootloader" / "mcuboot" / "scripts").mkdir(parents=True, exist_ok=True)
    (ws / "bootloader" / "mcuboot" / "scripts" / "requirements.txt").write_text(
        "pyelftools>=0.29\n"
    )
    sys.exit(0)
if args[0] == "update":
    log("mutations.log")
    if os.path.exists(os.environ["FAKE_WEST_SETUP_LOG_DIR"] + "/fail_update"):
        print("fake west: forced update failure", file=sys.stderr)
        sys.exit(1)
    sys.exit(0)
log("mutations.log")
sys.exit(0)
'''}

with open(bin_dir / "python", "w") as fh:
    fh.write("#!" + sys.executable + "\n" + PY)
with open(bin_dir / "pip", "w") as fh:
    fh.write("#!" + sys.executable + "\n" + PIP)
with open(bin_dir / "west", "w") as fh:
    fh.write("#!" + sys.executable + "\n" + WEST)
for name in ("python", "pip", "west"):
    (bin_dir / name).chmod(0o755)
with open(os.environ["FAKE_WEST_SETUP_LOG_DIR"] + "/mutations.log", "a") as fh:
    fh.write(
        pathlib.Path(sys.argv[0]).name + " " + " ".join(sys.argv[1:]) + "\n"
    )
"""


class WestSetupTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.fake_dir = self.root / "fake"
        self.fake_dir.mkdir()
        self.creator = self.fake_dir / "nix-python"
        self.creator.write_text(f"#!{sys.executable}\n{FAKE_CREATOR}")
        self.creator.chmod(0o755)
        self.env = os.environ.copy()
        self.env["HOME"] = str(self.home)
        self.env["NIX_NRF_WEST_PYTHON"] = str(self.creator)
        self.env["NIX_NRF_WEST_NCS_VERSION"] = "v3.3.0"
        self.env["NIX_NRF_WEST_TESTED_WEST_VERSION"] = "1.4.0"
        self.env["NIX_NRF_WEST_REQUIREMENTS"] = REQUIREMENTS
        self.env["NIX_NRF_WEST_PIP_CONSTRAINTS"] = "cbor2==5.9.0"
        self.env["FAKE_WEST_SETUP_LOG_DIR"] = str(self.fake_dir)
        self.env.pop("NIX_NRF_WEST_SETUP_YES", None)
        self.env.pop("NIX_NRF_WEST_WORKSPACE", None)

    def tearDown(self):
        self.tmp.cleanup()

    @property
    def workspace(self):
        return self.home / "ncs" / "v3.3.0"

    def write_marker(self, name, text=""):
        (self.fake_dir / name).write_text(text)

    def rm_marker(self, name):
        (self.fake_dir / name).unlink(missing_ok=True)

    def run_setup(self, *args, env_extra=None, cwd=None):
        env = dict(self.env)
        if env_extra:
            env.update(env_extra)
        return subprocess.run(
            [sys.executable, SETUP_SCRIPT, *args],
            env=env,
            cwd=cwd,
            capture_output=True,
            text=True,
        )

    def set_west_version(self, version):
        """Fake venv west --version output; default is v1.4.0."""
        self.write_marker("west_version", f"West version: v{version}\n")

    def set_west_constraint(self, constraint):
        """Overwrite both requirement base files so the only west constraint
        is the given one (e.g. ">1.4.0"), matching the setup helper's
        `-r` include resolution."""
        (self.workspace / "zephyr" / "scripts" / "requirements-base.txt").write_text(
            f"west{constraint}\n"
        )
        (self.workspace / "nrf" / "scripts" / "requirements-base.txt").write_text(
            f"west{constraint}\n"
        )

    def log(self, name):
        log_path = self.fake_dir / name
        if not log_path.exists():
            return []
        return log_path.read_text().splitlines()

    def mutations(self):
        return self.log("mutations.log")

    def probes(self):
        return self.log("probes.log")

    def make_ready_workspace(self):
        """Materialize a fully ready workspace without running setup:
        the fake venv via the fake creator, plus the workspace files."""
        proc = subprocess.run(
            [str(self.creator), "-m", "venv", str(self.workspace / ".venv")],
            env=self.env,
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        (self.workspace / ".west").mkdir(parents=True)
        (self.workspace / ".west" / "config").write_text(
            "[manifest]\npath = nrf\nfile = west.yml\n"
        )
        (self.workspace / "nrf").mkdir(parents=True)
        (self.workspace / "nrf" / "west.yml").write_text("manifest:\n")
        (self.workspace / "zephyr" / "scripts").mkdir(parents=True)
        (self.workspace / "zephyr" / "zephyr-env.sh").write_text("#!/bin/sh\n")
        (self.workspace / "zephyr" / "scripts" / "requirements-base.txt").write_text(
            "west>=0.14.0\n"
        )
        (self.workspace / "zephyr" / "scripts" / "requirements.txt").write_text(
            "-r requirements-base.txt\n"
        )
        (self.workspace / "nrf" / "scripts").mkdir(parents=True)
        (self.workspace / "nrf" / "scripts" / "requirements-base.txt").write_text(
            "west>=1.4.0\n"
        )
        (self.workspace / "nrf" / "scripts" / "requirements.txt").write_text(
            "-r requirements-base.txt\n"
        )
        (self.workspace / "bootloader" / "mcuboot" / "scripts").mkdir(parents=True)
        (
            self.workspace / "bootloader" / "mcuboot" / "scripts" / "requirements.txt"
        ).write_text("pyelftools>=0.29\n")
        # The harness venv creation above is not a setup-helper mutation:
        # reset both logs so the run under test starts clean.
        for name in ("mutations.log", "probes.log"):
            (self.fake_dir / name).write_text("")

    # 1. Missing workspace --check: exit 1, no mutation, no probes.
    def test_check_missing_workspace_exits_1_no_mutation(self):
        proc = self.run_setup("--check")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("not ready", proc.stderr)
        self.assertIn("no changes made", proc.stderr)
        self.assertEqual(self.mutations(), [])
        self.assertEqual(self.probes(), [])

    # 2. Ready workspace --check: exit 0; --print-workspace prints exactly
    #    one path line; probes run (read-only), mutations stay empty.
    def test_check_ready_exits_0_no_stdout(self):
        self.make_ready_workspace()
        proc = self.run_setup("--check")
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout, "")
        self.assertEqual(self.mutations(), [])

    def test_check_ready_print_workspace_one_line(self):
        self.make_ready_workspace()
        proc = self.run_setup("--check", "--print-workspace")
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout, str(self.workspace) + "\n")
        self.assertEqual(self.mutations(), [])

    # 3. Noninteractive approval requirement: no --yes, no TTY -> exit 2
    #    with the exact re-run guidance; nothing runs.
    def test_missing_non_tty_requires_approval(self):
        proc = self.run_setup()
        self.assertEqual(proc.returncode, 2)
        self.assertIn("nix-nrf-west-setup --yes", proc.stderr)
        self.assertIn("NIX_NRF_WEST_SETUP_YES=1", proc.stderr)
        self.assertEqual(self.mutations(), [])

    def test_env_yes_approves(self):
        proc = self.run_setup(env_extra={"NIX_NRF_WEST_SETUP_YES": "1"})
        self.assertEqual(proc.returncode, 0)
        self.assertTrue(any("west init" in line for line in self.mutations()))

    # 4. Initial command order and exact argument arrays.
    def test_initial_command_order_and_exact_argv(self):
        proc = self.run_setup("--yes")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(
            self.mutations(),
            [
                "nix-python -m venv .venv",
                f"python -m pip install -c {self.workspace}/.venv/nix-nrf-pip-constraints.txt west==1.4.0",
                f"west init -m https://github.com/nrfconnect/sdk-nrf --mr v3.3.0 {self.workspace}",
                "west update",
                f"python -m pip install -c {self.workspace}/.venv/nix-nrf-pip-constraints.txt -r {self.workspace}/zephyr/scripts/requirements.txt",
                f"python -m pip install -c {self.workspace}/.venv/nix-nrf-pip-constraints.txt -r {self.workspace}/nrf/scripts/requirements.txt",
                f"python -m pip install -c {self.workspace}/.venv/nix-nrf-pip-constraints.txt -r {self.workspace}/bootloader/mcuboot/scripts/requirements.txt",
            ],
        )
        # Re-readiness after setup runs the read-only probes.
        self.assertNotEqual(self.probes(), [])

    # 5. Requirements installed in metadata order.
    def test_requirements_installed_in_metadata_order(self):
        proc = self.run_setup("--yes")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        pip_requirements = [
            line
            for line in self.mutations()
            if " -r " in line and line.startswith("python -m pip install")
        ]
        self.assertEqual(
            pip_requirements,
            [
                f"python -m pip install -c {self.workspace}/.venv/nix-nrf-pip-constraints.txt -r {self.workspace}/{req}"
                for req in REQUIREMENTS.splitlines()
            ],
        )

    # 6. Re-run never calls west init again; it refreshes update +
    #    requirements for the current manifest (documented mutation) and
    #    does not re-create the venv or re-pin west.
    def test_rerun_does_not_call_west_init_again(self):
        proc = self.run_setup("--yes")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertTrue(any("west init" in line for line in self.mutations()))
        first_mutations = list(self.mutations())

        proc = self.run_setup("--yes")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        rerun = self.mutations()[len(first_mutations) :]
        self.assertFalse(any("west init" in line for line in rerun))
        self.assertFalse(any("nix-python" in line for line in rerun))
        self.assertFalse(any("python -m pip install west==" in line for line in rerun))
        self.assertTrue(any("west update" in line for line in rerun))
        self.assertEqual(
            [
                line
                for line in rerun
                if " -r " in line and line.startswith("python -m pip install")
            ],
            [
                f"python -m pip install -c {self.workspace}/.venv/nix-nrf-pip-constraints.txt -r {self.workspace}/{req}"
                for req in REQUIREMENTS.splitlines()
            ],
        )

    # 6b. Release-specific pip constraints are written into the venv and
    # applied via `-c` on every venv pip invocation.
    def test_pip_constraints_written_and_applied(self):
        proc = self.run_setup("--yes")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        constraints = self.workspace / ".venv" / "nix-nrf-pip-constraints.txt"
        self.assertTrue(constraints.is_file())
        self.assertEqual(constraints.read_text(), "cbor2==5.9.0\n")
        for line in self.mutations():
            if "python -m pip install" in line:
                self.assertIn(f"-c {constraints}", line)

    def test_no_pip_constraints_when_unset(self):
        env = dict(self.env)
        env.pop("NIX_NRF_WEST_PIP_CONSTRAINTS", None)
        proc = subprocess.run(
            [sys.executable, SETUP_SCRIPT, "--yes"],
            env=env,
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("python -m pip install west==1.4.0", self.mutations())
        self.assertFalse(
            (self.workspace / ".venv" / "nix-nrf-pip-constraints.txt").exists()
        )
        for line in self.mutations():
            if "python -m pip install" in line:
                self.assertNotIn("-c ", line)

    # 7. Incompatible existing workspace rejected without deletion or
    #    mutation.
    def test_incompatible_existing_workspace_rejected(self):
        (self.workspace / ".west").mkdir(parents=True)
        (self.workspace / ".west" / "config").write_text(
            "[manifest]\npath = nrf\nfile = west.yml\n"
        )
        before = sorted(
            str(p.relative_to(self.workspace)) for p in self.workspace.rglob("*")
        )
        proc = self.run_setup("--yes")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("incompatible", proc.stderr)
        self.assertIn("refusing to modify", proc.stderr)
        after = sorted(
            str(p.relative_to(self.workspace)) for p in self.workspace.rglob("*")
        )
        self.assertEqual(after, before)
        self.assertFalse((self.workspace / ".venv").exists())
        self.assertEqual(self.mutations(), [])

    def test_incompatible_venv_rejected(self):
        (self.workspace / ".venv").mkdir(parents=True)
        proc = self.run_setup("--yes")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("incompatible", proc.stderr)
        self.assertEqual(self.mutations(), [])

    # 8. Failed west update / pip / incomplete post-setup state propagate.
    def test_failed_west_update_propagates(self):
        self.write_marker("fail_update")
        proc = self.run_setup("--yes")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("nix-nrf-west-setup: error", proc.stderr)
        self.assertIn("west update failed", proc.stderr)
        self.assertTrue(any("west update" in line for line in self.mutations()))

    def test_failed_pip_propagates(self):
        self.write_marker("fail_pip")
        proc = self.run_setup("--yes")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("nix-nrf-west-setup: error", proc.stderr)
        self.assertIn("pip install west failed", proc.stderr)

    def test_incomplete_post_setup_state_exits_1(self):
        # west init succeeds without materializing the workspace: the
        # re-readiness check fails with "setup incomplete".
        self.write_marker("noop_init")
        proc = self.run_setup("--yes")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("setup incomplete", proc.stderr)
        self.assertTrue(any("west init" in line for line in self.mutations()))

    # 9. --check performs no mutation/network commands.
    def test_check_no_mutation_commands_ready(self):
        self.make_ready_workspace()
        proc = self.run_setup("--check")
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(self.mutations(), [])
        self.assertNotEqual(self.probes(), [])  # read-only probes only

    def test_check_no_mutation_commands_missing(self):
        proc = self.run_setup("--check")
        self.assertEqual(proc.returncode, 1)
        self.assertEqual(self.mutations(), [])
        self.assertEqual(self.probes(), [])

    # 10. Default workspace resolves from isolated HOME and the version.
    def test_default_workspace_uses_isolated_home_and_version(self):
        self.make_ready_workspace()
        proc = self.run_setup("--check", "--print-workspace")
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout, str(self.home / "ncs" / "v3.3.0") + "\n")

    def test_cli_workspace_overrides_default(self):
        alt = self.home / "elsewhere"
        (alt / "nrf").mkdir(parents=True)
        proc = self.run_setup("--check", "--workspace", str(alt))
        self.assertEqual(proc.returncode, 1)
        self.assertIn(str(alt), proc.stderr)

    # 10b. A relative --workspace is normalized to an absolute path BEFORE
    # any subprocess runs (subprocesses use cwd=workspace, so a relative path
    # would otherwise be re-interpreted from inside the workspace). west init
    # must receive the absolute intended path and nothing may be nested.
    def test_relative_workspace_normalized_to_absolute(self):
        rel = "rel/ws"
        proc = self.run_setup("--yes", "--workspace", rel, cwd=str(self.root))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        expected = os.path.abspath(os.path.join(str(self.root), rel))
        self.assertEqual(
            proc.stdout,
            "",  # no --print-workspace requested
        )
        self.assertIn(
            f"west init -m https://github.com/nrfconnect/sdk-nrf --mr v3.3.0 {expected}",
            self.mutations(),
        )
        # venv landed at the absolute path, and nothing nested below it.
        self.assertTrue((pathlib.Path(expected) / ".venv" / "bin" / "west").is_file())
        self.assertFalse((pathlib.Path(expected) / rel).exists())

    def test_relative_workspace_print_workspace_is_absolute(self):
        proc = self.run_setup(
            "--yes", "--workspace", "ws", "--print-workspace", cwd=str(self.root)
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(
            proc.stdout, os.path.abspath(os.path.join(str(self.root), "ws")) + "\n"
        )

    def test_tilde_workspace_expanded(self):
        proc = self.run_setup("--yes", "--workspace", "~/tilde-ws", cwd=str(self.root))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        expected = str(self.home / "tilde-ws")
        self.assertIn(
            f"west init -m https://github.com/nrfconnect/sdk-nrf --mr v3.3.0 {expected}",
            self.mutations(),
        )

    # West version satisfaction: workspace requirement west>=1.4.0 (via -r
    # includes) vs the venv west's --version.
    def test_ready_requires_west_version_satisfying_requirements(self):
        self.make_ready_workspace()
        self.write_marker("west_version", "West version: v1.4.0\n")
        proc = self.run_setup("--check")
        self.assertEqual(proc.returncode, 0)

    def test_too_old_west_version_not_ready(self):
        self.make_ready_workspace()
        self.write_marker("west_version", "West version: v1.3.0\n")
        proc = self.run_setup("--check")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("west version", proc.stderr)

    # Every constraint operator the parser accepts must be compared,
    # including strict boundaries. The fake west version is controlled via
    # set_west_version and the single active constraint via
    # set_west_constraint (both requirement base files are overwritten).
    def test_constraint_eq(self):
        self.make_ready_workspace()
        self.set_west_constraint("==1.4.0")
        self.set_west_version("1.4.0")
        self.assertEqual(self.run_setup("--check").returncode, 0)
        self.set_west_version("1.4.1")
        self.assertEqual(self.run_setup("--check").returncode, 1)

    def test_constraint_ge(self):
        self.make_ready_workspace()
        self.set_west_constraint(">=1.4.0")
        self.set_west_version("1.4.0")
        self.assertEqual(self.run_setup("--check").returncode, 0)
        self.set_west_version("1.3.9")
        self.assertEqual(self.run_setup("--check").returncode, 1)

    def test_constraint_gt_strict_boundary(self):
        self.make_ready_workspace()
        self.set_west_constraint(">1.4.0")
        self.set_west_version("1.4.1")
        self.assertEqual(self.run_setup("--check").returncode, 0)
        # Strict: exactly the boundary version must NOT satisfy.
        self.set_west_version("1.4.0")
        self.assertEqual(self.run_setup("--check").returncode, 1)

    def test_constraint_le(self):
        self.make_ready_workspace()
        self.set_west_constraint("<=1.4.0")
        self.set_west_version("1.4.0")
        self.assertEqual(self.run_setup("--check").returncode, 0)
        self.set_west_version("1.4.1")
        self.assertEqual(self.run_setup("--check").returncode, 1)

    def test_constraint_lt_strict_boundary(self):
        self.make_ready_workspace()
        self.set_west_constraint("<1.4.0")
        self.set_west_version("1.3.9")
        self.assertEqual(self.run_setup("--check").returncode, 0)
        # Strict: exactly the boundary version must NOT satisfy.
        self.set_west_version("1.4.0")
        self.assertEqual(self.run_setup("--check").returncode, 1)

    def test_constraint_mixed_ranges_all_must_hold(self):
        self.make_ready_workspace()
        (self.workspace / "zephyr" / "scripts" / "requirements-base.txt").write_text(
            "west>=1.4.0\n"
        )
        (self.workspace / "nrf" / "scripts" / "requirements-base.txt").write_text(
            "west<2.0.0\n"
        )
        self.set_west_version("1.9.0")
        self.assertEqual(self.run_setup("--check").returncode, 0)
        # Violates the upper bound; both constraints must hold.
        self.set_west_version("2.0.0")
        self.assertEqual(self.run_setup("--check").returncode, 1)

    def test_missing_requirement_file_not_ready(self):
        self.make_ready_workspace()
        (
            self.workspace / "bootloader" / "mcuboot" / "scripts" / "requirements.txt"
        ).unlink()
        proc = self.run_setup("--check")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("requirements file", proc.stderr)

    def test_help_exits_0(self):
        proc = self.run_setup("--help")
        self.assertEqual(proc.returncode, 0)
        self.assertIn("nix-nrf-west-setup", proc.stdout)


if __name__ == "__main__":
    unittest.main()
