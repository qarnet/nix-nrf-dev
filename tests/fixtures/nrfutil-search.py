#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
#
# Test-only deterministic stand-in for
# `nrfutil sdk-manager search --json --skip-overhead`. Packaged as the fake
# nrfutilPackage for checks.init-project-tests
# (nix/flake/checks/init-project.nix) and reused by the raw-source unit suite
# (tests/unit/test_nix_nrf_init_project.py).
#
# Contract:
#   - argv must be exactly: sdk-manager search --json --skip-overhead.
#     Anything else prints the offending argv to stderr and exits 1.
#   - Every invocation is logged as one JSON argv array to
#     $NIX_NRF_INIT_FAKE_LOG (when set), appending.
#   - When $NIX_NRF_INIT_FAKE_SEARCH_EXIT is set to a nonzero integer, print
#     $NIX_NRF_INIT_FAKE_SEARCH_STDERR (or a default diagnostic) to stderr
#     and exit with that code. This simulates remote-index or network failure.
#   - Otherwise emit the contents of $NIX_NRF_INIT_FAKE_SEARCH_FILE when
#     set, else a deterministic built-in default payload (one stable nrf
#     entry, v3.3.0).
#   - stdout carries exactly the search JSON; no other stdout output.
#
# The fake never touches the network, sdk-manager state, or the filesystem
# outside its declared environment.

import json
import os
import sys

DEFAULT_PAYLOAD = {
    "alerts": [],
    "entries": [
        {
            "sdkStatus": {"local": "none", "remote": "available"},
            "sdkType": "nrf",
            "sdkVersion": "v3.3.0",
            "tags": ["stable"],
            "toolchains": [
                {
                    "status": {"local": "none", "remote": "available"},
                    "version": "v3.3.0",
                }
            ],
        }
    ],
}


def main():
    argv = sys.argv[1:]
    if argv != ["sdk-manager", "search", "--json", "--skip-overhead"]:
        print(
            "fake nrfutil search: unexpected argv: " + json.dumps(argv),
            file=sys.stderr,
        )
        return 1
    log = os.environ.get("NIX_NRF_INIT_FAKE_LOG")
    if log:
        with open(log, "a") as fh:
            fh.write(json.dumps(argv) + "\n")
    exit_code = os.environ.get("NIX_NRF_INIT_FAKE_SEARCH_EXIT", "")
    if exit_code:
        try:
            code = int(exit_code)
        except ValueError:
            code = 1
        if code != 0:
            detail = os.environ.get("NIX_NRF_INIT_FAKE_SEARCH_STDERR")
            if detail:
                print(detail, file=sys.stderr)
            else:
                print(
                    "fake nrfutil search: simulated sdk-manager failure",
                    file=sys.stderr,
                )
            return code
    search_file = os.environ.get("NIX_NRF_INIT_FAKE_SEARCH_FILE")
    if search_file:
        with open(search_file) as fh:
            sys.stdout.write(fh.read())
    else:
        print(json.dumps(DEFAULT_PAYLOAD))
    return 0


if __name__ == "__main__":
    sys.exit(main())
