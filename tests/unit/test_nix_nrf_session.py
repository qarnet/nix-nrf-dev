"""Public process ownership tests plus actual no-hardware OpenOCD Tcl traffic."""

import json
import os
from pathlib import Path
import selectors
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(os.environ.get("SESSION_SCRIPT", ROOT / "bin/commands/nix-nrf-session"))
FIXTURES = Path(os.environ.get("SESSION_FIXTURES", ROOT / "tests/fixtures"))


class SessionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.doctor = self.root / "doctor"
        self.doctor.write_text(
            f"#!{sys.executable}\nimport os\nprint(os.environ['DOCTOR_JSON'])\n"
        )
        self.doctor.chmod(0o755)
        self.candidate = {
            "serial": "test-serial",
            "type": "cmsis-dap",
            "accessible": True,
            "access_method": "usb",
            "fallback": False,
            "nodes": [
                {"kind": "usb", "exists": True, "readable": True, "writable": True}
            ],
        }
        self.env = dict(
            os.environ,
            NIX_NRF_SESSION_DOCTOR=str(self.doctor),
            NIX_NRF_SESSION_OPENOCD=str(FIXTURES / "session-openocd.py"),
            DOCTOR_JSON=json.dumps({"hardware": {"candidates": [self.candidate]}}),
        )
        self.children = []
        self.addCleanup(self.cleanup_children)

    def cleanup_children(self):
        for child in self.children:
            if child.poll() is None:
                child.terminate()
                child.wait(timeout=8)
            child.stdout.close()

    def command(self, operation="start", *args):
        return [
            sys.executable,
            str(SCRIPT),
            operation,
            "--serial",
            "test-serial",
            "--runtime-dir",
            str(self.root / "runtime"),
            *args,
        ]

    def run_command(self, *args, operation="start", env=None):
        return subprocess.run(
            self.command(operation, *args),
            env=env or self.env,
            capture_output=True,
            text=True,
            timeout=12,
        )

    def launch(self, *args, env=None):
        log = open(self.root / f"stderr-{len(self.children)}", "w+")
        self.addCleanup(log.close)
        child = subprocess.Popen(
            self.command("start", *args),
            env=env or self.env,
            stdout=subprocess.PIPE,
            stderr=log,
            text=True,
        )
        self.children.append(child)
        assert child.stdout is not None
        with selectors.DefaultSelector() as select:
            select.register(child.stdout, selectors.EVENT_READ)
            self.assertTrue(select.select(10), "session did not report readiness")
        line = child.stdout.readline()
        if not line:
            log.seek(0)
            self.fail(log.read())
        return child, json.loads(line)

    def test_status_and_contention_do_not_terminate_owner(self):
        child, ready = self.launch("--tcl-port", "0")
        status = self.run_command(operation="status")
        self.assertEqual(status.returncode, 0, status.stderr)
        self.assertEqual(json.loads(status.stdout)["id"], ready["id"])
        second = self.run_command()
        self.assertNotEqual(second.returncode, 0)
        self.assertIn("already owned", second.stderr)
        self.assertIsNone(child.poll())
        with socket.create_connection(("127.0.0.1", ready["tcl_port"]), timeout=1):
            pass
        child.terminate()
        self.assertEqual(child.wait(timeout=8), 130)
        self.assertFalse(Path(ready["manifest"]).exists())
        self.assertNotEqual(self.run_command(operation="status").returncode, 0)
        replacement, new = self.launch()
        self.assertNotEqual(ready["id"], new["id"])
        self.assertIsNone(new["tcl_port"])
        self.assertIsNone(new["gdb_port"])
        replacement.terminate()

    def test_duplicate_and_inaccessible_probes_fail_before_session(self):
        for candidates in (
            [self.candidate, self.candidate],
            [],
            [dict(self.candidate, accessible=False)],
        ):
            with self.subTest(candidates=candidates):
                env = dict(
                    self.env,
                    DOCTOR_JSON=json.dumps({"hardware": {"candidates": candidates}}),
                )
                result = self.run_command(env=env)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")

    def test_startup_failure_timeout_and_retry(self):
        for scenario in ("failure", "timeout"):
            with self.subTest(scenario=scenario):
                result = self.run_command(
                    "--startup-timeout",
                    "0.3",
                    env=dict(self.env, SESSION_SCENARIO=scenario),
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
        child, _ = self.launch()
        child.terminate()

    def test_port_conflict_has_no_ready_manifest(self):
        with socket.socket() as occupied:
            occupied.bind(("127.0.0.1", 0))
            occupied.listen()
            result = self.run_command("--tcl-port", str(occupied.getsockname()[1]))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_explicit_debug_ports_and_bounded_stubborn_shutdown(self):
        child, ready = self.launch(
            "--mode",
            "debug",
            "--gdb-port",
            "0",
            "--tcl-port",
            "0",
            env=dict(self.env, SESSION_SCENARIO="stubborn"),
        )
        self.assertGreater(ready["gdb_port"], 0)
        self.assertNotEqual(ready["gdb_port"], ready["tcl_port"])
        start = time.monotonic()
        child.send_signal(signal.SIGINT)
        child.wait(timeout=8)
        self.assertGreater(time.monotonic() - start, 2.5)
        self.assertLess(time.monotonic() - start, 7)
        self.assertFalse(Path(ready["manifest"]).exists())

    def test_unexpected_exit_removes_manifest(self):
        child, ready = self.launch(
            env=dict(self.env, SESSION_SCENARIO="exit-after-ready")
        )
        self.assertNotEqual(child.wait(timeout=8), 0)
        self.assertFalse(Path(ready["manifest"]).exists())

    def test_invalid_arguments_and_unsafe_directory(self):
        for args in (
            ("--gdb-port", "3333"),
            ("--speed", "0"),
            ("--startup-timeout", "nan"),
            ("--serial", "bad\nserial"),
        ):
            self.assertEqual(self.run_command(*args).returncode, 2)
        (self.root / "runtime").mkdir(mode=0o755)
        self.assertNotEqual(self.run_command().returncode, 0)

    @unittest.skipUnless(os.environ.get("REAL_OPENOCD"), "requires pinned OpenOCD")
    def test_real_openocd_tcl_wire_and_serial_quoting(self):
        # Real Jim Tcl, listener, framing and cleanup. Only adapter and target
        # are replaced: no claim about physical Cortex-M state preservation.
        evil = 'probe"; error INJECTED; # $x [error INJECTED] \\ {x}'
        self.candidate["serial"] = evil
        env = dict(
            self.env,
            DOCTOR_JSON=json.dumps({"hardware": {"candidates": [self.candidate]}}),
            NIX_NRF_SESSION_OPENOCD=str(FIXTURES / "session-dummy-openocd.py"),
        )
        child, ready = self.launch("--tcl-port", "0", "--serial", evil, env=env)
        with socket.create_connection(
            ("127.0.0.1", ready["tcl_port"]), timeout=2
        ) as sock:
            sock.sendall(b"expr {6 *")
            sock.sendall(b" 7}\x1a")
            data = b""
            while not data.endswith(b"\x1a"):
                data += sock.recv(1024)
            self.assertEqual(data, b"42\x1a")
            sock.sendall(b"list [nrf54l.cpu was_examined] [poll]\x1a")
            data = sock.recv(1024)
            self.assertIn(b"1", data)
            # Ephemeral RTT service removal uses original key "0", not the
            # allocated port. Exercise the pinned server, not a mock here.
            sock.sendall(
                b"rtt server start 0 0; rtt server start 0 1; rtt server stop 0; rtt server stop 0; set n 0; foreach s [services] {if {[dict get $s name] eq {rtt}} {incr n}}; set n\x1a"
            )
            data = b""
            while not data.endswith(b"\x1a"):
                data += sock.recv(1024)
            self.assertEqual(data, b"0\x1a")
        child.terminate()
        child.wait(timeout=8)
        self.assertIn("SESSION_CLEAN_SHUTDOWN", (self.root / "stderr-0").read_text())
        with self.assertRaises(OSError):
            socket.create_connection(("127.0.0.1", ready["tcl_port"]), timeout=0.3)

    def test_killed_owner_keeps_probe_locked_while_child_lives(self):
        owner, ready = self.launch()
        try:
            owner.kill()
            owner.wait(timeout=3)
            result = self.run_command()
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("already owned", result.stderr)
        finally:
            os.kill(ready["openocd_pid"], signal.SIGTERM)
        deadline = time.monotonic() + 3
        while self.run_command(operation="status").returncode == 0:
            self.assertLess(time.monotonic(), deadline)
            time.sleep(0.05)
        replacement, new = self.launch()
        self.assertNotEqual(new["id"], ready["id"])
        replacement.terminate()


if __name__ == "__main__":
    unittest.main()
