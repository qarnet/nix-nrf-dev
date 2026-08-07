# nRF5340 CPUNET and nRF54L15 FLPR hardware-test handoff

## Goal

Make hardware harness prove real multicore flashing instead of accepting an
app-only image twice:

- nRF5340: build distinct CPUAPP and CPUNET images, flash correct address
  spaces, and byte-verify both cores.
- XIAO nRF54L15: build official NCS FLPR empty-image sysbuild bundle, prove
  bundle contains CPUAPP launcher and FLPR RRAM payload, then load and
  byte-verify entire bundle through OpenOCD.

User explicitly authorizes builds and flashing on connected probes:

- nRF5340: `E6635C08CB1F502B`
- XIAO nRF54L15: `8EE9B3FF`

## Scope

### In scope

- Fix `tests/hardware/run.sh` image construction, layout validation, flashing,
  logging, and assertions.
- Add post-write `verify_image` for both images in manual nRF53 `flash_both`.
- Add clear verification progress/success messages to nRF53 manual and nRF54L
  recipes.
- Update fake-OpenOCD Tcl semantic tests for nRF53 verification order.
- Refresh hardware README and workflow timeout/comments.
- Run normal flake gates and full physical hardware harness.

### Out of scope

- Recovery, mass erase, APPROTECT behavior changes, probe firmware, or board
  wiring changes.
- Changing `flash_west` verification semantics. Its `app_hex` is currently a
  sysbuild merged image that may include both address spaces; experimentally,
  `verify_image` of a combined app+net image while CPUAPP is selected fails at
  `0x01000000`. This phase changes only manual `flash_both`, used by hardware
  harness.
- Proving FLPR runtime execution/IPC/heartbeat. This phase proves flashability:
  official FLPR payload exists at FLPR RRAM addresses and OpenOCD
  `load_image` + `verify_image` succeeds byte-for-byte. Runtime FLPR proof needs
  dedicated observable firmware/IPC and is separate work.
- Visual LED assertion, UART capture, or committing generated firmware.
- Hardware workflow scheduling.

## Grounding and reproduced defect

Current harness builds only nRF5340 CPUAPP blinky, then passes same
`merged.hex` as both `flash_both` arguments. Physical run exited 0 but logged:

```text
Flashing net core: .../nrf53.../merged.hex
Warn : no flash bank found for address 0x00000000
OK: nRF5340 flashed
```

Thus net-core claim is false-positive.

Installed NCS v3.3.0 provides official multicore-empty sample:

```text
$ZEPHYR_BASE/../nrf/samples/basic/empty
```

Its `sample.yaml` explicitly supports nRF5340 CPUNET and nRF54L15 FLPR. Local
proof with exact commands:

```sh
west build -p always --sysbuild \
  -b nrf5340dk/nrf5340/cpunet \
  -d <cpunet-build> \
  "$ZEPHYR_BASE/../nrf/samples/basic/empty"

west build -p always --sysbuild \
  -b xiao_nrf54l15/nrf54l15/cpuflpr \
  -d <flpr-build> \
  "$ZEPHYR_BASE/../nrf/samples/basic/empty"
```

Observed artifacts and parsed Intel HEX ranges:

- CPUAPP blinky `<cpuapp-build>/merged.hex`: 25,172 data bytes,
  `0x00000000..0x00006253`.
- CPUNET empty `<cpunet-build>/merged.hex`: 20,664 data bytes,
  `0x01000000..0x010050B7`.
- FLPR sysbuild `<flpr-build>/merged.hex`: 51,114 data bytes,
  `0x00000000..0x00169713`, with data in both:
  - CPUAPP VPR launcher region below `0x00165000`;
  - FLPR RRAM `0x00165000..0x0017CFFF`.
- FLPR `domains.yaml` contains domains `empty` (RISC-V FLPR) and
  `vpr_launcher` (CPUAPP).

Physical proof already run manually:

- Dedicated app/net images flashed without `no flash bank` warning.
- CPUAPP `verify_image`: `verified 25172 bytes`.
- CPUNET `verify_image`: `verified 20664 bytes`.
- FLPR merged bundle loaded and `verify_image` returned success on XIAO.

## Recipe changes

### `tcl/nrf53_flash.tcl`

In `flash_both` only:

1. Immediately after CPUAPP `flash write_image erase $app_hex`, print
   `Verifying app core: $app_hex`, call `verify_image $app_hex`, then print
   `Verified app core: $app_hex`.
2. Immediately after CPUNET `flash write_image erase $net_hex`, print
   `Verifying net core: $net_hex`, call `verify_image $net_hex`, then print
   `Verified net core: $net_hex`.
3. Keep UICR writes after image verification, existing release/select/probe
   order, and final reset unchanged.
4. Do not modify `flash_west` in this phase.

Verification failure must propagate naturally and abort recipe before success
or final reset.

### `tcl/nrf54l_flash.tcl`

Keep operation order unchanged. Add progress messages around existing
`verify_image`:

```tcl
puts "Verifying image: $image"
verify_image $image
puts "Verified image: $image"
```

This provides explicit hardware-log evidence while preserving byte
verification already present.

## Tcl semantic-test updates

Update `tests/tcl/test_flash_recipes.tcl`:

- nRF53 unlocked and locked `flash_both` exact logs include
  `verify_image $app_hex` directly after app write and
  `verify_image $net_hex` directly after net write.
- Add ordered assertions proving each verify follows matching write and precedes
  corresponding UICR handling.
