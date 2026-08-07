# Clean-Room Bootstrap and Blinky Build Handoff

## Goal

Prove end-to-end behavior from an empty Linux home directory:

1. Enter project shell without inheriting developer nRF Util/NCS state.
2. Run `nix-nrf bootstrap --yes` and install NCS v3.3.0 plus selected toolchain.
3. Re-enter shell with same isolated home.
4. Prove shell derives `ZEPHYR_BASE` from isolated installation.
5. Build Zephyr basic blinky for `xiao_nrf54l15/nrf54l15/cpuapp` with sysbuild.
6. Verify resulting ELF artifact.

This phase includes real multi-gigabyte Nordic downloads. User explicitly
approved download and build on 2026-08-05.

## Grounding

### Isolation interface

Installed Nix 2.34.8 supports:

```text
nix develop --ignore-env --set-env-var HOME <path> --command ...
```

`--ignore-env` clears inherited environment; `--set-env-var HOME` supplies only
the isolated home before devshell variables/hooks are applied.

### Disk budget

Current filesystem has approximately 94 GiB free. Existing NCS v3.3.0 reports
74 GiB only because it contains about 65 GiB of generated BabbleSim results;
excluding generated results/doc output gives approximately 5 GiB SDK source.
Installed toolchain is approximately 4.3 GiB. A guarded 25 GiB free-space
minimum provides margin for archives, extraction, and build output.

### Build target and artifacts

Installed NCS v3.3.0 source verifies:

- sample: `zephyr/samples/basic/blinky`;
- board target:
  `xiao_nrf54l15/nrf54l15/cpuapp`, defined by
  `zephyr/boards/seeed/xiao_nrf54l15/xiao_nrf54l15_nrf54l15_cpuapp.yaml`;
- board metadata sets `sysbuild: true`, so `--sysbuild` is required;
- sysbuild default image name is `blinky`;
- primary artifact:
  `<build>/blinky/zephyr/zephyr.elf`.

Exact build:

```bash
west build -p always \
  -b xiao_nrf54l15/nrf54l15/cpuapp \
  --sysbuild \
  -d <build-dir> \
  "$ZEPHYR_BASE/samples/basic/blinky"
```

### CI constraints

Cold SDK/toolchain bootstrap is too large and slow for normal PR CI. Existing
self-hosted runner label is `[self-hosted, nrf-hardware]`. Add a separate
manual-only workflow using that known runner; do not add a schedule yet and do
not alter normal `.github/workflows/ci.yml` to download SDK bundles.

## Exact implementation

### `tests/clean-room/run.sh`

Add executable Bash script with `set -euo pipefail`. Resolve repository root
from script location and run all Nix commands there.

Environment controls:

- `NIX_NRF_CLEAN_HOME`: optional absolute path. If omitted, create a dedicated
  directory with `mktemp -d -t nix-nrf-clean-home-XXXXXXXX`.
- `NIX_NRF_CLEAN_KEEP=1`: retain script-created temporary home after run or
  failure for diagnosis. Any other value cleans a script-created home on exit.
- Caller-provided home is never automatically removed.
- `NIX_NRF_CLEAN_MIN_FREE_GIB`: optional integer, default `25`.

Safety rules:

1. Reject non-absolute caller home.
2. Reject `/`, `/home`, current user's real `$HOME`, repository root, or any
   path outside `/tmp` unless caller explicitly supplies
   `NIX_NRF_CLEAN_ALLOW_OUTSIDE_TMP=1`.
3. If caller path exists, require it to be empty. Never remove/reset an
   existing path.
4. Cleanup only a path created by this script, only after validating it matches
   script's recorded exact path and basename prefix `nix-nrf-clean-home-`.
5. Check free space on parent filesystem before bootstrap using `df`; fail
   before any download when below configured threshold.

Print clean-home path, free-space result, selected release, and lifecycle step
headers. Preserve command output for evidence.

### Lifecycle 1: cold explicit bootstrap

Before first `nix develop`, assert isolated home is empty and has neither
`.nrfutil` nor `ncs`.

Run:

```bash
nix develop .#clean-env-test \
  --ignore-env \
  --set-env-var HOME "$clean_home" \
  --command bash -ceu '<bootstrap assertions>'
```

Inside command:

1. Assert `HOME` equals expected clean-home path passed through a second
   explicit environment variable such as `NIX_NRF_EXPECTED_HOME`.
2. Assert `nix-nrf`, `nrfutil`, and `west` exist.
3. Run `nix-nrf bootstrap --yes`.
4. Run read-only
   `nix-nrf bootstrap --check --print-sdk-path`, capture one line.
5. Assert SDK path equals `$HOME/ncs/v3.3.0` and contains `zephyr/`.
6. Assert at least one toolchain directory exists under `$HOME/ncs/toolchains`.

Do not pass `--install-dir`; acceptance proves Nordic's default root follows
isolated HOME. Do not use or copy existing `/home/thomas-workstation/ncs`.

### Lifecycle 2: fresh shell and real build

Run a second independent `nix develop` process with same `--ignore-env`, HOME,
and expected-home variable. Inside:

