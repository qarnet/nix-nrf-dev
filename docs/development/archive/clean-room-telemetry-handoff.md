# Clean-Room Resource Telemetry — Phase 8 Handoff

Status: historical. Phase 8 of
`docs/development/nixos-safety-init-testing-plan.md` was implemented as
instrumentation only and accepted on branch `feat/nixos-safety-and-init`
(commit `test(clean-room): add resource telemetry`). This phase adds the
telemetry instrumentation and claims no real measurements: the real retained
bootstrap/build measurement run remains separately approved and pending, and
the 25 GiB free-space guard is unchanged. This document records the
implementation shape; archived with the accepted plan.

## Goal

Replace ambiguous “25 GiB SDK size” language with measured clean-room evidence
while preserving the conservative 25 GiB preflight guard. A real retained run
must show mutable-home disk use, free-space deltas, Nix closure size, and actual
bootstrap/build time. This phase does not run that real download/build.

## Scope

Modify only:

- `tests/clean-room/run.sh`;
- `tests/clean-room/README.md`;
- `.github/workflows/clean-room.yml`;
- concise architecture/accepted-plan status documentation if needed.

Do not lower `NIX_NRF_CLEAN_MIN_FREE_GIB=25`. Do not schedule the workflow,
move it off `[self-hosted, nrf-hardware]`, combine it with udev tests, cache
Nordic mutable state, run hardware, or perform a real bootstrap/build during
implementation. Real execution still requires separate explicit approval.

## Telemetry contract

Add optional environment control:

```text
NIX_NRF_CLEAN_TELEMETRY_FILE
```

When set:

- must be an absolute path;
- parent must already exist and be a real directory;
- target must not already exist (no overwrite);
- target must remain outside `CLEAN_HOME`, because script-created homes are
  removed by default;
- script creates one Markdown report and appends measurements to it only from
  the script's telemetry functions.

Telemetry always prints to normal logs even when no file is requested.

Record exact integer KiB values as stable evidence and human-readable MiB/GiB
beside them. Use portable existing Linux tools (`df -kP`, `du -sk`, `date
+%s`, awk); do not add jq/bc/Python runtime requirements to the script.

Required fields/checkpoints:

- result: `passed`, `failed`, or `dry-run`;
- selected NCS release;
- clean-home path and filesystem mount point;
- configured minimum free-space guard (25 GiB default, unchanged);
- filesystem free KiB:
  - before bootstrap;
  - after bootstrap;
  - after build;
- minimum observed free KiB across available checkpoints;
- consumed free KiB from before-bootstrap to minimum observed;
- mutable path sizes:
  - `$CLEAN_HOME/ncs` after bootstrap and final;
  - `$CLEAN_HOME/.nrfutil` after bootstrap and final;
  - `$CLEAN_HOME/build` final;
  - total `$CLEAN_HOME` final;
- bootstrap elapsed seconds around the actual `nix-nrf bootstrap --yes`
  command only;
- build elapsed seconds around the actual `west build ...` command only;
- realized `devShells.x86_64-linux.clean-env-test` Nix closure output/path and
  `nix path-info -Sh` line, explicitly labeled separate from mutable-home disk
  use.

Unavailable future-stage fields on failure/dry-run must appear as `not
available`, not zero. Zero means a measured empty path only.

## Script implementation

Keep current home resolution, safety checks, empty-home precondition, free-space
failure, lifecycle commands, artifact assertions, and cleanup guard.

Add metric globals initialized to empty/not-available. Add narrow helpers:

- free KiB + mount parser using `df -kP`;
- path size in KiB using `du -sk` when path exists;
- KiB human formatter;
- telemetry emitter for logs and optional Markdown file;
- EXIT handler that captures original status, emits telemetry before cleanup,
  runs existing guarded cleanup, then preserves the original failure status
  (telemetry/cleanup failure may turn an otherwise successful run into failure,
  but must never hide an existing nonzero status).

Set a run-result marker to `dry-run` immediately before dry-run exit and
`passed` only after all lifecycle/artifact checks pass. Default remains
`failed`, so any early exit emits partial evidence where available.

### Timing

The inner `nix develop --command bash` processes own the actual bootstrap/build
commands. Inside each inner script:

