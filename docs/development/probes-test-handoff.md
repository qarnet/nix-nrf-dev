# Probe command regression-test phase handoff

## Goal

Add normal, hardware-free flake coverage for `nix-nrf probes`, currently largest
untested public command surface. Tests must execute command as subprocess against
a temporary fake sysfs tree and fake `openocd`, proving user-visible output and
exit behavior without touching host USB devices.

## Scope

### In scope

- Add environment seams to `bin/commands/nix-nrf-probes` for:
  - USB sysfs root override: `NIX_NRF_PROBES_SYSFS_ROOT`, defaulting to
    `/sys/bus/usb/devices`.
  - OpenOCD timeout override: `NIX_NRF_PROBES_OPENOCD_TIMEOUT`, defaulting to
    `30` seconds and accepting a positive decimal number.
- Keep default production behavior unchanged.
- Make missing requested-serial diagnostics deterministic: preserve first
  occurrence order from CLI and omit duplicate missing serials.
- Add `tests/unit/test_nix_nrf_probes.py` using Python stdlib `unittest` only.
- Add `checks.probes-tests` in `nix/flake/checks/core.nix` and export it from
  `nix/flake/checks/default.nix`.
- Extend existing help gate to prove `nix-nrf help probes` reaches packaged
  probe command help successfully.
- Update current testing/check documentation only where check list or test
  ownership is enumerated.

### Out of scope

- Real USB, CMSIS-DAP, OpenOCD target access, flashing, or hardware workflow
  changes.
- Changing chip-family detection addresses or `SCAN_TCL` logic.
- Adding JSON output or changing table columns.
- Refactoring command into importable Python modules.
- NixOS module tests, nrfutil west-wrapper tests, template tests, platform-output
  fixes, or TCL flash-recipe tests. Those remain later phases.
- New test dependencies (`pytest`, `nix-unit`, mocks, or external fixtures).

## Grounded current behavior

- Command source: `bin/commands/nix-nrf-probes`.
- Packaging: `nix/commands/probes.nix`; exact command lives at
  `$out/libexec/nix-nrf/probes` and dispatcher execs it.
- Current USB root is hard-coded at source line 24.
- Current OpenOCD subprocess timeout is hard-coded to 30 seconds at source line
  137.
- `tests/hardware/run.sh` exercises enumeration and unique family lookup only
  with physical boards; normal flake checks contain no probe fixture coverage.
- Doctor tests already establish repository precedent for temporary sysfs/dev
  roots through environment overrides and stdlib subprocess tests.

## Required production behavior

1. Resolve sysfs root once from `NIX_NRF_PROBES_SYSFS_ROOT` when set; otherwise
   use `/sys/bus/usb/devices` exactly as today.
2. Resolve timeout from `NIX_NRF_PROBES_OPENOCD_TIMEOUT`; default `30`.
   Reject non-numeric, zero, and negative values with concise
   `nix-nrf probes:` stderr and nonzero exit, never Python traceback.
3. Enumeration still:
   - sorts USB device paths;
   - accepts products containing `CMSIS-DAP`;
   - skips missing/unreadable product or serial files;
   - emits existing `no CMSIS-DAP probes found` error when empty.
4. OpenOCD invocation remains read-only and unchanged apart from configurable
   timeout. Fake boundary must observe selected serial and expected setup/scan
   arguments.
5. Existing parser, chip naming, variant rendering, notes, table headings, and
   `--find` exit semantics remain unchanged.
6. Missing serial list becomes deterministic in caller order, de-duplicated.
7. Environment overrides are test/diagnostic seams; do not advertise them as
   normal user configuration in main README.

## Test shape

Create `tests/unit/test_nix_nrf_probes.py`, following resolver/subprocess style
from `test_nix_nrf_doctor.py`:

- Resolve command from `NIX_NRF_PROBES_SCRIPT`, with repository-relative
  fallback for direct local execution.
