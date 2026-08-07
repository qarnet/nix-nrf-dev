#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
#
# tests/hardware/preflight_xiao.py — hardware harness consumer contract for
# `nix-nrf doctor --json`.
#
# Before any OpenOCD probe session, NCS build, flash, or mutation, the
# hardware harness must prove the real XIAO probe (serial 8EE9B3FF) is
# usable through the explicit CMSIS-DAP v2 bulk USB transport. This script
# is that proof: a pure stdin-to-result boundary that consumes exactly one
# JSON document (the `nix-nrf doctor --json` output) and asserts the exact
# consumer contract:
#
#   - exactly one candidate with the requested serial (duplicate = failure);
#   - type == "cmsis-dap";
#   - accessible is true;
#   - access_method == "usb" (explicit v2 bulk, not v1 HID);
#   - fallback is false (no legacy USB fallback);
#   - at least one nodes[] item with kind == "usb" whose exists, readable,
#     and writable are all exactly true.
#
# It never invokes doctor or OpenOCD itself, never opens probe nodes, and
# never mutates anything — it only validates the JSON contract. Devnum,
# /dev/bus/usb paths, hidraw paths, and hidraw permissions are deliberately
# NOT asserted: those change across machines and may become more permissive.
#
# Usage: python3 preflight_xiao.py <serial>   (JSON document on stdin)
# Exit codes:
#   0  contract satisfied — XIAO usable via explicit CMSIS-DAP v2 bulk USB
#   1  valid JSON but contract failure (probe missing, duplicate, blocked,
#      wrong transport, fallback, or no accessible USB node)
#   2  usage error, malformed JSON, or malformed schema
#
# Contract failures print FAIL lines to stderr and forward any string
# entries from the top-level "remediation" list as follow-up context.
# Malformed input is handled explicitly with exit 2; programming defects
# are left to traceback and fail loudly rather than being normalized into
# input errors.

import json
import sys

PROG = "preflight-xiao"

USAGE = f"usage: {PROG}.py <serial>   (JSON document on stdin)"


def fail(msg, remediation=(), code=1):
    """Print a FAIL line plus optional remediation context; never raises."""
    print(f"FAIL: {PROG}: {msg}", file=sys.stderr)
    for item in remediation:
        print(f"  remediation: {item}", file=sys.stderr)
    return code


def parse_document(raw):
    """(document, error) — malformed input yields (None, message)."""
    if not raw.strip():
        return None, "empty JSON document on stdin"
    try:
        return json.loads(raw), None
    except json.JSONDecodeError as exc:
        return None, f"malformed JSON on stdin: {exc}"


def remediation_strings(doc):
    """Top-level remediation entries, string values only (contract context)."""
    items = doc.get("remediation") if isinstance(doc, dict) else None
    if not isinstance(items, list):
        return []
    return [item for item in items if isinstance(item, str)]


def check_schema(doc):
    """Structural validation; returns (error_message, remediation) — error is
    None when the document shape is usable. Broken shape is exit 2, not a
    hardware verdict."""
    if not isinstance(doc, dict):
        return "JSON document must be an object", []
    remediation = remediation_strings(doc)
    hardware = doc.get("hardware")
    if not isinstance(hardware, dict):
        return "missing or non-object 'hardware'", remediation
    candidates = hardware.get("candidates")
    if not isinstance(candidates, list):
        return "missing or non-list 'hardware.candidates'", remediation
    for i, cand in enumerate(candidates):
        if not isinstance(cand, dict):
            return f"candidate #{i} is not an object", remediation
    return None, remediation


def candidate_contract(cand, serial, remediation):
    """Assert the exact consumer contract for the single matching candidate.
    Returns an exit code (1 contract failure, 2 malformed candidate)."""
    for key in ("type", "accessible", "access_method", "fallback", "nodes"):
        if key not in cand:
            return fail(
                f"candidate serial {serial} lacks required field '{key}'", [], code=2
            )
    if not isinstance(cand["type"], str):
        return fail(f"candidate serial {serial} 'type' is not a string", [], code=2)
    if cand["type"] != "cmsis-dap":
        return fail(
            f"candidate serial {serial} is type {cand['type']!r}, expected 'cmsis-dap'",
            remediation,
        )
    if not isinstance(cand["accessible"], bool):
        return fail(
            f"candidate serial {serial} 'accessible' is not a boolean", [], code=2
        )
    if cand["accessible"] is not True:
        return fail(f"candidate serial {serial} is not accessible", remediation)
    if not isinstance(cand["access_method"], str):
        return fail(
            f"candidate serial {serial} 'access_method' is not a string", [], code=2
        )
    if cand["access_method"] != "usb":
        return fail(
            f"candidate serial {serial} uses access method {cand['access_method']!r}, "
            "expected 'usb' (explicit CMSIS-DAP v2 bulk USB)",
            remediation,
        )
    if not isinstance(cand["fallback"], bool):
        return fail(
            f"candidate serial {serial} 'fallback' is not a boolean", [], code=2
        )
    if cand["fallback"] is not False:
        return fail(
            f"candidate serial {serial} relies on the legacy USB fallback",
            remediation,
        )
    nodes = cand["nodes"]
    if not isinstance(nodes, list):
        return fail(f"candidate serial {serial} 'nodes' is not a list", [], code=2)
    for i, node in enumerate(nodes):
        if not isinstance(node, dict):
            return fail(
                f"candidate serial {serial} node #{i} is not an object", [], code=2
            )
        if node.get("kind") != "usb":
            continue
        for key in ("exists", "readable", "writable"):
            if key not in node:
                return fail(
                    f"candidate serial {serial} usb node lacks required field '{key}'",
                    [],
                    code=2,
                )
            if not isinstance(node[key], bool):
                return fail(
                    f"candidate serial {serial} usb node '{key}' is not a boolean",
                    [],
                    code=2,
                )
        if (
            node["exists"] is True
            and node["readable"] is True
            and node["writable"] is True
        ):
            return None
    return fail(
        f"candidate serial {serial} has no USB node with exists/readable/writable all true",
        remediation,
    )


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    if len(args) != 1:
        return fail(
            f"expected exactly one argument: the probe serial\n{USAGE}", [], code=2
        )
    serial = args[0]
    if not serial:
        return fail("serial must be non-empty", [], code=2)

    doc, error = parse_document(sys.stdin.read())
    if error is not None:
        return fail(error, [], code=2)
    if not isinstance(doc, dict):
        return fail("JSON document must be an object", [], code=2)
    error, remediation = check_schema(doc)
    if error is not None:
        return fail(error, [], code=2)

    candidates = doc["hardware"]["candidates"]
    matches = [c for c in candidates if c.get("serial") == serial]
    if not matches:
        return fail(f"no candidate with serial {serial}", remediation)
    if len(matches) > 1:
        return fail(
            f"{len(matches)} candidates with serial {serial} (expected exactly one)",
            remediation,
        )

    code = candidate_contract(matches[0], serial, remediation)
    if code is not None:
        return code

    product = matches[0].get("product")
    label = product if isinstance(product, str) and product else "cmsis-dap"
    print(f"OK: XIAO {serial} usable via explicit CMSIS-DAP v2 bulk USB ({label})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
