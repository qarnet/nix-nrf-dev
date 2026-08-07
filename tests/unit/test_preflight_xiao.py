#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
#
# tests/unit/test_preflight_xiao.py — public-boundary tests for the
# hardware harness doctor preflight parser
# (tests/hardware/preflight_xiao.py).
#
# The parser is a pure stdin-to-result boundary: it consumes exactly one
# `nix-nrf doctor --json` document and asserts the hardware harness's own
# consumer contract (exactly one candidate with the requested serial,
# explicit CMSIS-DAP v2 bulk USB, accessible USB node — no devnum, no
# /dev/bus/usb or hidraw path, no hidraw permissions). These tests run it
# as a subprocess against canned JSON documents and assert only the public
# boundary: exit classes and stdout/stderr output. No hardware, no real
# /sys or /dev, no doctor or OpenOCD invocation, no network.
#
# Run standalone from the repo:  python3 tests/unit/test_preflight_xiao.py
# Wired as checks.preflight-xiao-tests in nix/flake/checks/core.nix
# (sandboxed Python stdlib); the derivation copies the parser and test and
# sets NIX_NRF_PREFLIGHT_XIAO_SCRIPT to the copied parser.

import json
import os
import pathlib
import subprocess
import sys
import unittest


def _resolve_preflight_script() -> str:
    # The sandboxed check derivation copies the test to /build root, where
    # the repo-relative fallback cannot be computed (parents[2] missing);
    # NIX_NRF_PREFLIGHT_XIAO_SCRIPT is set there.
    configured = os.environ.get("NIX_NRF_PREFLIGHT_XIAO_SCRIPT")
    if configured:
        return configured
    try:
        repo_root = pathlib.Path(__file__).resolve().parents[2]
    except IndexError:
        raise RuntimeError(
            "NIX_NRF_PREFLIGHT_XIAO_SCRIPT is not set and the repo root is unavailable"
        )
    return str(repo_root / "tests" / "hardware" / "preflight_xiao.py")


PREFLIGHT_SCRIPT = _resolve_preflight_script()

SERIAL = "8EE9B3FF"


# ── canned JSON builders ────────────────────────────────────────────────────


def usb_node(path="/dev/bus/usb/001/017", exists=True, readable=True, writable=True):
    return {
        "path": path,
        "kind": "usb",
        "exists": exists,
        "readable": readable,
        "writable": writable,
    }


def candidate(**overrides):
    """One doctor-style candidate; the exact success shape for XIAO 8EE9B3FF
    via explicit CMSIS-DAP v2 bulk USB."""
    base = {
        "type": "cmsis-dap",
        "product": "Seeed Studio XIAO nrf54 CMSIS-DAP",
        "manufacturer": "Seeed Studio",
        "serial": SERIAL,
        "vid": "2886",
        "pid": "0066",
        "sysfs_path": "/sys/bus/usb/devices/1-9",
        "accessible": True,
        "access_method": "usb",
        "fallback": False,
        "nodes": [usb_node()],
    }
    base.update(overrides)
    return base


def doc(candidates, remediation=None):
    """A doctor JSON document; `candidates` may be any JSON value to model
    malformed schema."""
    return {
        "ok": True,
        "sdk": {"status": "skip", "version": None, "path": None, "message": "skipped"},
        "user": {"uid": 1000, "name": "tester", "groups": []},
        "hardware": {
            "status": "pass",
            "message": "1 accessible probe(s)",
            "candidates": candidates,
        },
        "remediation": remediation or [],
    }