- Each test gets isolated temp directory containing fake USB device dirs and a
  fake executable named `openocd` first on `PATH`.
- Fake OpenOCD reads `adapter serial <serial>` from argv, records full argv, and
  emits selected `FWP|key|value` lines or errors based on serial. Use running
  `sys.executable` in fake shebang so Nix sandbox works.
- Invoke copied real command as subprocess. Assert stdout, stderr, and exact
  return codes through CLI, not private functions or mocks.

Minimum cases:

1. Empty sysfs: error contains `no CMSIS-DAP probes found`, nonzero.
2. Enumeration filtering: non-CMSIS product and CMSIS-DAP device lacking serial
   are skipped; accepted devices appear in sorted device-path order.
3. Table parsing: fixtures cover known nRF5340 part, known nRF54L15 part,
   generic/known nRF52 part, ASCII variant, invalid variant fallback, unknown
   target, and no-target note.
4. Open failure text `unable to open CMSIS-DAP device` maps to existing udev/
   in-use note.
5. Locked target (`Examination failed`, DPIDR/family present, no part) renders
   family fallback and APPPROTECT note.
6. Serial filtering invokes OpenOCD only for selected present serials.
7. Missing serial error preserves requested order and de-duplicates repeated
   names.
8. `--find`:
   - unique family prints only serial and exits 0;
   - exact chip-name match prints only serial and exits 0;
   - no match prints inventory plus existing message to stderr and exits 1;
   - multiple matches print inventory plus existing message and exit 2.
9. Missing OpenOCD returns existing `openocd not found on PATH` error without
   traceback.
10. Short timeout fixture returns table note `timeout talking to probe` without
    waiting 30 seconds.
11. Invalid timeout values fail cleanly without invoking OpenOCD.
12. Fake argv log proves serial selection, CMSIS-DAP config, SWD transport,
    disabled server ports, scan proc, `init`, `fwp_scan`, and `shutdown` reach
    OpenOCD. Do not assert incidental Python implementation details.

Keep assertions resilient to column spacing: assert headings and meaningful
row substrings unless exact whitespace is public behavior being tested.

## Nix wiring

In `nix/flake/checks/core.nix`, add `probesTests` parallel to `doctorTests`:

- `nativeBuildInputs = [ pkgs.python3 ];`
- copy real probe script and test file into build directory;
- make script executable;
- run test with `NIX_NRF_PROBES_SCRIPT="$PWD/nix-nrf-probes"`;
- create `$out` only after tests pass.

Export as `probes-tests`, then add explicit inheritance in
`nix/flake/checks/default.nix`. Keep check hardware-, network-, and host-sysfs
independent.

## Verification

Run focused checks first:

```sh
python3 tests/unit/test_nix_nrf_probes.py
nix build .#checks.x86_64-linux.probes-tests -L
nix build .#checks.x86_64-linux.nix-nrf-help -L
```

Then repository gates:

```sh
nix flake check -L
```

Do not use `--all-systems` as phase acceptance: pinned Nixpkgs 26.11 rejects
`x86_64-darwin` before repository checks evaluate. Platform-output policy is a
separate known follow-up.

## Acceptance

- New test fails against pre-change command because fake sysfs/timeout seams do
  not exist, then passes after implementation.
- `checks.probes-tests` runs in normal `nix flake check`.
- All listed user-observable cases pass without hardware, network, or host USB.
- Existing hardware script remains unchanged.
- Full current-system flake check passes.
- Worktree contains only scoped source, test, check-wiring, handoff, and any
  necessary check-list documentation changes.

## Executor instructions

Implement this handoff exactly. Stop and escalate rather than inventing new
architecture, weakening assertions, or expanding scope. After verification,
inspect `git status`, `git diff`, and recent log; stage only intended files and
commit with concise conventional message. Do not push, amend, open PR, or add
agent attribution. Return files changed, behavior changed, commands/results,
commit hash/message, blockers, deviations, and suggested follow-up.
