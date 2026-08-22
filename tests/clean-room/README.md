# Clean-room bootstrap and build test

This test starts with an empty, isolated Linux home directory and uses real
Nordic downloads.

1. Enters `nix develop .#clean-env-test` with `--ignore-env` and isolated
   `HOME`.
2. Runs `nix-nrf bootstrap --yes` for NCS `v3.3.0` and selected toolchain.
3. Re-enters shell and checks that `ZEPHYR_BASE` comes from isolated install.
4. Builds Zephyr basic blinky for `xiao_nrf54l15/nrf54l15/cpuapp` with
   sysbuild, then checks `zephyr.elf` and `domains.yaml`.

It never flashes hardware.

## Requirements

- Linux with working Nix installation. `clean-env-test` shell and packaged
  nrfutil must build or come from cache.
- Network access to Nordic endpoints. Download is several GiB.
- At least 25 GiB free on isolated-home filesystem unless configured otherwise.
- First run can take tens of minutes. Workflow timeout is 120 minutes.

## Free-space guard

`NIX_NRF_CLEAN_MIN_FREE_GIB` defaults to `25`. It covers SDK source, toolchain
archives and extraction, nrfutil state, build tree, possible same-filesystem
Nix closure realization, and margin. It is not a measured SDK-only size.

Do not lower value until retained real run with `NIX_NRF_CLEAN_KEEP=1` records
peak use plus margin.

## Run it

```bash
bash tests/clean-room/run.sh
```

Script resolves repository root from its own path.

## Safety controls

- Default home is script-created `mktemp -d -t nix-nrf-clean-home-XXXXXXXX`.
  Set `NIX_NRF_CLEAN_HOME=/abs/path` to provide one.
- Script never removes caller-provided home. It removes script-created home on
  exit unless `NIX_NRF_CLEAN_KEEP=1`, after checking exact path and prefix.
- Script rejects non-absolute homes, `/`, `/home`, current real `$HOME`,
  repository root, and paths outside `/tmp` unless
  `NIX_NRF_CLEAN_ALLOW_OUTSIDE_TMP=1`. Existing caller home must be empty.
- Before downloads, script runs `df` on home filesystem and fails below guard.
- Shell hook creates `~/.nrfutil` state at entry. Empty-home check happens
  before first shell entry.
- `NIX_NRF_CLEAN_DRY_RUN=1` validates preconditions and prints plan without
  entering Nix shell or downloading. It records first free-space checkpoint
  and reports later fields as `not available`.
- Telemetry runs before cleanup. Telemetry or cleanup error can fail otherwise
  successful run. Original nonzero status is never hidden.

## Telemetry

Script always writes these values to logs:

- result, selected NCS release, clean-home path, mount point, and configured
  guard;
- free KiB before bootstrap, after bootstrap, after build, minimum observed,
  and consumed KiB;
- sizes of `$CLEAN_HOME/ncs`, `$CLEAN_HOME/.nrfutil`, build tree, and home;
- elapsed seconds for `nix-nrf bootstrap --yes` and `west build` only;
- realized `clean-env-test` Nix closure path and `nix path-info -Sh` size.

Future-stage fields are `not available`, never zero. Zero means measured empty
path.

Set `NIX_NRF_CLEAN_TELEMETRY_FILE=/abs/path/report.md` to write one Markdown
report. Parent must already exist and not be symlink. Target must be absolute,
new, outside clean home, and not a symlink. Bash `noclobber` reserves it before
work starts. Telemetry functions alone populate that path, including partial
failure and dry-run reports.

## Workflow and cleanup

`.github/workflows/clean-room.yml` runs manually on `nrf-hardware` runner. It
has no schedule, hardware, probe, or flashing step. Normal PR CI never runs it
or downloads SDK bundles.

Each dispatch writes telemetry under unique `${{ runner.temp }}` path. An
`if: always()` step appends nonempty report to job summary, otherwise writes
telemetry-unavailable note, then removes only that path.

On normal cleanup script removes script-created metrics directory and home.
Caller-provided home remains. `NIX_NRF_CLEAN_KEEP=1` retains clean-room state
for diagnosis.
