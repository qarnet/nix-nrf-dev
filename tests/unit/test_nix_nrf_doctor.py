#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
#
# tests/unit/test_nix_nrf_doctor.py — fake-boundary unit tests for the
# `nix-nrf doctor` command module (bin/nix-nrf-doctor).
#
# Exercises the command as a subprocess through public-style args and
# environment against temporary fake sysfs/dev roots and a fake bootstrap
# command. No real /sys, no /dev, no SDK, no network: candidate discovery,
# node mapping, access classification, SDK check, remediation, and the JSON
# contract are all driven by fixtures. Node access is injected through
# NIX_NRF_DOCTOR_ACCESS_JSON (test-only override) instead of assuming chmod
# semantics in every sandbox; production code always uses os.access.
#
# Run standalone from the repo:  python3 tests/unit/test_nix_nrf_doctor.py
# Wired as checks.doctor-tests in flake.nix (sandboxed Python stdlib); the
# derivation sets NIX_NRF_DOCTOR_SCRIPT to the copied script.

import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest


def _resolve_doctor_script() -> str:
    # The sandboxed check derivation copies the test to /build root, where
    # the repo-relative fallback cannot be computed (parents[2] missing);
    # NIX_NRF_DOCTOR_SCRIPT is set there.
    configured = os.environ.get("NIX_NRF_DOCTOR_SCRIPT")
    if configured:
        return configured
    try:
        repo_root = pathlib.Path(__file__).resolve().parents[2]
    except IndexError:
        raise RuntimeError(
            "NIX_NRF_DOCTOR_SCRIPT is not set and the repo root is unavailable"
        )
    return str(repo_root / "bin" / "nix-nrf-doctor")


DOCTOR_SCRIPT = _resolve_doctor_script()

# Fake bootstrap: records every invocation in argv.log, then exits with the
# code in boot_exit (default 0) and prints boot_stdout (default empty).
# The real `nix-nrf bootstrap --check --quiet --print-sdk-path` contract:
# exit 0 + exactly one SDK path line on success, nonzero when missing.
FAKE_BOOTSTRAP = r"""import os
import pathlib
import sys

state = pathlib.Path(os.environ["FAKE_BOOTSTRAP_DIR"])
with (state / "argv.log").open("a") as fh:
    fh.write(" ".join(sys.argv[1:]) + "\n")

exit_code = 0
if (state / "boot_exit").exists():
    exit_code = int((state / "boot_exit").read_text().strip())

if (state / "boot_stdout").exists():
    sys.stdout.write((state / "boot_stdout").read_text())
sys.exit(exit_code)
"""


class DoctorTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)
        self.sysfs = self.root / "sysfs"
        self.dev = self.root / "dev"
        self.sysfs.mkdir()
        self.fake_dir = self.root / "fake-bootstrap"
        self.fake_dir.mkdir()
        self.fake_bootstrap = self.fake_dir / "bootstrap"
        self.fake_bootstrap.write_text(f"#!{sys.executable}\n{FAKE_BOOTSTRAP}")
        self.fake_bootstrap.chmod(0o755)
        self.rules_pkg = self.root / "udev-rules"
        rule = self.rules_pkg / "lib" / "udev" / "rules.d" / "60-openocd.rules"
        rule.parent.mkdir(parents=True)
        rule.write_text(
            "# SPDX-License-Identifier: GPL-2.0-or-later\n"
            'ATTRS{product}=="*CMSIS-DAP*", MODE="660", GROUP="plugdev", TAG+="uaccess"\n'
        )
        self.sdk_dir = self.root / "ncs" / "v3.3.0"
        (self.sdk_dir / "zephyr").mkdir(parents=True)
        self.env = os.environ.copy()
        self.env["NIX_NRF_DOCTOR_BOOTSTRAP"] = str(self.fake_bootstrap)
        self.env["FAKE_BOOTSTRAP_DIR"] = str(self.fake_dir)
        self.env["NIX_NRF_DOCTOR_UDEV_RULES"] = str(self.rules_pkg)
        self.env["NIX_NRF_DOCTOR_SYSFS_ROOT"] = str(self.sysfs)
        self.env["NIX_NRF_DOCTOR_DEV_ROOT"] = str(self.dev)
        self.env["NIX_NRF_DOCTOR_NCS_VERSION"] = "v3.3.0"
        self.env.pop("NIX_NRF_DOCTOR_SKIP_SDK", None)
        self.env.pop("NIX_NRF_DOCTOR_ACCESS_JSON", None)

    def tearDown(self):
        self.tmp.cleanup()

    # ── fixture helpers ────────────────────────────────────────────────────

    def make_device(
        self,
        name,
        *,
        product=None,
        manufacturer=None,
        serial=None,
        vid=None,
        pid=None,
        busnum=None,
        devnum=None,
        hidraw=(),
    ):
        """Create one fake USB sysfs device dir with optional attributes and
        descendant hidraw dirs (each hidraw is an absolute path to the sysfs
        hidrawN dir, mirroring <device>/*:*/.../hidraw/hidraw*)."""
        dev = self.sysfs / name
        dev.mkdir(parents=True)
        for key, value in (
            ("product", product),
            ("manufacturer", manufacturer),
            ("serial", serial),
            ("idVendor", vid),
            ("idProduct", pid),
            ("busnum", busnum),
            ("devnum", devnum),
        ):
            if value is not None:
                (dev / key).write_text(str(value))
        for hidraw_dir in hidraw:
            hidraw_dir.mkdir(parents=True)
        return dev

    def make_dev_node(self, rel):
        """Create a fake /dev node (regular file) below the fake dev root."""
        node = self.dev / rel
        node.parent.mkdir(parents=True, exist_ok=True)
        node.write_text("x")
        return node

    def access_env(self, mapping):
        """Test-only access override: path -> {readable, writable}."""
        return {"NIX_NRF_DOCTOR_ACCESS_JSON": json.dumps(mapping)}

    def add_xiao(self, accessible=True):
        """Seeed XIAO nRF54 CMSIS-DAP with one hidraw interface."""
        self.make_device(
            "1-9",
            product="Seeed Studio XIAO nrf54 CMSIS-DAP",
            manufacturer="Seeed Studio",
            serial="8EE9B3FF",
            vid="2886",
            pid="0066",
            busnum=1,
            devnum=17,
            hidraw=[
                self.sysfs
                / "1-9"
                / "1-9:1.0"
                / "0003:2886:0066.000F"
                / "hidraw"
                / "hidraw0"
            ],
        )
        hidraw_node = self.make_dev_node("hidraw0")
        usb_node = self.make_dev_node("bus/usb/001/017")
        override = {
            str(hidraw_node): {"readable": accessible, "writable": accessible},
            str(usb_node): {"readable": True, "writable": True},
        }
        return override

    def add_pico(self, accessible=True):
        """Debugprobe on Pico (CMSIS-DAP, bulk transport — no hidraw)."""
        self.make_device(
            "5-2.4",
            product="Debugprobe on Pico (CMSIS-DAP)",
            manufacturer="Raspberry Pi",
            serial="E6635C08CB1F502B",
            vid="2e8a",
            pid="000c",
            busnum=5,
            devnum=33,
        )
        usb_node = self.make_dev_node("bus/usb/005/033")
        return {str(usb_node): {"readable": accessible, "writable": accessible}}

    def add_jlink(self, accessible=True):
        """SEGGER J-Link (USB bus node only)."""
        self.make_device(
            "1-8",
            product="J-Link",
            manufacturer="SEGGER",
            serial="001050023938",
            vid="1366",
            pid="1061",
            busnum=1,
            devnum=3,
        )
        usb_node = self.make_dev_node("bus/usb/001/003")
        return {str(usb_node): {"readable": accessible, "writable": accessible}}

    def write_fake_state(self, name, text=""):
        (self.fake_dir / name).write_text(text)

    def bootstrap_invocations(self):
        log = self.fake_dir / "argv.log"
        if not log.exists():
            return []
        return log.read_text().splitlines()

    def run_doctor(self, *args, sdk=False, env_extra=None):
        """sdk=False adds NIX_NRF_DOCTOR_SKIP_SDK=1 so hardware-only tests do
        not depend on the fake bootstrap; env_extra values of None unset."""
        env = dict(self.env)
        if not sdk:
            env["NIX_NRF_DOCTOR_SKIP_SDK"] = "1"
        if env_extra:
            for key, value in env_extra.items():
                if value is None:
                    env.pop(key, None)
                else:
                    env[key] = value
        return subprocess.run(
            [sys.executable, DOCTOR_SCRIPT, *args],
            env=env,
            capture_output=True,
            text=True,
        )

    def doctor_json(self, proc):
        """Parse stdout as exactly one JSON object (no extra output)."""
        lines = [line for line in proc.stdout.splitlines() if line.strip()]
        self.assertEqual(len(lines), 1)
        return json.loads(lines[0])

    # 1. No candidate -> hardware fail / exit 1.
    def test_no_candidate_hardware_fail(self):
        proc = self.run_doctor()
        self.assertEqual(proc.returncode, 1)
        self.assertIn("no supported debug probe visible", proc.stdout)
        data = self.doctor_json(self.run_doctor("--json"))
        self.assertFalse(data["ok"])
        self.assertEqual(data["hardware"]["status"], "fail")
        self.assertEqual(data["hardware"]["candidates"], [])

    # 2. Accessible CMSIS-DAP via hidraw -> pass / exit 0.
    def test_accessible_cmsis_dap_via_hidraw(self):
        override = self.add_xiao(accessible=True)
        proc = self.run_doctor(env_extra=self.access_env(override))
        self.assertEqual(proc.returncode, 0)
        self.assertIn("PASS", proc.stdout)
        data = self.doctor_json(
            self.run_doctor("--json", env_extra=self.access_env(override))
        )
        self.assertTrue(data["ok"])
        self.assertEqual(data["hardware"]["status"], "pass")
        cand = data["hardware"]["candidates"][0]
        self.assertEqual(cand["type"], "cmsis-dap")
        self.assertTrue(cand["accessible"])
        self.assertEqual(cand["access_method"], "hidraw")
        self.assertFalse(cand["fallback"])
        self.assertEqual(cand["nodes"][0]["kind"], "hidraw")

    # 3. CMSIS-DAP without hidraw but accessible USB fallback -> pass.
    def test_cmsis_dap_usb_fallback(self):
        override = self.add_pico(accessible=True)
        proc = self.run_doctor(env_extra=self.access_env(override))
        self.assertEqual(proc.returncode, 0)
        self.assertIn("USB fallback", proc.stdout)
        data = self.doctor_json(
            self.run_doctor("--json", env_extra=self.access_env(override))
        )
        cand = data["hardware"]["candidates"][0]
        self.assertTrue(cand["accessible"])
        self.assertEqual(cand["access_method"], "usb")
        self.assertTrue(cand["fallback"])

    # 4. Visible CMSIS-DAP with inaccessible nodes -> fail + remediation.
    def test_visible_cmsis_dap_inaccessible(self):
        override = self.add_xiao(accessible=False)
        proc = self.run_doctor(env_extra=self.access_env(override))
        self.assertEqual(proc.returncode, 1)
        self.assertIn("probe visible but inaccessible", proc.stdout)
        self.assertIn("NixOS:", proc.stdout)
        self.assertIn("imports = [ nix-nrf-dev.nixosModules.default ]", proc.stdout)
        self.assertIn("nix build .#udev-rules", proc.stdout)
        self.assertIn("Packaged udev rule:", proc.stdout)
        self.assertIn("OpenOCD should not run as root.", proc.stdout)
        self.assertNotIn("sudo", proc.stdout)
        data = self.doctor_json(
            self.run_doctor("--json", env_extra=self.access_env(override))
        )
        self.assertFalse(data["ok"])
        self.assertTrue(data["remediation"])
        self.assertFalse(data["hardware"]["candidates"][0]["accessible"])

    # 5. Accessible J-Link via USB node -> pass.
    def test_accessible_jlink_via_usb(self):
        override = self.add_jlink(accessible=True)
        proc = self.run_doctor("--json", env_extra=self.access_env(override))
        self.assertEqual(proc.returncode, 0)
        data = self.doctor_json(proc)
        cand = data["hardware"]["candidates"][0]
        self.assertEqual(cand["type"], "j-link")
        self.assertTrue(cand["accessible"])
        self.assertEqual(cand["access_method"], "usb")
        self.assertFalse(cand["fallback"])

    # 6. Mixed accessible/inaccessible candidates -> pass + warning.
    def test_mixed_accessible_inaccessible(self):
        override = {}
        override.update(self.add_xiao(accessible=True))
        override.update(self.add_pico(accessible=False))
        proc = self.run_doctor(env_extra=self.access_env(override))
        self.assertEqual(proc.returncode, 0)
        self.assertIn("limited access", proc.stdout)
        data = self.doctor_json(
            self.run_doctor("--json", env_extra=self.access_env(override))
        )
        self.assertTrue(data["ok"])
        self.assertEqual(data["hardware"]["status"], "pass")
        by_path = {
            pathlib.Path(c["sysfs_path"]).name: c
            for c in data["hardware"]["candidates"]
        }
        self.assertTrue(by_path["1-9"]["accessible"])
        self.assertFalse(by_path["5-2.4"]["accessible"])
        self.assertTrue(data["remediation"])  # blocked candidate still remediated

    # 7. Missing/unreadable optional attributes do not crash.
    def test_missing_unreadable_attributes_no_crash(self):
        # Recognizable candidate with only `product` (no descriptors, no
        # busnum/devnum -> no nodes at all).
        self.make_device("1-9", product="Test CMSIS-DAP")
        # Unreadable product file (PermissionError path in non-root sandboxes).
        hidden = self.make_device("5-2.4", product="Hidden CMSIS-DAP")
        (hidden / "product").chmod(0o000)
        # Non-probe dir with no product file.
        self.make_device("usb1")
        proc = self.run_doctor()
        self.assertNotIn("Traceback", proc.stderr)
        self.assertIn("Test CMSIS-DAP", proc.stdout)
        # Visible candidate without nodes is inaccessible -> hardware fail.
        self.assertEqual(proc.returncode, 1)

    # 8. SDK ready -> pass with exact path; only --check invocation.
    def test_sdk_ready(self):
        self.write_fake_state("boot_stdout", str(self.sdk_dir) + "\n")
        override = self.add_xiao(accessible=True)
        proc = self.run_doctor("--json", sdk=True, env_extra=self.access_env(override))
        self.assertEqual(proc.returncode, 0)
        data = self.doctor_json(proc)
        self.assertEqual(data["sdk"]["status"], "pass")
        self.assertEqual(data["sdk"]["path"], str(self.sdk_dir))
        self.assertEqual(data["sdk"]["version"], "v3.3.0")
        self.assertEqual(
            self.bootstrap_invocations(), ["--check --quiet --print-sdk-path"]
        )

    # 9. SDK missing -> overall fail + bootstrap remediation; log proves
    #    `--check --quiet --print-sdk-path` only.
    def test_sdk_missing(self):
        self.write_fake_state("boot_exit", "1")
        override = self.add_xiao(accessible=True)
        proc = self.run_doctor("--json", sdk=True, env_extra=self.access_env(override))
        self.assertEqual(proc.returncode, 1)
        data = self.doctor_json(proc)
        self.assertFalse(data["ok"])
        self.assertEqual(data["sdk"]["status"], "fail")
        self.assertIn("run `nix-nrf bootstrap`", data["sdk"]["message"])
        self.assertEqual(data["hardware"]["status"], "pass")  # hardware alone passes
        self.assertIn("SDK/toolchain: run `nix-nrf bootstrap`", data["remediation"])
        self.assertEqual(
            self.bootstrap_invocations(), ["--check --quiet --print-sdk-path"]
        )

    # 10. No configured version and skip mode -> SDK skip, not failure.
    def test_no_version_skip_base_package(self):
        override = self.add_xiao(accessible=True)
        proc = self.run_doctor(
            "--json",
            env_extra={
                "NIX_NRF_DOCTOR_NCS_VERSION": None,
                "NIX_NRF_DOCTOR_SKIP_SDK": None,
            }
            | self.access_env(override),
        )
        self.assertEqual(proc.returncode, 0)
        data = self.doctor_json(proc)
        self.assertEqual(data["sdk"]["status"], "skip")
        self.assertIsNone(data["sdk"]["version"])
        self.assertIn("no NCS version configured", data["sdk"]["message"])
        self.assertEqual(self.bootstrap_invocations(), [])

    def test_no_version_skip_flag(self):
        override = self.add_xiao(accessible=True)
        proc = self.run_doctor(
            "--json",
            env_extra={"NIX_NRF_DOCTOR_NCS_VERSION": None} | self.access_env(override),
        )
        self.assertEqual(proc.returncode, 0)
        data = self.doctor_json(proc)
        self.assertEqual(data["sdk"]["status"], "skip")

    # 11. JSON schema: exactly one object, stable field order, deterministic
    #     candidate ordering.
    def test_json_schema_single_object_deterministic(self):
        override = {}
        override.update(self.add_xiao(accessible=True))
        override.update(self.add_pico(accessible=False))
        override.update(self.add_jlink(accessible=True))
        proc = self.run_doctor("--json", env_extra=self.access_env(override))
        self.assertEqual(proc.returncode, 0)
        data = self.doctor_json(proc)
        self.assertEqual(
            list(data.keys()), ["ok", "sdk", "user", "hardware", "remediation"]
        )
        self.assertEqual(
            list(data["sdk"].keys()), ["status", "version", "path", "message"]
        )
        self.assertEqual(list(data["user"].keys()), ["uid", "name", "groups"])
        self.assertEqual(
            list(data["hardware"].keys()), ["status", "message", "candidates"]
        )
        candidates = data["hardware"]["candidates"]
        names = [pathlib.Path(c["sysfs_path"]).name for c in candidates]
        self.assertEqual(names, sorted(names))  # "1-8" < "1-9" < "5-2.4"
        self.assertEqual(
            [c["type"] for c in candidates], ["j-link", "cmsis-dap", "cmsis-dap"]
        )
        for cand in candidates:
            self.assertEqual(
                list(cand.keys()),
                [
                    "type",
                    "product",
                    "manufacturer",
                    "serial",
                    "vid",
                    "pid",
                    "sysfs_path",
                    "accessible",
                    "access_method",
                    "fallback",
                    "nodes",
                ],
            )
            for node in cand["nodes"]:
                self.assertEqual(
                    list(node.keys()),
                    ["path", "kind", "exists", "readable", "writable"],
                )
        self.assertEqual(len(self.bootstrap_invocations()), 0)

    # 12. Human output: udev guidance only when needed, never a sudo command.
    def test_human_remediation_only_when_needed_no_sudo(self):
        override = {}
        override.update(self.add_xiao(accessible=True))
        override.update(self.add_jlink(accessible=True))
        proc = self.run_doctor(env_extra=self.access_env(override))
        self.assertEqual(proc.returncode, 0)
        self.assertNotIn("sudo", proc.stdout)
        self.assertNotIn("udev", proc.stdout)
        self.assertNotIn("nix build", proc.stdout)
        self.assertTrue(proc.stdout.rstrip().endswith("PASS"))
        self.assertIn("SDK/toolchain", proc.stdout)
        self.assertIn("User access", proc.stdout)
        self.assertIn("Debug probes", proc.stdout)

    def test_human_remediation_blocks_when_blocked_no_sudo(self):
        override = self.add_xiao(accessible=False)
        proc = self.run_doctor(env_extra=self.access_env(override))
        self.assertEqual(proc.returncode, 1)
        self.assertIn("NixOS:", proc.stdout)
        self.assertIn("imports = [ nix-nrf-dev.nixosModules.default ]", proc.stdout)
        self.assertIn("Other Linux:", proc.stdout)
        self.assertIn("nix build .#udev-rules", proc.stdout)
        self.assertIn(
            "documented udev procedure, reload rules, then replug probe.", proc.stdout
        )
        self.assertIn("Packaged udev rule:", proc.stdout)
        self.assertIn("OpenOCD should not run as root.", proc.stdout)
        self.assertNotIn("sudo", proc.stdout)
        self.assertTrue(proc.stdout.rstrip().endswith("FAIL"))

    # Extra public-surface behavior:
    def test_help_exits_0(self):
        proc = self.run_doctor("--help")
        self.assertEqual(proc.returncode, 0)
        self.assertIn("nix-nrf doctor", proc.stdout)

    def test_unknown_flag_exits_2(self):
        proc = self.run_doctor("--bogus")
        self.assertEqual(proc.returncode, 2)

    def test_sdk_malformed_multiple_paths(self):
        self.write_fake_state("boot_stdout", f"{self.sdk_dir}\n{self.sdk_dir}\n")
        override = self.add_xiao(accessible=True)
        proc = self.run_doctor("--json", sdk=True, env_extra=self.access_env(override))
        self.assertEqual(proc.returncode, 1)
        data = self.doctor_json(proc)
        self.assertEqual(data["sdk"]["status"], "fail")
        self.assertIn("malformed", data["sdk"]["message"])

    def test_sdk_path_does_not_exist(self):
        self.write_fake_state("boot_stdout", str(self.root / "nope") + "\n")
        override = self.add_xiao(accessible=True)
        proc = self.run_doctor("--json", sdk=True, env_extra=self.access_env(override))
        self.assertEqual(proc.returncode, 1)
        data = self.doctor_json(proc)
        self.assertEqual(data["sdk"]["status"], "fail")
        self.assertIn("non-existing", data["sdk"]["message"])

    # West backend label: the wrapped west-shell doctor passes
    # NIX_NRF_DOCTOR_ENVIRONMENT_LABEL="west workspace/Zephyr SDK". Human
    # headings/status/remediation reflect the label; JSON field names and
    # exit semantics never change, and the bootstrap is invoked only through
    # its read-only `--check --quiet --print-sdk-path` contract.
    def test_west_environment_label_human_output(self):
        self.write_fake_state("boot_stdout", str(self.sdk_dir) + "\n")
        override = self.add_xiao(accessible=True)
        env = {
            "NIX_NRF_DOCTOR_ENVIRONMENT_LABEL": "west workspace/Zephyr SDK",
        } | self.access_env(override)
        proc = self.run_doctor(sdk=True, env_extra=env)
        self.assertEqual(proc.returncode, 0)
        self.assertIn("west workspace/Zephyr SDK", proc.stdout)
        self.assertIn("NCS v3.3.0 ready", proc.stdout)
        self.assertIn("Debug probes", proc.stdout)
        self.assertEqual(
            self.bootstrap_invocations(), ["--check --quiet --print-sdk-path"]
        )

    def test_west_environment_label_remediation_json_stable(self):
        self.write_fake_state("boot_exit", "1")
        override = self.add_xiao(accessible=True)
        env = {
            "NIX_NRF_DOCTOR_ENVIRONMENT_LABEL": "west workspace/Zephyr SDK",
        } | self.access_env(override)
        proc = self.run_doctor("--json", sdk=True, env_extra=env)
        self.assertEqual(proc.returncode, 1)
        data = self.doctor_json(proc)
        self.assertEqual(
            list(data.keys()), ["ok", "sdk", "user", "hardware", "remediation"]
        )
        self.assertEqual(
            list(data["sdk"].keys()), ["status", "version", "path", "message"]
        )
        self.assertEqual(data["sdk"]["status"], "fail")
        self.assertIn(
            "west workspace/Zephyr SDK: run `nix-nrf bootstrap`",
            data["remediation"],
        )
        self.assertEqual(
            self.bootstrap_invocations(), ["--check --quiet --print-sdk-path"]
        )


if __name__ == "__main__":
    unittest.main()
