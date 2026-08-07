# West backend clean-room proof test

This directory contains the clean-room proof for the public west backend
(`mkNrfShell { backend = "west"; ... }`): it proves the hybrid installation
model end-to-end from an empty, isolated Linux home directory, using real
network downloads.

The test:

1. Enters the public west shell via the flake's public `lib.mkNrfShell`
   (`nix develop --impure --expr 'let flake = builtins.getFlake (toString
   ./.); in flake.lib.x86_64-linux.mkNrfShell { backend = "west"; ncsVersion
   = "v3.3.0"; }'`) with `--ignore-env` and an isolated `HOME`, so no
   developer state is inherited.
2. Runs `nix-nrf bootstrap --yes`, which creates the mutable west workspace
   (`west init` + `west update`) and the version-local venv (pip-installed
   west and the workspace requirement files) under the isolated home.
3. Re-enters the shell with the same isolated home and proves the scoped
   `west` wrapper resolves the workspace from `HOME`, requires bootstrap
   readiness, exports `ZEPHYR_BASE`, and execs the venv west.
4. Builds Zephyr basic blinky for `xiao_nrf54l15/nrf54l15/cpuapp` with
   sysbuild, and verifies the resulting `zephyr.elf` and `domains.yaml`.

It never flashes hardware.

## Requirements

- Linux x86_64 with a working Nix installation (the public west shell and the
  exact Zephyr SDK package must build or be cached).
- Network access to GitHub (west workspace, several GiB).
- At least 25 GiB free on the filesystem that hosts the isolated home
  (configurable, see below).
- Time: the first run initializes and updates the west workspace, installs
  the NCS Python requirements, then does a real sysbuild — expect tens of
  minutes.

## Manual invocation

```bash
bash tests/west-backend/run.sh
```

The script resolves the repository root from its own location and runs all
Nix commands there. It downloads several gigabytes on first use, so it must
be explicitly approved by the user before running.

## Safety controls

- The isolated home defaults to a script-created directory
  (`mktemp -d -t nix-nrf-west-home-XXXXXXXX`). A caller can supply
  `NIX_NRF_WEST_CLEAN_HOME=/abs/path` instead.
- Caller-provided homes are never removed. A script-created home is removed
  on exit (success or failure) unless `NIX_NRF_WEST_CLEAN_KEEP=1` is set, and
  only after the exact recorded path and `nix-nrf-west-home-` basename prefix
  are validated.
- The script rejects non-absolute homes, `/`, `/home`, the current user's
  real `$HOME`, the repository root, and any path outside `/tmp` unless
  `NIX_NRF_WEST_ALLOW_OUTSIDE_TMP=1` is explicitly set. A caller path that
  already exists must be empty.
- Before any download, the script checks free space on the home's filesystem
  with `df` and fails below `NIX_NRF_WEST_MIN_FREE_GIB` (default 25).
- `NIX_NRF_WEST_DRY_RUN=1` validates all preconditions and prints the plan
  without running `nix develop` or downloading anything — use it for a quick
  sanity check before committing to the large download.

## CI policy

This script is NOT part of normal CI and no scheduled workflow runs it: it is
a real multi-gigabyte network setup plus build, kept as local evidence. Normal
CI runs the fake-boundary gates instead (`checks.west-bootstrap-tests`,
`checks.west-versions-tests`, `checks.west-backend-metadata`,
`checks.west-backend-quoting`, `checks.west-shell-boundary`) — see
`docs/development/west-backend-status.md`.

## Output and cleanup

The run prints the clean-home path, the free-space result, the selected NCS
release, lifecycle step headers, elapsed setup/build seconds, the measured
installed size (`du -sh $HOME/ncs`), the SDK store path, compiler versions,
the absence of nrfutil, and the artifact assertions. All command output is
preserved as evidence. On completion, a script-created home is cleaned up; a
caller-provided home is left exactly as it was.
