# west backend clean-room test

This test starts with empty home, creates west workspace and venv, then builds
Zephyr blinky using public `mkNrfShell { backend = "west"; ... }`.

1. Enters public west shell with `--ignore-env` and isolated `HOME`.
2. Runs `nix-nrf bootstrap --yes` to create workspace and version-local venv.
3. Re-enters shell and checks scoped `west` wrapper, `ZEPHYR_BASE`, and venv
   west.
4. Builds `xiao_nrf54l15/nrf54l15/cpuapp` sysbuild blinky and checks
   `zephyr.elf` and `domains.yaml`.

It never flashes hardware.

## Requirements

- `x86_64-linux` with Nix. Public west shell and Zephyr SDK must build or be
  cached.
- Network access to GitHub. Workspace setup downloads several GiB.
- At least 25 GiB free on isolated-home filesystem unless configured otherwise.
- First run takes tens of minutes.

## Run it

```bash
bash tests/west-backend/run.sh
```

Running it downloads several GiB. Get explicit approval before running it.

## Safety controls

- Default home is `mktemp -d -t nix-nrf-west-home-XXXXXXXX`. Set
  `NIX_NRF_WEST_CLEAN_HOME=/abs/path` to provide one.
- Caller home is never removed. Script-created home is removed on exit unless
  `NIX_NRF_WEST_CLEAN_KEEP=1`, after checking exact path and prefix.
- Script rejects non-absolute homes, `/`, `/home`, current real `$HOME`, repo
  root, and paths outside `/tmp` unless `NIX_NRF_WEST_ALLOW_OUTSIDE_TMP=1`.
  Existing caller home must be empty.
- It checks free space with `df` before download and fails below
  `NIX_NRF_WEST_MIN_FREE_GIB`, default `25`.
- `NIX_NRF_WEST_DRY_RUN=1` checks preconditions and prints plan without Nix
  shell entry or download.

## CI policy

No scheduled workflow runs this test. Normal CI uses fake-boundary checks:
`checks.west-bootstrap-tests`, `checks.west-versions-tests`,
`checks.west-backend-metadata`, `checks.west-backend-quoting`, and
`checks.west-shell-boundary`.

## Output and cleanup

Run prints clean-home path, free space, selected NCS release, lifecycle steps,
setup and build durations, installed size, SDK store path, compiler versions,
absence of nrfutil, and artifact checks. Script-created home is removed at end.
Caller-provided home remains unchanged.
