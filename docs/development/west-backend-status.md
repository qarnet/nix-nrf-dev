# west backend

`backend = "west"` is experimental. Active metadata selects NCS `v3.4.1` on
`x86_64-linux` and `aarch64-linux`. Host defaults and refusal boundaries live in
[backends.md](../backends.md#native-host-boundaries). Current qualification and
limits are recorded below; older platform experiments remain historical evidence
in [linux-host-platform-plan.md](linux-host-platform-plan.md#implementation-qualification-status).

Nix provides Zephyr SDK `1.0.1`, compiler targets, Python `3.12`, and host
tools. Standard west creates mutable NCS workspace. Version-local venv holds
west and workspace Python requirements. This backend does not use nrfutil,
sdk-manager, or the Nordic toolchain bundle.

## What exists

- `mkNrfShell { backend = "west"; ncsVersion = "v3.4.1"; }` is public
  selector. It rejects unknown releases, `toolchainBundleId`, and non-default
  `nrfutilPackage`. Other shell options match nrfutil backend.
- `nix/backends/west/versions.nix` owns NCS release, Python package, Zephyr SDK
  assets and hashes, requirements, and pip constraints. Builders contain no
  release-specific literals.
- `nix/backends/west/zephyr-sdk.nix` assembles official minimal SDK and compiler
  archives. It removes interactive installers, patches ELF binaries, exports
  `ZEPHYR_TOOLCHAIN_VARIANT=zephyr` and `ZEPHYR_SDK_INSTALL_DIR`, and validates
  SDK files and compilers.
- `nix-nrf bootstrap` creates or updates `$HOME/ncs/<version>` workspace and
  `.venv`. `--check` only checks state. Ready non-check invocation does not
  prompt or mutate. Setup creates venv, installs `west`, runs `west init` and
  `west update`, then installs declared requirements.
- `nix-nrf versions` lists sorted keys from `versions.nix` and does not invoke
  nrfutil.
- `nix-nrf doctor` accepts `west workspace/Zephyr SDK` human label while JSON
  schema and exit behavior remain same.
- `nix/backends/west/shell.nix` provides host tools, OpenOCD, backend-aware
  `nix-nrf`, and scoped `west`. It prepends `.venv/bin` only for west and
  exports workspace and Zephyr SDK variables there.

## Validation

Normal CI runs `checks.west-bootstrap-tests`, `checks.west-versions-tests`,
`checks.west-backend-metadata`, `checks.west-target-toolchain-consistency`,
`checks.west-backend-quoting`, `checks.west-shell-boundary`, and
`checks.west-sdk-native-probes`. The compiler probe produces real ARM/RISC-V
objects; shell/bootstrap tests use fake boundaries. None provisions a mutable
workspace or touches hardware.

`tests/west-backend/run.sh` starts with empty home, creates real workspace and
venv, then builds Zephyr blinky. It downloads several GiB, needs explicit
approval, and is not part of normal CI.

## Constraints

- SDK 1.0.1 Python-enabled GDB links Python 3.12; the package now supplies that
  library. Compiler and plain-GDB executable probes are separate from Python-GDB
  integration qualification, which is not claimed here.
- Workspace readiness resolves `-r` includes and accepts any west version that
  satisfies all constraints. It does not require initial `1.5.0` after
  requirements installation.
- NCS `v3.4.1` requirements allow `cbor2` 6.x, but `zcbor==0.8.1` imports an
  alias removed in 6.x. Metadata pins `cbor2==5.9.0` from NCS
  `requirements-fixed.txt` through every venv pip install.
- No scheduled workflow runs full workspace setup. Normal CI builds fixed SDK
  package and runs deterministic tests.

## Open work

[roadmap.md](roadmap.md) tracks new releases, platforms, caching, and CI
policy. [sdk-nrf-feasibility-draft.md](sdk-nrf-feasibility-draft.md) tracks
pure Nix backend research.

## v3.4.1 qualification

Fresh isolated SDKs use sdk-nrf commit
`b20f8619ba9a5530f8c34b0a130d829947cfe55d` and sdk-zephyr commit
`33fa6a7aac6a4401d16a67cb9f27a3483fa02dd6`. No v3.3.0 SDK is an input to this
acceptance. Nordic's amd64 bundle is `8285d8ad56`; both compiler providers report
Zephyr SDK 1.0.1 / GCC 14.3.0. Prepared west Python is 3.12.13 with west 1.5.0;
the Nordic bundle supplies Python 3.12.4 and west 1.5.0. These observations are
distinct from the tools YAML's declared west 1.4.0.

The compile-only baseline runner passes six profiles per backend: nRF52840
single-image/sysbuild, nRF5340 CPUAPP/CPUNET, and nRF54L15 CPUAPP/FLPR. This is 12
amd64 builds and six ARM64 west builds. The FLPR sysbuild includes its CPUAPP
launcher. Independent application-owned imported workspace qualification also
passes four amd64 builds and two ARM64 west builds, with the manifest-owned module
symbol linked into the ELF and original source/config/Git inputs unchanged.
Imported fixtures explicitly omit Matter and cmock; stock-SDK command audits do
not make those omissions.

Registry/parser audits account for all 39 stock registrations across four
application layouts: 312 amd64 cases across both backends and 156 ARM64 west
cases. Only `suit-manifest` fails (eight amd64 cases, four ARM64 cases), because
the v3.4.1 descriptor points to missing `suit_manifest.py`. Snapshot preservation
passes. Missing Python imports from the earlier v3.3.0 prepared environments are
not carried forward; selected extra groups and dependency consistency now pass.
No SBOM smoke, hardware operation or network-dependent command execution is used
as an availability proxy.

Evidence roots: amd64 `/tmp/opencode/pb001-v341-baseline-builds-v2/`,
`pb001-v341-imported-amd64-v3/`, and `pb001-v341-command-layers-four-layouts/`;
Pi `~/nix-nrf-experiments/pb001-v341-baseline-resumed/`,
`pb001-v341-imported-native/`, and `pb001-v341-command-layers-native-v2/`.
Each has a retained `result.json` and raw logs. Upstream missing command remains
an explicit failed qualification case, not a silent skip or a passing-all-tools
claim. Build success does not establish physical target execution.

## Historical v3.3.0 resolved command-registry qualification (2026-10-05)

The following evidence predates the v3.4.1 migration. It is retained as history,
not current-baseline acceptance. Fresh v3.4.1 provisioning and qualification are
tracked by PB-001; the old SDK is not used for new acceptance.

Command availability now has two independent evidence boundaries. Read-only
doctor uses west's resolved `Manifest.from_topdir()` and
`WestApp.load_extension_specs()` to discover effective names/owners without
calling extension factories. It also accounts for descriptor declarations,
built-in/duplicate-name rejection, and missing implementation files. Public
`west help <name>` then checks each effective parser in the selected backend
Python/tool environment. `west topdir` alone does not prove either boundary.

The opt-in runner's offline SBOM execution is now `--sbom-smoke` only. Its
separate outcome never determines command availability. No SBOM execution was
requested in the resolved-registry runs below.

Application-owned imported-manifest fixtures expose 31 registrations (10 Nordic,
21 Zephyr) from `sdk/nrf` and `sdk/rtos`. The previously recorded stock SDK catalog
exposes another five Matter ZAP commands; Matter was explicitly excluded from
these imported fixtures, not silently skipped by the command runner.

| Host/backend | Parser cases, four layouts | Failed cases | Source/config preservation |
| --- | ---: | ---: | --- |
| amd64/west | 124 | 28 | pass |
| amd64/nrfutil | 124 | 4 | pass |
| ARM64/west | 124 | 28 | pass |

Every layout resolves the same 31 effective names/owners and selected application
manifest. Discovery reports `partial` because stock NCS v3.3.0 declares
`suit-manifest` but lacks `scripts/west_commands/suit_manifest.py`. The command is
registered, but cannot load; registration and activation are not conflated.

Prepared west Python on both hosts additionally lacks `pygit2` (three NCS
repository commands), `usb` (Thingy DFU/reset parsers), and `natsort` (Twister).
Direct isolated imports confirm these missing dependencies; `packaging.version`
imports successfully. The earlier stock amd64 west run additionally finds missing
`wget` for the five Matter ZAP parsers. No package installation, SDK modification,
network-dependent command execution, or hardware operation repaired these results.

Evidence: `/tmp/opencode/pb026-resolved-registry-final-v5/result.json` on amd64;
Pi `~/nix-nrf-experiments/pb026-resolved-registry-v4/result.json` plus raw logs.
Pi's v4 report treats structural `partial` as a failed registry case; the later
runner separates successfully resolved registries from implementation/parser
failures. Its retained full discovery data, names, owners and per-command outcomes
remain authoritative; that report is not relabeled as a passing run.

Repository gates pass with the final implementation on both native hosts:
`nix flake check -L`, 23 public source/workspace regressions, and 30 doctor tests.
Pi report `pb026-resolved-registry-final-native-v5.json` returns 0 in 771.89s,
without throttling. Full SDK parser-readiness qualification remains failed for the
concrete upstream/environment causes above; repository gate success is not a
claim that every SDK command is ready.