- capture epoch seconds immediately before and after the target command;
- write the non-negative integer result to a metrics directory under
  `$CLEAN_HOME/.nix-nrf-clean-metrics` using an exact environment-provided
  path;
- outer script validates/reads that integer after the lifecycle succeeds.

Do not replace command timing with whole `nix develop` lifecycle timing.

### Checkpoints

1. Existing free-space check becomes the before-bootstrap measurement and
   guard.
2. Immediately after lifecycle 1 succeeds, capture free-after-bootstrap plus
   NCS and `.nrfutil` sizes.
3. Immediately after lifecycle 2/artifact assertions succeed, capture
   free-after-build plus final NCS, `.nrfutil`, build-tree, and total-home sizes.
4. After shell realization, obtain the closure safely:

   ```sh
   shell_path="$(nix build --no-link --print-out-paths \
     .#devShells.x86_64-linux.clean-env-test)"
   shell_closure_line="$(nix path-info -Sh "$shell_path")"
   ```

   `nix path-info` alone fails if output is not realized; the explicit build is
   required. This realizes fixed Nix closure inputs only. It must not run
   `nix-nrf bootstrap`, `west`, or any Nordic install.

Compute minimum/consumed only from checkpoints actually recorded.

### Dry run

`NIX_NRF_CLEAN_DRY_RUN=1` must still run no Nix command and no download. It
records before-free-space/mount/guard, reports future metrics as unavailable,
prints the expanded telemetry plan, sets result `dry-run`, emits optional
Markdown, and safely cleans its script-created home.

## Workflow

Keep `.github/workflows/clean-room.yml` manual-only and self-hosted. Add
top-level read-only repository permission if absent:

```yaml
permissions:
  contents: read
```

For the run step, set a unique telemetry path under `${{ runner.temp }}` using
run ID + attempt, for example:

```text
${{ runner.temp }}/nix-nrf-clean-room-<run>-<attempt>.md
```

Pass it as `NIX_NRF_CLEAN_TELEMETRY_FILE`; keep
`NIX_NRF_CLEAN_MIN_FREE_GIB: '25'`. Do not set `NIX_NRF_CLEAN_KEEP`.

Add an `if: always()` summary step:

- append report to `$GITHUB_STEP_SUMMARY` when present/nonempty;
- otherwise append an explicit “telemetry unavailable; inspect run logs” note;
- remove only the exact guarded runner-temp telemetry path afterward so a
  persistent self-hosted runner does not accumulate reports.

Logs plus workflow summary are retained evidence. No artifact upload or Nordic
state cache is required.

## Documentation

Update `tests/clean-room/README.md`:

- 25 GiB is a conservative free-space guard covering SDK source, toolchain,
  nrfutil state, extraction/temp overhead, build tree, possible same-filesystem
  Nix closure realization, and safety margin — not measured SDK-only size;
- list exact telemetry/checkpoints and closure separation;
- document optional report path and no-overwrite/outside-home rules;
- explain partial/dry-run values;
- state guard cannot be lowered until at least one complete retained run
  establishes observed peak plus margin;
- workflow summary retains the report while mutable home remains cleaned.

Update `docs/development/architecture.md` only if needed to mention telemetry
ownership. Update accepted-plan header after verification: Phase 8 complete
pending review; Phase 9 next.

## Verification

No real bootstrap/build.

```sh
NIX_NRF_CLEAN_DRY_RUN=1 bash tests/clean-room/run.sh
bash -n tests/clean-room/run.sh
nix flake check --all-systems --no-build -L
nix flake check -L
```

Also run one safe telemetry-file dry run using a script-created temporary
directory outside the clean home. Assert:

- report exists and says `dry-run`;
- before-free/mount/25-GiB guard are present;
- after-bootstrap/build, mutable sizes, elapsed values, and closure are `not
  available`;
- script-created clean home was removed;
- pre-existing telemetry target is rejected without overwrite;
- relative telemetry path and telemetry path inside clean home are rejected;
- caller-provided clean home remains untouched except for normal dry-run
  behavior (no Nix/download).

Run actionlint/shellcheck through normal hooks. Inspect workflow remains
manual-only/self-hosted and contains no install command beyond the existing
script invocation.

Implement without commit/push and return for review. Escalate rather than run a
real bootstrap, lower the guard, weaken cleanup, or add unapproved cache/state
retention.