1. Assert `HOME` is isolated path.
2. Assert `ZEPHYR_BASE == "$HOME/ncs/v3.3.0/zephyr"` and directory exists.
3. Run `nix-nrf bootstrap --check --quiet --print-sdk-path` and assert exactly
   `$HOME/ncs/v3.3.0` (proves second entry is ready without mutation).
4. Build:

   ```bash
   west build -p always \
     -b xiao_nrf54l15/nrf54l15/cpuapp \
     --sysbuild \
     -d "$HOME/build/blinky" \
     "$ZEPHYR_BASE/samples/basic/blinky"
   ```

5. Assert regular non-empty files:
   `$HOME/build/blinky/blinky/zephyr/zephyr.elf` and
   `$HOME/build/blinky/domains.yaml`.

Print elapsed bootstrap/build seconds and `du -sh "$HOME/ncs"` before cleanup.
Never flash hardware.

### Manual workflow

Add `.github/workflows/clean-room.yml`:

- name `Clean room`;
- trigger only `workflow_dispatch`;
- concurrency keyed by ref, cancel in progress;
- `runs-on: [self-hosted, nrf-hardware]` (known configured label);
- timeout 120 minutes;
- checkout v7, install-nix-action v31, Cachix action v17 matching existing
  workflow conventions;
- one test step: `bash tests/clean-room/run.sh`;
- set `NIX_NRF_CLEAN_MIN_FREE_GIB=25`;
- do not set KEEP, so script-created home cleans on completion/failure;
- no hardware/probe/flashing step and no schedule.

Update `.github/actionlint.yaml` only if required; known label already exists.

### Documentation and status

Update:

- `CONTRIBUTING.md`: local clean-room command, download/disk warning, manual
  workflow, no use in normal pre-commit gate.
- `README.md`: concise clean bootstrap proof/status and link to test script.
- the then-current bootstrap versioning plan: mark Phase 3 done only
  after real run passes; record date, host platform, elapsed times, measured
  installed size, exact build/artifact evidence, and workflow policy.
- `docs/development/nrfutil-backend-status.md`: clean-home bootstrap/build now
  proven; remove it from open follow-up.
- the then-current roadmap document: adjust any live claim that CI never
  performs real west build.

Add `tests/clean-room/README.md` documenting behavior, safety controls,
requirements (Linux, network, 25 GiB free, time), manual invocation, and that it
downloads several GiB then cleans script-created state.

Do not claim GitHub workflow passed unless it was actually dispatched and
observed. Local real run evidence is sufficient for this phase; workflow stays
manual and ready for later dispatch.

## Validation order

1. Implement script/workflow/docs without marking Phase 3 done.
2. Run cheap gates:

   ```bash
   nix fmt
   nix flake check -L
   bash -n tests/clean-room/run.sh
   actionlint .github/workflows/clean-room.yml
   ```

3. Exercise script safety without download using targeted temporary paths or a
   dry precondition mechanism if implemented; do not add a complex mock mode.
4. Confirm free space remains at least 25 GiB.
5. Run real test once:

   ```bash
   bash tests/clean-room/run.sh
   ```

   User approved this download. Allow up to 120 minutes.
6. Capture elapsed seconds, install size, exact artifact assertions, and final
   exit status in implementation recap and status docs.
7. Run full cheap gate again after evidence docs are updated.

If download/build fails:

- preserve temporary home by rerunning or setting
  `NIX_NRF_CLEAN_KEEP=1` only when useful for diagnosis;
- do not normalize failure, weaken artifact assertions, reuse existing SDK, or
  mark phase done;
- after two materially different fixes fail, escalate with logs, disk state,
  retained path, and exact question.

## Scope

In scope:

- Guarded clean-room harness.
- One approved real v3.3.0 SDK/toolchain download.
- Real XIAO nRF54L15 sysbuild blinky compilation.
- Manual self-hosted workflow and docs/evidence.

Out of scope:

- Flashing or probe access.
- Scheduled cold downloads.
- GitHub-hosted runner support.
- SDK/toolchain cache design.
- Exact bundle pin addition; this run proves current release-level selector.
- Parallel-bootstrap locking.
- Nix-native backend.

## Acceptance

- Empty isolated HOME verified before entry.
- Bootstrap installs under isolated `$HOME/ncs`, not developer home.
- Second independent shell derives isolated `ZEPHYR_BASE`.
- Real west sysbuild succeeds for exact board/sample.
- ELF and `domains.yaml` exist and are non-empty.
- Script cleanup cannot remove caller state or unsafe paths.
- Normal PR CI remains free of SDK downloads.
- Manual workflow validates current checkout when dispatched.
- Evidence docs match observed run, with no unsupported workflow-success claim.
- Full repository gate passes.

## Commit and recap

Commit implementation and measured evidence together only after real run and
final gate pass:

```text
test(bootstrap): verify clean-room NCS build
```

Inspect status, diff, and recent log; stage only phase files. Do not push,
merge, amend, open PR, flash hardware, or add attribution. Return:

- files changed;
- exact real-run command and result;
- download/bootstrap/build elapsed times;
- measured clean-home NCS size;
- artifact paths;
- cleanup result and free space after;
- cheap/full gate results;
- commit hash/message;
- blockers/deviations;
- explicit GitHub workflow dispatch status.