- Assert verification success messages are emitted for both cores.
- nRF54 existing exact command order remains same; assert new verification
  success message uses exact image path.
- `flash_west` expected command sequence remains unchanged, proving scope.

## Hardware harness changes

### Build directories and cleanup

Use four independent temporary build dirs:

- nRF53 CPUAPP blinky;
- nRF53 CPUNET empty;
- nRF54L CPUAPP blinky (existing normal app proof);
- nRF54L FLPR empty sysbuild bundle.

Trap removes all four exact `mktemp` dirs on every exit.

### Builds

Keep existing CPUAPP blinky builds. Add:

```sh
NCS_EMPTY_SRC="$ZEPHYR_BASE/../nrf/samples/basic/empty"

west build -p always --sysbuild \
  -b nrf5340dk/nrf5340/cpunet \
  -d "$BUILD_DIR_53_NET" "$NCS_EMPTY_SRC"

west build -p always --sysbuild \
  -b xiao_nrf54l15/nrf54l15/cpuflpr \
  -d "$BUILD_DIR_54L_FLPR" "$NCS_EMPTY_SRC"
```

Require exact non-empty root artifacts:

- CPUAPP: `$BUILD_DIR_53/merged.hex`;
- CPUNET: `$BUILD_DIR_53_NET/merged.hex`;
- nRF54 blinky: `$BUILD_DIR_54L/merged.hex`;
- FLPR bundle: `$BUILD_DIR_54L_FLPR/merged.hex`;
- FLPR domains: `$BUILD_DIR_54L_FLPR/domains.yaml` containing names `empty` and
  `vpr_launcher`.

Do not retain fallback artifact paths. Exact paths are part of tested sysbuild
contract.

### Intel HEX layout validation

Add a stdlib Python helper invocation inside `run.sh` (function + heredoc is
fine). It must:

- parse Intel HEX data plus extended segment/linear address records;
- validate each record checksum;
- reject malformed/unsupported address state with clear error;
- count data bytes per required region;
- reject any data byte outside allowed required regions;
- print total bytes and min/max address.

Required layouts:

- CPUAPP: one region `[0x00000000, 0x00100000)`.
- CPUNET: one region `[0x01000000, 0x01040000)`.
- nRF54 FLPR bundle:
  - CPUAPP launcher `[0x00000000, 0x00165000)`;
  - FLPR RRAM `[0x00165000, 0x0017D000)`.

Every listed region must contain at least one data byte. This catches original
app-image-as-net-image defect before touching hardware.

### Flash assertions

Capture each OpenOCD invocation to per-step temporary log while preserving
pipe exit through `set -o pipefail`/existing `set -euo pipefail`.

1. nRF53 `flash_both` receives distinct CPUAPP and CPUNET hex files.
2. Fail if nRF53 log contains `no flash bank found`.
3. Require exact `Verified app core:` and `Verified net core:` success lines.
4. Keep existing nRF54 CPUAPP blinky flash.
5. Add second nRF54 flash of FLPR bundle using existing `nrf54l_flash`.
6. Require exact `Verified image: <FLPR bundle>` line from FLPR step.

An OpenOCD nonzero exit fails immediately. Do not invoke recovery or mass erase.

## Documentation/workflow

- Update `tests/hardware/README.md`: remove stale phase-6/fixture claims;
  describe runtime-built CPUAPP/CPUNET/FLPR artifacts, address validation,
  byte verification, and explicit limit that FLPR execution is not observed.
- Update `.github/workflows/hardware.yml` stale phase comments and raise timeout
  from 15 to 25 minutes for four clean builds on self-hosted runner.
- Update README hardware verification wording if needed; keep concise.

## Verification

Run in order:

```sh
NIX_NRF_NRF53_FLASH_TCL="$PWD/tcl/nrf53_flash.tcl" \
NIX_NRF_NRF54L_FLASH_TCL="$PWD/tcl/nrf54l_flash.tcl" \
  nix shell nixpkgs#tcl --command tclsh tests/tcl/test_flash_recipes.tcl

nix build .#checks.x86_64-linux.flash-recipe-tests -L
nix flake check --all-systems --no-build -L
nix flake check -L
bash tests/hardware/run.sh
```

User has authorized final hardware command now. Preserve full hardware log in
`/tmp/opencode/hardware-multicore-run.log` while retaining command exit status.

## Acceptance

- nRF53 app and net hex layouts are distinct and correct.
- nRF53 physical run has no `no flash bank found`, verifies both images, resets,
  and exits 0.
- FLPR bundle contains non-empty launcher and FLPR RRAM regions.
- XIAO physical run loads and verifies full FLPR bundle, prints exact success,
  resets, and exits 0.
- Existing normal nRF54 app flash still passes.
- All temp dirs removed; worktree clean after commit.
- Normal 18 flake checks remain green (no new normal check key needed; existing
  flash-recipe test expands).

## Executor instructions

Implement exactly this phase. Hardware flashing is approved, but recovery/mass
erase is not. Stop if probe identities differ, unexpected locking requires
recovery, address layout differs from grounded ranges, or verification fails.
Do not weaken layout/verification assertions. Run normal gates before hardware,
then hardware once. Inspect status/diff/log, stage scoped files, and commit a
concise conventional message only after all acceptance criteria pass. No push,
amend, PR, or attribution. Return files, exact build/layout/flash evidence,
warnings, cleanup, commit hash/message, blockers, deviations, and follow-up.
