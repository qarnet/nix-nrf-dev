#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
#
# tests/fixtures/west-workspace.py — stdlib-only fake-ready west workspace
# creator shared by the west quoting and shell-boundary gates
# (nix/flake/checks/west.nix). Replaces the duplicated inline shell creation
# blocks: both modes create the same ready structure (workspace manifest,
# requirement roots, executable fake venv python/pip/west), differing only in
# the fake executables' behavior.
#
#   west-workspace.py --workspace PATH --mode stdout
#     python/pip exit 0; west prints "West version: v1.4.0" for --version,
#     otherwise "FAKE_WEST argv=... ZEPHYR_BASE=..." (quoting gate).
#
#   west-workspace.py --workspace PATH --mode log
#     python/pip/west append exact argv/environment lines to $HOME/venv.log;
#     west prints "West version: v1.4.0" for --version (boundary gate).
#
# Safety contract: resolves the workspace to an absolute path, refuses `/`,
# the current HOME, existing non-empty directories, and symlink escapes, and
# creates files only inside the requested workspace. Never deletes, runs
# network, invokes pip/west, or touches real SDK state.

import argparse
import os
import sys

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

STDOUT_EXECUTABLES = {
    "python": "#!/bin/sh\nexit 0\n",
    "pip": "#!/bin/sh\nexit 0\n",
    "west": (
        "#!/bin/sh\n"
        'if [ "$1" = "--version" ]; then\n'
        '  echo "West version: v1.4.0"\n'
        "  exit 0\n"
        "fi\n"
        'echo "FAKE_WEST argv=$* ZEPHYR_BASE=$ZEPHYR_BASE"\n'
    ),
}

LOG_EXECUTABLES = {
    "python": '#!/bin/sh\necho "python argv=$*" >> "$HOME/venv.log"\nexit 0\n',
    "pip": '#!/bin/sh\necho "pip argv=$*" >> "$HOME/venv.log"\nexit 0\n',
    "west": (
        "#!/bin/sh\n"
        'echo "west argv=$* ZEPHYR_BASE=${ZEPHYR_BASE:-} ZEPHYR_TOOLCHAIN_VARIANT='
        "${ZEPHYR_TOOLCHAIN_VARIANT:-} ZEPHYR_SDK_INSTALL_DIR=${ZEPHYR_SDK_INSTALL_DIR:-} "
        'PATH=$PATH" >> "$HOME/venv.log"\n'
        'if [ "$1" = "--version" ]; then\n'
        'echo "West version: v1.4.0"\n'
        "exit 0\n"
        "fi\n"
        "exit 0\n"
    ),
}


def _refuse(message):
    print(f"west-workspace.py: {message}", file=sys.stderr)
    sys.exit(1)


def _validate(workspace):
    ws = os.path.abspath(workspace)
    if ws == os.path.abspath(os.sep):
        _refuse(f"refusing to create the filesystem root: {ws}")
    if ws == os.path.abspath(os.path.expanduser("~")):
        _refuse(f"refusing to create the current HOME: {ws}")
    if os.path.exists(ws) and os.listdir(ws):
        _refuse(f"refusing existing non-empty directory: {ws}")
    # Symlink escape guard: the symlink-resolved location must stay inside
    # the requested workspace.
    effective = os.path.realpath(ws)
    if effective != ws and not effective.startswith(ws + os.sep):
        _refuse(
            f"refusing symlink escape outside requested workspace: {ws} -> {effective}"
        )
    return ws


def _write(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(content)


def create(ws, mode):
    executables = STDOUT_EXECUTABLES if mode == "stdout" else LOG_EXECUTABLES
    for rel, content in BASE_FILES.items():
        _write(os.path.join(ws, rel), content)
    for name, content in executables.items():
        path = os.path.join(ws, ".venv", "bin", name)
        _write(path, content)
        os.chmod(path, 0o755)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--mode", required=True, choices=["stdout", "log"])
    args = parser.parse_args()
    ws = _validate(args.workspace)
    create(ws, args.mode)


if __name__ == "__main__":
    main()
