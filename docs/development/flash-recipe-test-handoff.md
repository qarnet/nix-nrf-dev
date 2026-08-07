# Flash-recipe semantic regression-test handoff

## Goal

Add normal, hardware-free semantic tests for repository Tcl flash recipes while
keeping existing real-OpenOCD syntax/source gate and hardware proof.

## Scope

### In scope

- Add stdlib Tcl test harness `tests/tcl/test_flash_recipes.tcl`.
- Source real `tcl/nrf53_flash.tcl` and `tcl/nrf54l_flash.tcl` under `tclsh`
  with fake OpenOCD commands that record semantic operations.
- Add `checks.flash-recipe-tests` in `nix/flake/checks/core.nix` using pinned
  `pkgs.tcl`.
- Export check and update README/architecture check list/count.
- Tighten both existing `.github/workflows/ci.yml` real-OpenOCD parse steps to
  require nonzero no-probe exit, rather than accepting unexpected exit 0.

### Out of scope

- Real target access, flashing, firmware builds, USB, recovery, or hardware
  workflow changes.
- Changing flash recipes unless test exposes genuine conflict with documented
  behavior; escalate first.
- Pretending mocks prove electrical/device behavior. Hardware harness remains
  authority for real target execution.
- OpenOCD target-config internals or Nordic register/address research. Tests
  preserve and exercise current recipe contract; they do not invent addresses.
- Adding Expect, pytest, or other dependencies.

## Grounding

- `tcl/nrf54l_flash.tcl` documents required order: halt, RRAMC write-enable,
  load image, verify image, run.
- `tcl/nrf53_flash.tcl` documents dual-core order, conditional recovery, UICR
  unprotect behavior, cpunet release, bank probe, and final reset.
- `.github/workflows/ci.yml` currently asks real OpenOCD to source each recipe
  without hardware and rejects Tcl/syntax strings, but does not invoke recipe
  procs or assert expected nonzero exit.
- `tests/hardware/run.sh` invokes `flash_both` and `nrf54l_flash` on physical
  targets, but only in approval-gated self-hosted flow.
- Pinned Nixpkgs exposes `${pkgs.tcl}/bin/tclsh` (verified with Tcl 8.6).

## Test harness design

Create one executable/plain Tcl script. Recipe paths come from required env vars
`NIX_NRF_NRF53_FLASH_TCL` and `NIX_NRF_NRF54L_FLASH_TCL`; fail clearly when
unset. Use custom tiny assertions and operation log—no Tcl packages.

Before sourcing recipes, define fake commands matching used OpenOCD surface:

- `init`, `targets`, `reset`, `halt`, `wait_halt`, `load_image`,
  `verify_image`, `mww`, `nrf53_recover`, `nrf53_cpunet_release`;
- dispatcher proc `flash {subcommand args}`;
- target commands `nrf53.cpuapp` and `nrf53.cpunet` supporting
  `arp_examine` and `read_memory`.

Every fake appends a Tcl list describing command + args to global log. Target
state controls:

- app locked/unlocked (`arp_examine` error/success);
- per-address read-memory values for erased (`0xFFFFFFFF`), already-unprotected
  (`0x50FA50FA`), and other-programmed UICR cases.

Use list equality and ordered-subsequence assertions. Do not compare human
`puts` text except where needed to prove warning/recovery branch; command
semantics matter more than formatting.

## Required cases

### nRF54L

1. `nrf54l_rram_we` records exactly
   `mww 0x5004b500 0x101`.
2. `nrf54l_flash` with image path containing spaces records exact order and
   single-argument preservation:
   - `reset halt`;
   - RRAM write-enable;
   - `load_image <exact image>`;
   - `verify_image <exact image>`;
   - `reset run`.

### nRF53 UICR helper

3. Erased UICR performs one exact `flash fillw <addr> 0x50FA50FA 1`.
4. Already-unprotected UICR performs no write.
5. Other programmed value performs no write (leave-as-is safety branch).
6. App helper reads/programs exact current two app addresses; net helper uses
   exact current net address. These addresses are current recipe contract, not
   newly researched constants.

### nRF53 recovery and flashing

7. `check_approtect` unlocked path does not recover; locked path calls
   `nrf53_recover` exactly once.
8. `flash_both` unlocked path with app/net names containing spaces preserves
   each as one argument and proves ordered semantics:
   - init + app examine;
   - select app, reset/halt/wait;
   - app image write before app UICR writes;
   - cpunet release/examine before selecting net;
   - net halt/wait + `flash probe 2` before net image write;
   - net UICR handling after net image write;
   - final `reset run` last.
9. `flash_both` locked path invokes recovery after failed app examine and before
   app reset/flash, then continues normal flow.
10. `flash_west` uses exact `NET_CORE_HEX`, does not run manual `init`/app
    reset-halt sequence, flashes app before release/net flow, and ends reset run.

Test script prints concise pass summary and exits nonzero on first assertion
failure with expected/actual operation context.

## Nix wiring

Add `flashRecipeTests` in `core.nix`:

```nix
pkgs.runCommand "nix-nrf-flash-recipe-tests" {
  nativeBuildInputs = [ pkgs.tcl ];
  testFile = ../../../tests/tcl/test_flash_recipes.tcl;
  nrf53Recipe = ../../../tcl/nrf53_flash.tcl;
  nrf54lRecipe = ../../../tcl/nrf54l_flash.tcl;
} ''
  NIX_NRF_NRF53_FLASH_TCL="$nrf53Recipe" \
  NIX_NRF_NRF54L_FLASH_TCL="$nrf54lRecipe" \
    tclsh "$testFile"
  mkdir -p "$out"
'';
```

Exact Nix formatting may differ. Export `flash-recipe-tests` explicitly.

## Real OpenOCD CI gate

Keep existing two hosted-CI parse steps. After command capture, add explicit
failure when `rc == 0`; hosted runner has no probe, so success would mean gate
did not exercise expected adapter-open boundary. Continue rejecting
`syntax error|wrong # args|can't read|invalid command name`. Update comments to
describe this as real-OpenOCD source compatibility, while new flake check owns
proc semantics.

Do not require one exact OpenOCD no-probe message; versions may phrase adapter
failure differently.

## Verification

```sh
NIX_NRF_NRF53_FLASH_TCL="$PWD/tcl/nrf53_flash.tcl" \
NIX_NRF_NRF54L_FLASH_TCL="$PWD/tcl/nrf54l_flash.tcl" \
  nix shell nixpkgs#tcl --command tclsh tests/tcl/test_flash_recipes.tcl
nix build .#checks.x86_64-linux.flash-recipe-tests -L
nix flake check --all-systems --no-build -L
nix flake check -L
```

First command is useful local proof but may use registry Nixpkgs. Flake check's
`pkgs.tcl` is pinned acceptance authority.

## Acceptance

- New normal check executes real recipe procs and proves listed command order,
  arguments, conditionals, and safety branches with no hardware.
- Existing real OpenOCD source gate rejects syntax errors and unexpected exit 0.
- Hardware workflow remains unchanged.
- Full checks pass; list/count/docs match.
- No recipe behavior changes unless escalated.

## Executor instructions

Implement exactly. Escalate before changing recipes or weakening semantic
assertions. Stop after two materially different failed approaches rather than
thrashing. Run verification, inspect status/diff/log, stage scoped files, commit
concise conventional message. No push, amend, PR, or attribution. Return files,
behavior, exact tests/results, hash/message, blockers, deviations, follow-up.
