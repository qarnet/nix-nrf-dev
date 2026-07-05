# nix-nrf-dev

Reusable Nix tooling for Nordic nRF firmware projects: the NCS toolchain
dev shell and CMSIS-DAP flashing via a pinned openocd-master build.
Extracted from the `le-audio-receiver` project (nRF5340 + nRF54L15), where
every piece is verified on hardware.

## Why

Every NCS project ends up re-creating the same flake: an openocd built from
master (release openocd lacks nRF53/54 target support), a minimal nrfutil
packaging (nixpkgs' depends on SEGGER J-Link), the nrfutil sdk-manager
toolchain environment dance, and probe/flash helper scripts. This repo owns
those pieces once.

**Policy: openocd-master is the only flash backend.** probe-rs was evaluated
(0.31.0, 2026-07-05) and rejected: on the nRF5340 its attach model collides
with the soft-APPROTECT design and its only unlock remedy is a destructive
mass erase that recreates the lock.

## Quick start (new project)

```bash
nix flake init -t github:qarnet/nix-nrf-dev
direnv allow          # or: nix develop
```

The shell provides: `west` + Zephyr toolchain (via nrfutil sdk-manager for
the configured NCS version), `ZEPHYR_BASE`, `openocd` (master build),
`nrf-probes`, `nrfutil`, and multilib GCC for `native_sim`.

## Outputs

| Output | What |
|--------|------|
| `lib.<system>.mkNrfShell { ncsVersion, packages, extraShellHook, withMultilib }` | devShell factory |
| `packages.openocd-master` | openocd from master (pinned), wrapped for libudev; has nRF53 CTRL-AP recovery TCL |
| `packages.openocd-master-unwrapped` | the raw build |
| `packages.nrf-probes` | probe/target identification (see below) |
| `packages.nrfutil-core` | minimal nrfutil (no J-Link dependency) |
| `templates.default` | project skeleton (flake.nix + .envrc) |
| `tcl/` | canonical flash recipes (see below) |

## nrf-probes — never assume the probe↔board mapping

```
$ nrf-probes
SERIAL            PROBE                              TARGET    DPIDR       PART        VARIANT
8EE9B3FF          Seeed Studio XIAO nrf54 CMSIS-DAP  nRF54L15  0x6ba02477  0x00054b15  AAC0
E6635C08CB1F502B  Debugprobe on Pico (CMSIS-DAP)     nRF5340   0x6ba02477  0x00005340  QKAA

$ nrf-probes --find nrf53      # serial of the probe wired to an nRF53
E6635C08CB1F502B
```

Read-only SWD fingerprint (DPIDR → AP IDR map → FICR PART/VARIANT). Works on
APPROTECT-locked chips via the DP/AP signature. Flash scripts should select
probes with `--find <family>` instead of hardcoding serials — hardcoded
serials go stale the moment probes are replugged.

## Flash recipes (`tcl/`)

- **`nrf53_flash.tcl`** — nRF5340 dual-core: APPROTECT check/recovery, app
  core, **UICR.APPROTECT programming** (mandatory — an erased UICR
  hard-locks debug at every reset; SystemInit copies UICR.APPROTECT into
  CTRLAP.APPROTECT.DISABLE), cpunet FORCEOFF release, net core, net UICR,
  reset. Integrates with the west openocd runner (`check_approtect` /
  `flash_west`) or standalone (`flash_both`).
- **`nrf54l_flash.tcl`** — nRF54L: RRAM is plain writable memory after the
  RRAMC write-enable (`mww 0x5004b500 0x101`); `load_image` +
  `verify_image`, no flash driver. FLPR firmware flashes identically (its
  code partition is an RRAM slice in the app core address space, `0x165000`
  on the nRF54L15).

## Recovery coverage — KNOWN GAP

| Chip | Recovery | Notes |
|------|----------|-------|
| nRF52 | openocd `nrf52_recover` | upstream, untested here |
| nRF5340 | openocd `nrf53_recover` (used by `check_approtect`) | proven; nRF53-specific (`_nrf_ctrl_ap_recover` hardcodes CTRL-AP IDR `0x12880000`) |
| nRF54L | **NONE** | upstream openocd has no nrf54l recovery; the generic CTRL-AP proc rejects the 54L CTRL-AP. Fallback: `nrfutil device recover` with a J-Link. Writing/testing an adapted CTRL-AP proc needs a sacrificial board. |

## Roadmap

- `nrf-flash` — chip-aware flash CLI (identify probe+chip via nrf-probes,
  dispatch to the right recipe, project config from a small `.nrf.toml`)
- nRF54L CTRL-AP recovery proc (once testable against a sacrificial board)
- openocd pin bumps as upstream gains nRF54L flash/recovery support

## Consumers

- [`le-audio-receiver`](https://github.com/qarnet/le-audio-receiver) —
  nRF5340 (Ebyte E83 + picoprobe) and nRF54L15 (Seeed Xiao, built-in
  CMSIS-DAP)
