#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
#
# tests/unit/test_nix_nrf_bootstrap.py — fake-boundary unit tests for the
# `nix-nrf bootstrap` command module (bin/nix-nrf-bootstrap).
#
# Exercises the command as a subprocess through public-style args and
# environment against a temporary fake `nrfutil` executable and state
# directory. No network, no real SDK, no real nrfutil state: the fake
# emulates the verified sdk-manager JSON interfaces (list/config show),
# toolchain env readiness, and records every install command.
#
# Run standalone from the repo:  python3 tests/unit/test_nix_nrf_bootstrap.py
# Wired as checks.bootstrap-tests in flake.nix (sandboxed Python stdlib);
# the derivation sets NIX_NRF_BOOTSTRAP_SCRIPT to the copied script.

import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest


def _resolve_bootstrap_script() -> str:
    # The sandboxed check derivation copies the test to /build root, where
    # the repo-relative fallback cannot be computed (parents[2] missing);
    # NIX_NRF_BOOTSTRAP_SCRIPT is set there.
    configured = os.environ.get("NIX_NRF_BOOTSTRAP_SCRIPT")
    if configured:
        return configured
    try:
        repo_root = pathlib.Path(__file__).resolve().parents[2]
    except IndexError:
        raise RuntimeError(
            "NIX_NRF_BOOTSTRAP_SCRIPT is not set and the repo root is unavailable"
        )
    return str(repo_root / "bin" / "nix-nrf-bootstrap")


BOOTSTRAP_SCRIPT = _resolve_bootstrap_script()

# Fake nrfutil: reads/writes a state directory pointed at by
# FAKE_NRFUTIL_DIR. Markers:
#   sdk_dir / sdk_ok / toolchain_ok   installed SDK dir and readiness flags
#   list_override / config_override   raw output to print (malformed-JSON tests)
#   fail_list / fail_config           make the read-only command exit nonzero
#   fail_install                      make install commands exit nonzero
#   noop_install                      install commands succeed without changing state
#   commands.log                      every install command line (assert no-mutation)
#   env_args.log                      every `toolchain env` selector invocation
#
# Written with a shebang pointing at the running interpreter's store path
# (sys.executable): /usr/bin/env is absent inside the Nix build sandbox, so
# `#!/usr/bin/env python3` would fail with ENOENT there.
FAKE_NRFUTIL = r"""import json
import os
import pathlib
import sys

state = pathlib.Path(os.environ["FAKE_NRFUTIL_DIR"])


def has(name):
    return (state / name).exists()


def log():
    with (state / "commands.log").open("a") as fh:
        fh.write(" ".join(sys.argv[1:]) + "\n")


def fail_if_marked():
    if has("fail_install"):
        print("fake nrfutil: forced install failure", file=sys.stderr)
        sys.exit(1)
    if has("noop_install"):
        sys.exit(0)


args = sys.argv[1:]
assert args and args[0] == "sdk-manager", args
args = args[1:]
cmd = args[0]

if cmd == "list":
    if has("fail_list"):
        print("fake nrfutil: forced list failure", file=sys.stderr)
        sys.exit(1)
    if has("list_override"):
        sys.stdout.write((state / "list_override").read_text())
        sys.exit(0)
    versions = []
    if has("sdk_ok"):
        sdk_dir = (state / "sdk_dir").read_text().strip()
        versions.append(
            {
                "dirNames": [sdk_dir],
                "sdkStatus": "installed",
                "toolchainStatus": "installed",
                "type": "nrf",
                "version": os.environ.get("NIX_NRF_NCS_VERSION", "v3.3.0"),
            }
        )
    print(json.dumps({"versions": versions}))
elif cmd == "config":
    # args: show --json --skip-overhead
    if has("fail_config"):
        print("fake nrfutil: forced config failure", file=sys.stderr)
        sys.exit(1)
    if has("config_override"):
        sys.stdout.write((state / "config_override").read_text())
    else:
        print(json.dumps({"default": {"install_dir": None}}))
elif cmd == "toolchain":
    sub = args[1]
    if sub == "env":
        # args[2:] = selector flags + --as-script sh
        with (state / "env_args.log").open("a") as fh:
            fh.write(" ".join(args[2:]) + "\n")
        if not has("toolchain_ok"):
            print(
                "fake nrfutil: toolchain env: selected toolchain not found",
                file=sys.stderr,
            )
            sys.exit(1)
        print("export FAKE_TOOLCHAIN_ENV=1")
    elif sub == "install":
        log()
        fail_if_marked()
        (state / "toolchain_ok").write_text("1")
    else:
        print(f"fake nrfutil: unexpected toolchain subcommand: {sub}", file=sys.stderr)
        sys.exit(99)
elif cmd == "sdk":
    sub = args[1]
    if sub == "install":
        log()
        fail_if_marked()
        (state / "sdk_ok").write_text("1")
    else:
        print(f"fake nrfutil: unexpected sdk subcommand: {sub}", file=sys.stderr)
        sys.exit(99)
elif cmd == "install":
    log()
    fail_if_marked()
    (state / "sdk_ok").write_text("1")
    (state / "toolchain_ok").write_text("1")
else:
    print(f"fake nrfutil: unexpected command: {cmd}", file=sys.stderr)
    sys.exit(99)
"""


class BootstrapTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)
        self.home = self.root / "home"
        self.sdk_dir = self.home / "ncs" / "v3.3.0"
        (self.sdk_dir / "zephyr").mkdir(parents=True)
        self.fake_dir = self.root / "fake"
        self.fake_dir.mkdir()
        self.fake = self.fake_dir / "nrfutil"
        # Direct-interpreter shebang (see FAKE_NRFUTIL docstring): works both
        # in the Nix build sandbox and on a normal host.
        self.fake.write_text(f"#!{sys.executable}\n{FAKE_NRFUTIL}")
        self.fake.chmod(0o755)
        self.write_state("sdk_dir", str(self.sdk_dir))
        self.env = os.environ.copy()
        self.env["HOME"] = str(self.home)
        self.env["NIX_NRF_NRFUTIL"] = str(self.fake)
        self.env["FAKE_NRFUTIL_DIR"] = str(self.fake_dir)
        self.env["NIX_NRF_NCS_VERSION"] = "v3.3.0"
        self.env.pop("NIX_NRF_BOOTSTRAP_YES", None)
        self.env.pop("NIX_NRF_TOOLCHAIN_BUNDLE_ID", None)
        self.env.pop("NRFUTIL_HOME", None)

    def tearDown(self):
        self.tmp.cleanup()

    def write_state(self, name, text=""):
        (self.fake_dir / name).write_text(text)

    def rm_state(self, name):
        (self.fake_dir / name).unlink(missing_ok=True)

    def run_bootstrap(self, *args, env_extra=None):
        env = dict(self.env)
        if env_extra:
            env.update(env_extra)
        return subprocess.run(
            [sys.executable, BOOTSTRAP_SCRIPT, *args],
            env=env,
            capture_output=True,
            text=True,
        )

    def commands(self):
        log = self.fake_dir / "commands.log"
        if not log.exists():
            return []
        return log.read_text().splitlines()

    def env_calls(self):
        log = self.fake_dir / "env_args.log"
        if not log.exists():
            return []
        return log.read_text().splitlines()

    # 1. Ready selection: exits 0, prints SDK path only when requested,
    #    performs no install.
    def test_ready_selection_no_install_no_output(self):
        self.write_state("sdk_ok")
        self.write_state("toolchain_ok")
        proc = self.run_bootstrap()
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout, "")
        self.assertEqual(self.commands(), [])

    def test_ready_selection_print_sdk_path(self):
        self.write_state("sdk_ok")
        self.write_state("toolchain_ok")
        proc = self.run_bootstrap("--print-sdk-path")
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout.strip(), str(self.sdk_dir))
        self.assertEqual(self.commands(), [])

    # 2. Missing default SDK/toolchain + --check: exits 1, no mutation.
    def test_check_missing_exits_1_no_mutation(self):
        proc = self.run_bootstrap("--check")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("missing", proc.stderr.lower())
        self.assertIn("no changes made", proc.stderr)
        self.assertEqual(self.commands(), [])

    # 3. Missing selection non-TTY without approval: exits 2, exact guidance,
    #    no install.
    def test_missing_non_tty_requires_approval(self):
        proc = self.run_bootstrap()
        self.assertEqual(proc.returncode, 2)
        self.assertIn("nix-nrf bootstrap --yes", proc.stderr)
        self.assertIn("NIX_NRF_BOOTSTRAP_YES=1", proc.stderr)
        self.assertEqual(self.commands(), [])

    # 4. --yes default selector: invokes only the combined install, rechecks,
    #    exits 0; toolchain env uses the --ncs-version selector.
    def test_yes_default_selector_installs_and_rechecks(self):
        proc = self.run_bootstrap("--yes", "--print-sdk-path")
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout.strip(), str(self.sdk_dir))
        self.assertEqual(self.commands(), ["sdk-manager install v3.3.0"])
        self.assertIn("--ncs-version v3.3.0 --as-script sh", self.env_calls())

    # 5. NIX_NRF_BOOTSTRAP_YES=1: same approval behavior.
    def test_env_yes_approves(self):
        proc = self.run_bootstrap(env_extra={"NIX_NRF_BOOTSTRAP_YES": "1"})
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(self.commands(), ["sdk-manager install v3.3.0"])

    # 6. Exact selector missing both: SDK-only then exact-toolchain commands;
    #    never the combined install; toolchain env uses the exact bundle.
    def test_exact_bundle_missing_both_sdk_then_toolchain(self):
        proc = self.run_bootstrap(
            "--yes",
            "--toolchain-bundle-id",
            "bundle-1",
        )
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(
            self.commands(),
            [
                "sdk-manager sdk install v3.3.0",
                "sdk-manager toolchain install --toolchain-bundle-id bundle-1",
            ],
        )
        self.assertIn("--toolchain-bundle-id bundle-1 --as-script sh", self.env_calls())
        self.assertNotIn("sdk-manager install v3.3.0", self.commands())

    # 7. Exact selector with only one component missing: only the missing
    #    action runs.
    def test_exact_bundle_only_toolchain_missing(self):
        self.write_state("sdk_ok")
        proc = self.run_bootstrap(
            "--yes",
            "--toolchain-bundle-id",
            "bundle-1",
        )
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(
            self.commands(),
            ["sdk-manager toolchain install --toolchain-bundle-id bundle-1"],
        )

    def test_exact_bundle_only_sdk_missing(self):
        self.write_state("toolchain_ok")
        proc = self.run_bootstrap(
            "--yes",
            "--toolchain-bundle-id",
            "bundle-1",
        )
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(self.commands(), ["sdk-manager sdk install v3.3.0"])

    # 8. Malformed list/config JSON or failed state command: exits 1, never
    #    installs.
    def test_malformed_list_json_exits_1(self):
        self.write_state("list_override", "not json {")
        proc = self.run_bootstrap("--yes")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("nix-nrf bootstrap: error", proc.stderr)
        self.assertEqual(self.commands(), [])

    def test_failed_list_command_exits_1(self):
        self.write_state("fail_list")
        proc = self.run_bootstrap("--yes")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("nix-nrf bootstrap: error", proc.stderr)
        self.assertEqual(self.commands(), [])

    def test_malformed_config_json_exits_1(self):
        self.write_state("config_override", "not json {")
        proc = self.run_bootstrap("--yes")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("nix-nrf bootstrap: error", proc.stderr)
        self.assertEqual(self.commands(), [])

    def test_failed_config_command_exits_1(self):
        self.write_state("fail_config")
        proc = self.run_bootstrap("--yes")
        self.assertEqual(proc.returncode, 1)
        self.assertEqual(self.commands(), [])

    # 9. Failed install or incomplete post-install state: exits 1.
    def test_failed_install_exits_1(self):
        self.write_state("fail_install")
        proc = self.run_bootstrap("--yes")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("nix-nrf bootstrap: error", proc.stderr)
        self.assertEqual(self.commands(), ["sdk-manager install v3.3.0"])

    def test_incomplete_post_install_state_exits_1(self):
        self.write_state("noop_install")
        proc = self.run_bootstrap("--yes")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("install incomplete", proc.stderr)
        self.assertEqual(self.commands(), ["sdk-manager install v3.3.0"])

    # stdout contract regressions: the mutating path must never emit the SDK
    # path before install, so `--print-sdk-path` yields exactly one line on
    # success and an empty stdout on failed/incomplete mutation.
    def test_check_prints_sdk_path_once_when_toolchain_missing(self):
        # Installed SDK + missing toolchain + --check --print-sdk-path: the
        # shell hook relies on this single emission (exit stays 1).
        self.write_state("sdk_ok")
        proc = self.run_bootstrap("--check", "--print-sdk-path")
        self.assertEqual(proc.returncode, 1)
        self.assertEqual(proc.stdout, str(self.sdk_dir) + "\n")
        self.assertEqual(self.commands(), [])

    def test_sdk_ready_toolchain_missing_yes_exact_one_line(self):
        # Installed SDK + missing toolchain + --yes --print-sdk-path (exact
        # bundle): exactly one output line, one toolchain install, exit 0.
        # Regresses the pre-fix duplicate-line stdout (path emitted before
        # --check handling AND again after install).
        self.write_state("sdk_ok")
        proc = self.run_bootstrap(
            "--yes",
            "--print-sdk-path",
            "--toolchain-bundle-id",
            "bundle-1",
        )
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout, str(self.sdk_dir) + "\n")
        self.assertEqual(
            self.commands(),
            ["sdk-manager toolchain install --toolchain-bundle-id bundle-1"],
        )

    def test_incomplete_mutation_keeps_stdout_empty(self):
        # Pre-existing SDK + toolchain install succeeds without changing state:
        # post-install recheck fails, exit 1, no stale path on stdout.
        self.write_state("sdk_ok")
        self.write_state("noop_install")
        proc = self.run_bootstrap(
            "--yes",
            "--print-sdk-path",
            "--toolchain-bundle-id",
            "bundle-1",
        )
        self.assertEqual(proc.returncode, 1)
        self.assertEqual(proc.stdout, "")
        self.assertEqual(
            self.commands(),
            ["sdk-manager toolchain install --toolchain-bundle-id bundle-1"],
        )

    def test_failed_mutation_keeps_stdout_empty(self):
        # Pre-existing SDK + failing toolchain install: exit 1, stdout empty.
        self.write_state("sdk_ok")
        self.write_state("fail_install")
        proc = self.run_bootstrap(
            "--yes",
            "--print-sdk-path",
            "--toolchain-bundle-id",
            "bundle-1",
        )
        self.assertEqual(proc.returncode, 1)
        self.assertEqual(proc.stdout, "")
        self.assertEqual(
            self.commands(),
            ["sdk-manager toolchain install --toolchain-bundle-id bundle-1"],
        )

    # 10. Missing configured/default NCS version: argparse-style exit 2.
    def test_missing_ncs_version_exits_2(self):
        env = dict(self.env)
        env.pop("NIX_NRF_NCS_VERSION", None)
        proc = subprocess.run(
            [sys.executable, BOOTSTRAP_SCRIPT],
            env=env,
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 2)
        self.assertIn("nix-nrf bootstrap: error", proc.stderr)
        self.assertIn("--ncs-version", proc.stderr)

    # Extra public-surface behavior:
    def test_help_exits_0(self):
        proc = self.run_bootstrap("--help")
        self.assertEqual(proc.returncode, 0)
        self.assertIn("nix-nrf bootstrap", proc.stdout)

    def test_cli_ncs_version_overrides_configured_default(self):
        # CLI value wins over NIX_NRF_NCS_VERSION: the toolchain env selector
        # must carry the CLI value even though the fake's list only shows the
        # configured default.
        proc = self.run_bootstrap(
            "--ncs-version",
            "v3.2.0",
        )
        self.assertEqual(proc.returncode, 2)  # non-TTY approval required
        self.assertIn("--ncs-version v3.2.0 --as-script sh", self.env_calls())
        self.assertEqual(self.commands(), [])

    def test_quiet_suppresses_status_but_not_errors(self):
        self.write_state("fail_list")
        proc = self.run_bootstrap("--check", "--quiet")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("nix-nrf bootstrap: error", proc.stderr)


if __name__ == "__main__":
    unittest.main()
