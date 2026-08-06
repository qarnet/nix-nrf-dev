#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
#
# tests/unit/test_nix_nrf_probes.py — fake-boundary unit tests for the
# `nix-nrf probes` command module (bin/commands/nix-nrf-probes).
#
# Exercises the command as a subprocess through public args and environment
# against a temporary fake sysfs tree and a fake `openocd` executable first
# on PATH. No real /sys, no USB devices, no OpenOCD, no network: enumeration,
# table parsing, serial filtering, --find semantics, openocd-not-found, and
# timeout behavior are all driven by fixtures. The fake openocd records its
# full argv so tests can prove the read-only scan invocation while remaining
# agnostic to Python implementation details.
#
# Run standalone from the repo:  python3 tests/unit/test_nix_nrf_probes.py
# Wired as checks.probes-tests in nix/flake/checks/core.nix (sandboxed Python
# stdlib); the derivation sets NIX_NRF_PROBES_SCRIPT to the copied script.

import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest


def _resolve_probes_script() -> str:
    # The sandboxed check derivation copies the test to /build root, where
    # the repo-relative fallback cannot be computed (parents[2] missing);
    # NIX_NRF_PROBES_SCRIPT is set there.
    configured = os.environ.get("NIX_NRF_PROBES_SCRIPT")
    if configured:
        return configured
    try:
        repo_root = pathlib.Path(__file__).resolve().parents[2]
    except IndexError:
        raise RuntimeError(
            "NIX_NRF_PROBES_SCRIPT is not set and the repo root is unavailable"
        )
    return str(repo_root / "bin" / "commands" / "nix-nrf-probes")


PROBES_SCRIPT = _resolve_probes_script()

# Fake openocd: records the full argv as one JSON line per invocation, then
# emits per-serial stdout/stderr fixtures. `out_<serial>`/`err_<serial>`
# files hold FWP lines / error text; a `sleep` file makes the process linger
# so the command's timeout path can be exercised without waiting 30 seconds.
FAKE_OPENOCD = r"""import json
import os
import pathlib
import sys
import time

state = pathlib.Path(os.environ["FAKE_OPENOCD_DIR"])
serial = ""
for arg in sys.argv[1:]:
    if arg.startswith("adapter serial "):
        serial = arg.split(" ", 2)[2]

with (state / "argv.log").open("a") as fh:
    fh.write(json.dumps(sys.argv[1:]) + "\n")

sleep_file = state / "sleep"
if sleep_file.exists():
    time.sleep(int(sleep_file.read_text().strip()))

out = state / ("out_" + serial)
if out.exists():
    sys.stdout.write(out.read_text())
err = state / ("err_" + serial)
if err.exists():
    sys.stderr.write(err.read_text())
sys.exit(0)
"""


class ProbesTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)
        self.sysfs = self.root / "sysfs"
        self.sysfs.mkdir()
        self.fake_dir = self.root / "fake-openocd"
        self.fake_dir.mkdir()
        self.fake_openocd = self.fake_dir / "openocd"
        self.fake_openocd.write_text(f"#!{sys.executable}\n{FAKE_OPENOCD}")
        self.fake_openocd.chmod(0o755)
        self.env = os.environ.copy()
        self.env["NIX_NRF_PROBES_SYSFS_ROOT"] = str(self.sysfs)
        self.env["FAKE_OPENOCD_DIR"] = str(self.fake_dir)
        self.env["PATH"] = str(self.fake_dir) + os.pathsep + self.env.get("PATH", "")

    def tearDown(self):
        self.tmp.cleanup()

    # ── fixture helpers ────────────────────────────────────────────────────

    def make_device(self, name, *, product=None, serial=None):
        """Create one fake USB sysfs device dir with optional attributes."""
        dev = self.sysfs / name
        dev.mkdir(parents=True)
        for key, value in (("product", product), ("serial", serial)):
            if value is not None:
                (dev / key).write_text(str(value))
        return dev

    def write_fwp(
        self,
        serial,
        *,
        dpidr="",
        aps=("", "", "", ""),
        family="unknown",
        part="",
        variant="",
    ):
        """Write the fake openocd's FWP|key|value output for a serial."""
        lines = []
        if dpidr:
            lines.append(f"FWP|dpidr|{dpidr}")
        for i, idr in enumerate(aps):
            if idr:
                lines.append(f"FWP|ap{i}|{idr}")
        lines.append(f"FWP|family|{family}")
        if part:
            lines.append(f"FWP|part|{part}")
        if variant:
            lines.append(f"FWP|variant|{variant}")
        (self.fake_dir / f"out_{serial}").write_text("\n".join(lines) + "\n")

    def run_probes(self, *args, env_extra=None):
        """Run the real probe command as a subprocess against fixtures."""
        env = dict(self.env)
        if env_extra:
            for key, value in env_extra.items():
                if value is None:
                    env.pop(key, None)
                else:
                    env[key] = value
        return subprocess.run(
            [sys.executable, PROBES_SCRIPT, *args],
            env=env,
            capture_output=True,
            text=True,
        )

    def invocations(self):
        """Parsed argv of every fake openocd invocation, in order."""
        log = self.fake_dir / "argv.log"
        if not log.exists():
            return []
        return [json.loads(line) for line in log.read_text().splitlines()]

    def table_row(self, stdout, serial):
        """Return the table line for a serial (header/row col 0 is SERIAL)."""
        return next(
            line for line in stdout.splitlines() if line.startswith(serial + "  ")
        )

    # 1. Empty sysfs: no CMSIS-DAP probes found, nonzero, no OpenOCD run.
    def test_empty_sysfs_no_probes(self):
        proc = self.run_probes()
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("nix-nrf probes: no CMSIS-DAP probes found", proc.stderr)
        self.assertEqual(self.invocations(), [])

    # 2. Enumeration filtering: non-CMSIS products and CMSIS-DAP devices
    #    without a serial are skipped; accepted devices keep sysfs path order.
    def test_enumeration_filtering(self):
        self.make_device("1-1", product="Some Random Widget", serial="W1")
        self.make_device("1-2", product="Probe with no serial (CMSIS-DAP)")
        self.make_device("1-3", product="Probe A (CMSIS-DAP)", serial="AAA")
        self.make_device("1-4", product="Probe B (CMSIS-DAP)", serial="BBB")
        self.write_fwp("AAA", dpidr="0x6ba02477", family="nrf54l", part="0x00054b15")
        self.write_fwp("BBB", dpidr="0x6ba02477", family="nrf54l", part="0x00054b15")
        proc = self.run_probes()
        self.assertEqual(proc.returncode, 0)
        self.assertNotIn("Some Random Widget", proc.stdout)
        self.assertNotIn("Probe with no serial", proc.stdout)
        self.assertLess(proc.stdout.index("AAA"), proc.stdout.index("BBB"))
        # Only the two accepted devices were fingerprinted.
        self.assertEqual(len(self.invocations()), 2)

    # 3. Table parsing across parts, variants, and target fallbacks.
    def test_table_parsing(self):
        self.make_device("1-1", product="Probe A (CMSIS-DAP)", serial="p5340")
        self.make_device("1-2", product="Probe B (CMSIS-DAP)", serial="p54l15")
        self.make_device("1-3", product="Probe C (CMSIS-DAP)", serial="p52")
        self.make_device("1-4", product="Probe D (CMSIS-DAP)", serial="pbadvar")
        self.make_device("1-5", product="Probe E (CMSIS-DAP)", serial="punknown")
        self.make_device("1-6", product="Probe F (CMSIS-DAP)", serial="pnotgt")
        self.write_fwp(
            "p5340",
            dpidr="0x02880000",
            family="nrf53",
            part="0x00005340",
            variant="0x41414141",
        )
        self.write_fwp("p54l15", dpidr="0x6ba02477", family="nrf54l", part="0x00054b15")
        self.write_fwp("p52", dpidr="0x2ba01477", family="nrf52", part="0x00052840")
        self.write_fwp(
            "pbadvar",
            dpidr="0x2ba01477",
            family="nrf52",
            part="0x00005340",
            variant="0xffffffff",
        )
        self.write_fwp("punknown", dpidr="0x2ba01477", family="unknown")
        self.write_fwp("pnotgt", family="unknown")
        proc = self.run_probes()
        self.assertEqual(proc.returncode, 0)
        for heading in (
            "SERIAL",
            "PROBE",
            "TARGET",
            "DPIDR",
            "PART",
            "VARIANT",
            "NOTE",
        ):
            self.assertIn(heading, proc.stdout)
        self.assertIn("nRF5340", self.table_row(proc.stdout, "p5340"))
        self.assertIn("nRF54L15", self.table_row(proc.stdout, "p54l15"))
        self.assertIn("nRF52840", self.table_row(proc.stdout, "p52"))
        # ASCII variant decodes; invalid variant falls back to raw hex.
        self.assertIn("AAAA", self.table_row(proc.stdout, "p5340"))
        self.assertIn("0xffffffff", self.table_row(proc.stdout, "pbadvar"))
        self.assertIn("unknown target", self.table_row(proc.stdout, "punknown"))
        self.assertIn(
            "no target (wiring? power?)", self.table_row(proc.stdout, "pnotgt")
        )

    # 4. Open failure maps to the existing udev/in-use note.
    def test_unable_to_open_note(self):
        self.make_device("1-1", product="Probe A (CMSIS-DAP)", serial="popen")
        self.write_fwp("popen", family="unknown")
        (self.fake_dir / "err_popen").write_text("unable to open CMSIS-DAP device\n")
        proc = self.run_probes()
        self.assertEqual(proc.returncode, 0)
        self.assertIn(
            "cannot open probe (udev permissions? probe in use?)",
            self.table_row(proc.stdout, "popen"),
        )

    # 5. Locked target: family fallback + APPROTECT note.
    def test_locked_target_note(self):
        self.make_device("1-1", product="Probe A (CMSIS-DAP)", serial="plock")
        self.write_fwp(
            "plock", dpidr="0x2ba01477", aps=("", "", "", ""), family="nrf52"
        )
        (self.fake_dir / "err_plock").write_text("Examination failed\n")
        proc = self.run_probes()
        self.assertEqual(proc.returncode, 0)
        row = self.table_row(proc.stdout, "plock")
        self.assertIn("nrf52 (locked?)", row)
        self.assertIn(
            "AP locked (APPROTECT engaged) — identity from DP/AP signature only", row
        )

    # 6. Serial filtering invokes OpenOCD only for selected present serials.
    def test_serial_filtering(self):
        self.make_device("1-1", product="Probe A (CMSIS-DAP)", serial="AAA")
        self.make_device("1-2", product="Probe B (CMSIS-DAP)", serial="BBB")
        self.make_device("1-3", product="Probe C (CMSIS-DAP)", serial="CCC")
        self.write_fwp("AAA", family="nrf52", part="0x00052840")
        self.write_fwp("BBB", family="nrf52", part="0x00052840")
        self.write_fwp("CCC", family="nrf52", part="0x00052840")
        proc = self.run_probes("BBB")
        self.assertEqual(proc.returncode, 0)
        invocations = self.invocations()
        self.assertEqual(len(invocations), 1)
        self.assertIn("adapter serial BBB", invocations[0])
        for argv in invocations:
            self.assertNotIn("adapter serial AAA", argv)
            self.assertNotIn("adapter serial CCC", argv)

    # 7. Missing serials: caller order preserved, duplicates removed.
    def test_missing_serial_order_and_dedup(self):
        self.make_device("1-1", product="Probe A (CMSIS-DAP)", serial="AAA")
        self.write_fwp("AAA", family="nrf52", part="0x00052840")
        proc = self.run_probes("MISS2", "MISS1", "MISS2")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn(
            "nix-nrf probes: no CMSIS-DAP probe with serial MISS2, MISS1", proc.stderr
        )
        self.assertEqual(self.invocations(), [])

    # 8. --find semantics.
    def test_find_unique_family(self):
        self.make_device("1-1", product="Probe A (CMSIS-DAP)", serial="AAA")
        self.make_device("1-2", product="Probe B (CMSIS-DAP)", serial="BBB")
        self.write_fwp("AAA", family="nrf53", part="0x00005340")
        self.write_fwp("BBB", family="nrf52", part="0x00052840")
        proc = self.run_probes("--find", "nrf53")
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout.strip(), "AAA")

    def test_find_exact_chip_name(self):
        self.make_device("1-1", product="Probe A (CMSIS-DAP)", serial="AAA")
        self.make_device("1-2", product="Probe B (CMSIS-DAP)", serial="BBB")
        self.write_fwp("AAA", family="nrf53", part="0x00005340")
        self.write_fwp("BBB", family="nrf52", part="0x00052840")
        proc = self.run_probes("--find", "nrf5340")
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout.strip(), "AAA")

    def test_find_no_match(self):
        self.make_device("1-1", product="Probe A (CMSIS-DAP)", serial="AAA")
        self.write_fwp("AAA", family="nrf53", part="0x00005340")
        proc = self.run_probes("--find", "nrf91")
        self.assertEqual(proc.returncode, 1)
        self.assertEqual(proc.stdout, "")
        self.assertIn("->", proc.stderr)  # inventory lines
        self.assertIn("nix-nrf probes: no probe with a nrf91 target", proc.stderr)

    def test_find_multiple_matches(self):
        self.make_device("1-1", product="Probe A (CMSIS-DAP)", serial="AAA")
        self.make_device("1-2", product="Probe B (CMSIS-DAP)", serial="BBB")
        self.make_device("1-3", product="Probe C (CMSIS-DAP)", serial="CCC")
        self.write_fwp("AAA", family="nrf53", part="0x00005340")
        self.write_fwp("BBB", family="nrf52", part="0x00052840")
        self.write_fwp("CCC", family="nrf52", part="0x00052833")
        proc = self.run_probes("--find", "nrf52")
        self.assertEqual(proc.returncode, 2)
        self.assertEqual(proc.stdout, "")
        self.assertIn("->", proc.stderr)
        self.assertIn(
            "nix-nrf probes: multiple probes with a nrf52 target", proc.stderr
        )

    # 9. Missing OpenOCD: existing error, no traceback.
    def test_missing_openocd(self):
        self.make_device("1-1", product="Probe A (CMSIS-DAP)", serial="AAA")
        self.write_fwp("AAA", family="nrf52", part="0x00052840")
        empty_dir = self.root / "empty-path"
        empty_dir.mkdir()
        proc = self.run_probes(env_extra={"PATH": str(empty_dir)})
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("nix-nrf probes: openocd not found on PATH", proc.stderr)
        self.assertNotIn("Traceback", proc.stderr)

    # 10. Short timeout: table note, no 30-second wait.
    def test_short_timeout_note(self):
        self.make_device("1-1", product="Probe A (CMSIS-DAP)", serial="AAA")
        self.write_fwp("AAA", dpidr="0x2ba01477", family="nrf52")
        (self.fake_dir / "sleep").write_text("60")
        proc = self.run_probes(env_extra={"NIX_NRF_PROBES_OPENOCD_TIMEOUT": "1"})
        self.assertEqual(proc.returncode, 0)
        self.assertIn("timeout talking to probe", self.table_row(proc.stdout, "AAA"))
        self.assertEqual(len(self.invocations()), 1)

    # 11. Invalid timeouts: clean failure, OpenOCD never invoked.
    def test_invalid_timeout(self):
        self.make_device("1-1", product="Probe A (CMSIS-DAP)", serial="AAA")
        self.write_fwp("AAA", family="nrf52", part="0x00052840")
        for bad in ("abc", "0", "-5"):
            with self.subTest(bad=bad):
                proc = self.run_probes(
                    env_extra={"NIX_NRF_PROBES_OPENOCD_TIMEOUT": bad}
                )
                self.assertNotEqual(proc.returncode, 0)
                self.assertIn("nix-nrf probes:", proc.stderr)
                self.assertNotIn("Traceback", proc.stderr)
                self.assertNotIn("0x00052840", proc.stdout)  # never fingerprinted
                self.assertEqual(self.invocations(), [])

    # 12. Fake argv log proves the read-only scan invocation reaches OpenOCD.
    def test_openocd_argv(self):
        self.make_device("1-1", product="Probe A (CMSIS-DAP)", serial="AAA")
        self.write_fwp("AAA", dpidr="0x2ba01477", family="nrf52", part="0x00052840")
        proc = self.run_probes()
        self.assertEqual(proc.returncode, 0)
        invocations = self.invocations()
        self.assertEqual(len(invocations), 1)
        argv = invocations[0]
        self.assertIsInstance(argv, list)
        self.assertIn("interface/cmsis-dap.cfg", argv)  # CMSIS-DAP config
        self.assertIn("adapter serial AAA", argv)  # serial selection
        self.assertIn("transport select swd", argv)
        self.assertIn("gdb_port disabled", argv)
        self.assertIn("tcl_port disabled", argv)
        self.assertIn("telnet_port disabled", argv)
        self.assertIn("init", argv)
        self.assertIn("fwp_scan", argv)
        self.assertIn("shutdown", argv)
        # The scan proc is passed as one -c argument and carries FWP output.
        scan = next(arg for arg in argv if "proc fwp_scan" in arg)
        self.assertIn("FWP|dpidr|", scan)
        self.assertIn("FWP|part|", scan)


if __name__ == "__main__":
    unittest.main()