class PreflightXiaoTestCase(unittest.TestCase):
    def run_parser(self, json_input, *args):
        """Run the parser as a subprocess with stdin=json_input."""
        return subprocess.run(
            [sys.executable, PREFLIGHT_SCRIPT, *args],
            input=json_input,
            capture_output=True,
            text=True,
        )

    def run_doc(self, document, *args):
        if not args:
            args = (SERIAL,)
        return self.run_parser(json.dumps(document), *args)

    # 1. Exact success with an unrelated candidate present -> exit 0.
    def test_exact_success_with_unrelated_candidate(self):
        proc = self.run_doc(
            doc(
                [
                    candidate(),
                    candidate(
                        serial="E6635C08CB1F502B",
                        product="Debugprobe on Pico (CMSIS-DAP)",
                        manufacturer="Raspberry Pi",
                        vid="2e8a",
                        pid="000c",
                        sysfs_path="/sys/bus/usb/devices/5-2.4",
                    ),
                ]
            )
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn(
            f"OK: XIAO {SERIAL} usable via explicit CMSIS-DAP v2 bulk USB "
            "(Seeed Studio XIAO nrf54 CMSIS-DAP)",
            proc.stdout,
        )
        self.assertNotIn("FAIL", proc.stdout)
        self.assertEqual(proc.stderr, "")

    # 2. No candidate with the requested serial -> exit 1 (valid JSON).
    def test_missing_serial(self):
        proc = self.run_doc(doc([candidate(serial="DEADBEEF")]))
        self.assertEqual(proc.returncode, 1)
        self.assertIn("no candidate with serial", proc.stderr)
        self.assertIn(SERIAL, proc.stderr)
        self.assertEqual(proc.stdout, "")

    # 3. Duplicate serial -> exit 1 (exactly one candidate required).
    def test_duplicate_serial(self):
        proc = self.run_doc(
            doc(
                [
                    candidate(sysfs_path="/sys/bus/usb/devices/1-9"),
                    candidate(sysfs_path="/sys/bus/usb/devices/1-10"),
                ]
            )
        )
        self.assertEqual(proc.returncode, 1)
        self.assertIn("expected exactly one", proc.stderr)
        self.assertIn(SERIAL, proc.stderr)

    # 4. Visible but inaccessible -> exit 1.
    def test_inaccessible(self):
        proc = self.run_doc(doc([candidate(accessible=False)]))
        self.assertEqual(proc.returncode, 1)
        self.assertIn("not accessible", proc.stderr)
        self.assertIn(SERIAL, proc.stderr)

    # 5. Wrong candidate type -> exit 1.
    def test_wrong_type(self):
        proc = self.run_doc(doc([candidate(type="j-link")]))
        self.assertEqual(proc.returncode, 1)
        self.assertIn("expected 'cmsis-dap'", proc.stderr)
        self.assertIn("'j-link'", proc.stderr)

    # 6. HID transport chosen instead of explicit v2 bulk USB -> exit 1.
    def test_hidraw_method(self):
        proc = self.run_doc(doc([candidate(access_method="hidraw")]))
        self.assertEqual(proc.returncode, 1)
        self.assertIn("access method 'hidraw'", proc.stderr)
        self.assertIn("expected 'usb'", proc.stderr)

    # 7. Legacy USB fallback -> exit 1.
    def test_fallback_true(self):
        proc = self.run_doc(doc([candidate(fallback=True)]))
        self.assertEqual(proc.returncode, 1)
        self.assertIn("USB fallback", proc.stderr)

    # 8. No usable USB node (missing + blocked) -> exit 1.
    def test_missing_or_inaccessible_usb_node(self):
        proc = self.run_doc(
            doc(
                [
                    candidate(
                        nodes=[
                            usb_node(exists=False),
                            {
                                "path": "/dev/hidraw0",
                                "kind": "hidraw",
                                "exists": True,
                                "readable": True,
                                "writable": True,
                            },
                        ]
                    )
                ]
            )
        )
        self.assertEqual(proc.returncode, 1)
        self.assertIn("no USB node with exists/readable/writable all true", proc.stderr)

    # 9. Malformed JSON -> exit 2, clear message, no traceback.
    def test_malformed_json(self):
        proc = self.run_parser("{not valid json", SERIAL)
        self.assertEqual(proc.returncode, 2)
        self.assertIn("malformed JSON", proc.stderr)
        self.assertNotIn("Traceback", proc.stderr)

    # 10. Malformed schema / candidate -> exit 2, no traceback.
    def test_malformed_candidate_schema(self):
        missing_nodes = candidate()
        del missing_nodes["nodes"]
        cases = [
            # document is not an object
            ("document not an object", "[1, 2, 3]"),
            # candidates not a list
            ("candidates not a list", json.dumps(doc("not-a-list"))),
            # matching candidate (serial present) omits a required field
            (
                "matching candidate lacks required field",
                json.dumps(doc([missing_nodes])),
            ),
            # matching candidate has non-list nodes
            ("nodes not a list", json.dumps(doc([candidate(nodes="nope")]))),
            # malformed node is the sole node (must not short-circuit success)
            ("node not an object", json.dumps(doc([candidate(nodes=["junk"])]))),
            # matching candidate has non-boolean accessible
            ("non-boolean accessible", json.dumps(doc([candidate(accessible="yes")]))),
            # matching usb node omits a required boolean field
            (
                "usb node missing exists field",
                json.dumps(
                    doc(
                        [
                            candidate(
                                nodes=[
                                    {
                                        "path": "/dev/bus/usb/001/017",
                                        "kind": "usb",
                                        "readable": True,
                                        "writable": True,
                                    }
                                ]
                            )
                        ]
                    )
                ),
            ),
            # matching usb node has non-boolean flag
            (
                "usb node non-boolean writable",
                json.dumps(
                    doc(
                        [
                            candidate(
                                nodes=[
                                    {
                                        "path": "/dev/bus/usb/001/017",
                                        "kind": "usb",
                                        "exists": True,
                                        "readable": True,
                                        "writable": "yes",
                                    }
                                ]
                            )
                        ]
                    )
                ),
            ),
        ]
        for label, payload in cases:
            with self.subTest(case=label):
                proc = self.run_parser(payload, SERIAL)
                self.assertEqual(proc.returncode, 2, proc.stderr)
                self.assertIn("FAIL:", proc.stderr)
                self.assertNotIn("Traceback", proc.stderr)

    # 11. Contract failure forwards top-level string remediation entries.
    def test_remediation_included_on_failure(self):
        remediation = [
            "NixOS:\n  imports = [ nix-nrf-dev.nixosModules.default ];",
            "Other Linux:\n  nix build .#udev-rules",
            42,  # non-string entries must be skipped
        ]
        proc = self.run_doc(doc([candidate(accessible=False)], remediation=remediation))
        self.assertEqual(proc.returncode, 1)
        self.assertIn("FAIL: preflight-xiao:", proc.stderr)
        self.assertIn("remediation:", proc.stderr)
        self.assertIn("imports = [ nix-nrf-dev.nixosModules.default ]", proc.stderr)
        self.assertIn("nix build .#udev-rules", proc.stderr)
        self.assertNotIn("42", proc.stderr)

    # 12. Usage errors -> exit 2.
    def test_usage_errors(self):
        proc = self.run_parser(json.dumps(doc([candidate()])))  # no serial arg
        self.assertEqual(proc.returncode, 2)
        self.assertIn("usage:", proc.stderr)
        proc = self.run_parser(
            json.dumps(doc([candidate()])), SERIAL, "extra-arg"
        )  # too many args
        self.assertEqual(proc.returncode, 2)
        proc = self.run_parser("", SERIAL)  # empty stdin
        self.assertEqual(proc.returncode, 2)
        self.assertIn("empty JSON document", proc.stderr)


if __name__ == "__main__":
    unittest.main()
