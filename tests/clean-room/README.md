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

## The 25 GiB free-space guard

`NIX_NRF_CLEAN_MIN_FREE_GIB` (default `25`) is a **conservative end-to-end
free-space guard**, not a measured SDK-only size. It covers SDK source,
toolchain archives and extraction/temp overhead, nrfutil state, the build
tree, possible same-filesystem Nix closure realization (including the
realized `clean-env-test` shell closure), and a safety margin.

The guard is **not lowered** until at least one complete retained run
(`NIX_NRF_CLEAN_KEEP=1` on a real bootstrap) establishes the observed peak
free-space consumption plus margin. Until then, the 25 GiB default stays.

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
  sanity check in CI or before committing to a large download. It records the
  before-bootstrap free space, mount point, and guard, sets result `dry-run`,
  and reports every future-stage field as `not available`.
- On exit, telemetry is emitted **before** cleanup, and the original exit
  status is preserved: a telemetry/cleanup failure may turn an otherwise
  successful run into failure, but never hides an existing nonzero status.

## Resource telemetry

The script records exact evidence for a real retained run and always prints
it to the run logs. The complete schema is also printed to the logs on every
exit — including `not available` for any field a checkpoint did not reach —
so nothing is silently omitted even without a report file:

- result: `passed`, `failed`, or `dry-run`;
- selected NCS release;
- clean-home path and filesystem mount point;
- configured minimum free-space guard (25 GiB default, unchanged);
- filesystem free KiB before bootstrap, after bootstrap, and after build
  (exact integer KiB with human-readable MiB/GiB beside it, via `df -kP`);
- minimum observed free KiB and consumed free KiB (before-bootstrap to
  minimum), computed only from checkpoints actually recorded — at least the
  before-bootstrap checkpoint plus one later checkpoint are required,
  otherwise both report `not available`;
- mutable path sizes via `du -sk`: `$CLEAN_HOME/ncs` and
  `$CLEAN_HOME/.nrfutil` after bootstrap and final, `$CLEAN_HOME/build`
  final, and total `$CLEAN_HOME` final;
- bootstrap elapsed seconds around the actual `nix-nrf bootstrap --yes`
  command only, and build elapsed seconds around the actual
  `west build ...` command only — captured as epoch seconds (`date +%s`) by
  the inner lifecycle shells and written to
  `$CLEAN_HOME/.nix-nrf-clean-metrics/`; the outer script validates and reads
  the non-negative integers after the lifecycle succeeds (never whole
  `nix develop` lifecycle timing);
- the realized `devShells.x86_64-linux.clean-env-test` Nix closure output path
  and `nix path-info -Sh` size line, explicitly labeled **separate from
  mutable-home disk use**: `nix path-info` alone fails if output is not
  realized, so the script first runs
  `nix build --no-link --print-out-paths
  .#devShells.x86_64-linux.clean-env-test`. This realizes fixed Nix closure
  inputs only and never runs bootstrap, west, or any Nordic install.

Fields that a future-stage checkpoint did not reach (failure or dry-run)
appear as `not available`, never zero. Zero means a measured empty path only.

### Optional Markdown report

Set `NIX_NRF_CLEAN_TELEMETRY_FILE=/abs/path/report.md` to also write one
Markdown report. The script validates the report path before reserving it and
before any Nix/download lifecycle step (clean-home resolution and home safety
checks may already have run):

- must be an absolute path;
- parent must already exist and be a real directory (symlinked parents are
  rejected);
- target must not already exist in any form — regular file, symlink to an
  existing file, or dangling symlink (no overwrite, never writes through a
  symlink);
- target must remain outside `CLEAN_HOME` (script-created homes are removed
  by default, so an inside-home report would be deleted with it).

The target is then **exclusively reserved** with Bash `noclobber` during
validation, so a racing or pre-existing file is rejected instead of
overwritten and a caller file is never touched; the emitter later populates
exactly that reserved file at exit. If a later check fails after reservation
(for example the free-space guard), the reserved file receives the partial
failure report. The report contains the complete measurement list above, is
written only by the script's telemetry functions, and is produced even for
partial and dry-run results (with `not available` placeholders). Telemetry
always prints to the run logs even when no file is requested.

## Workflow

`.github/workflows/clean-room.yml` runs this script on a self-hosted runner
(`nrf-hardware` label). It is **manual-only** (`workflow_dispatch`) with no
schedule and no hardware/probe/flashing step, because a cold multi-gigabyte
SDK/toolchain bootstrap is too large and slow for normal PR CI. Normal PR CI
(`.github/workflows/ci.yml`) is not part of this test and never downloads
SDK/toolchain bundles. The workflow declares top-level read-only
`contents: read` permissions, keeps `NIX_NRF_CLEAN_MIN_FREE_GIB: '25'`, and
never sets `NIX_NRF_CLEAN_KEEP`.

For each dispatch, the run step passes a unique telemetry path under
`${{ runner.temp }}` derived from the run ID and attempt:
`nix-nrf-clean-room-<run>-<attempt>.md`. An `if: always()` summary step
appends the report to `$GITHUB_STEP_SUMMARY` when present and nonempty (or an
explicit "telemetry unavailable; inspect run logs" note otherwise), then
removes only that exact runner-temp path so a persistent self-hosted runner
does not accumulate reports. Logs plus the workflow summary are the retained
evidence; there is no artifact upload and no Nordic state cache.

## Output and cleanup

The run prints the clean-home path, the free-space result, the selected NCS
release, lifecycle step headers, telemetry metrics (free KiB, mutable-path
sizes, elapsed seconds, Nix closure), and the artifact assertions. On
non-KEEP cleanup, the script-created metrics directory under
`$CLEAN_HOME/.nix-nrf-clean-metrics` is removed (it holds only script
output); a script-created home is then removed entirely. A caller-provided
home is **never removed**: after a real run it retains the generated
SDK/nrfutil/build state, while a dry run leaves it empty. With
`NIX_NRF_CLEAN_KEEP=1`, clean-room state is retained at `$CLEAN_HOME` for
diagnosis. The workflow summary retains the telemetry report while the
mutable home remains cleaned.
