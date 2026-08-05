# Clean-room bootstrap and build test

This directory contains a clean-room test for nix-nrf-dev: it proves
end-to-end behavior from an empty, isolated Linux home directory, using real
Nordic downloads.

The test:

1. Enters the project shell (`nix develop .#clean-env-test`) with `--ignore-env`
   and an isolated `HOME`, so no developer nRF Util/NCS state is inherited.
2. Runs `nix-nrf bootstrap --yes` to install NCS v3.3.0 plus the selected
   toolchain into the isolated home.
3. Re-enters the shell with the same isolated home and proves it derives
   `ZEPHYR_BASE` from the isolated installation.
4. Builds Zephyr basic blinky for `xiao_nrf54l15/nrf54l15/cpuapp` with
   sysbuild, and verifies the resulting `zephyr.elf` and `domains.yaml`.

It never flashes hardware.

## Requirements

- Linux with a working Nix installation (the flake's `clean-env-test` shell
  and packaged nrfutil must build or be cached).
- Network access to Nordic's download endpoints (several GiB).
- At least 25 GiB free on the filesystem that hosts the isolated home
  (configurable, see below).
- Time: the first run downloads and installs the SDK and toolchain, then does
  a real sysbuild — expect tens of minutes (see the workflow's 120-minute
  timeout).

## Manual invocation

```bash
bash tests/clean-room/run.sh
```

The script resolves the repository root from its own location and runs all
Nix commands there.

## Safety controls

- The isolated home defaults to a script-created directory
  (`mktemp -d -t nix-nrf-clean-home-XXXXXXXX`). A caller can supply
  `NIX_NRF_CLEAN_HOME=/abs/path` instead.
- Caller-provided homes are never removed. A script-created home is removed
  on exit (success or failure) unless `NIX_NRF_CLEAN_KEEP=1` is set, and only
  after the exact recorded path and `nix-nrf-clean-home-` basename prefix are
  validated.
- The script rejects non-absolute homes, `/`, `/home`, the current user's
  real `$HOME`, the repository root, and any path outside `/tmp` unless
  `NIX_NRF_CLEAN_ALLOW_OUTSIDE_TMP=1` is explicitly set. A caller path that
  already exists must be empty.
- Before any download, the script checks free space on the home's filesystem
  with `df` and fails below `NIX_NRF_CLEAN_MIN_FREE_GIB` (default 25).
- The shell hook's read-only `nix-nrf bootstrap --check` query makes nrfutil
  create its own `~/.nrfutil` state directory inside the isolated home at
  shell entry; the emptiness assertion applies **before** the first entry,
  not inside it.
- `NIX_NRF_CLEAN_DRY_RUN=1` validates all preconditions and prints the plan
  without running `nix develop` or downloading anything — useful for a quick
  sanity check in CI or before committing to a large download.

## Workflow

`.github/workflows/clean-room.yml` runs this script on a self-hosted runner
(`nrf-hardware` label). It is **manual-only** (`workflow_dispatch`) with no
schedule and no hardware/probe/flashing step, because a cold multi-gigabyte
SDK/toolchain bootstrap is too large and slow for normal PR CI. Normal PR CI
(`.github/workflows/ci.yml`) is not part of this test and never downloads
SDK/toolchain bundles.

## Output and cleanup

The run prints the clean-home path, the free-space result, the selected NCS
release, lifecycle step headers, elapsed bootstrap/build seconds, the
measured installed size (`du -sh $HOME/ncs`), and the artifact assertions.
All command output is preserved as evidence. On completion, a script-created
home is cleaned up; a caller-provided home is left exactly as it was.
