# Changelog

All notable changes to the nix-nrf-dev project (and its `nix-nrf` CLI).

> The project version is independent from Nordic NCS versions. `release.json`
> holds the canonical strict SemVer of this nix-nrf-dev release; `ncsVersion`
> (e.g. `v3.3.0`) is an upstream SDK selection and tested baseline, never the
> project version.

| Version | Date | Highlights |
|---|---|---|
| [0.2.0](#020) | 2026-10-08 | Native Linux ARM64 west development; NCS v3.4.1 baseline; SDK-independent west core and command diagnostics; explicit Python tooling groups |
| [0.1.3](#013) | 2026-10-03 | Independent SDK workspace sources; experimental shared OpenOCD sessions and verification fixtures; pinned product backlog tooling |
| [0.1.2](#012) | 2026-09-12 | Documentation refresh; fixed fresh-shell default `nrfutil` bootstrap with content-pinned sdk-manager `1.16.1` supply |
| [0.1.1](#011) | 2026-08-17 | Documentation: install section split into automated (`init-project`) and manual (hand-written `flake.nix`) quick start methods; new detailed install guide (`docs/install.md`) |
| [0.1.0](#010) | 2026-08-08 | First release: reusable x86_64-linux flake and public `mkNrfShell` (default nrfutil/sdk-manager backend, experimental west backend); `nix-nrf` CLI (`versions`, `probes`, `bootstrap`, `doctor`, `--version`); dynamic concrete-version `init-project` app; pinned OpenOCD, udev package, narrow NixOS module with explicit plugdev policy; NCS v3.3.0 tested baseline with nRF5340/nRF54L15 flash and probe verification; deterministic flake/unit/VM/metadata checks, scheduled latest-NCS validation, manual hardware/clean-room workflows, clean-room telemetry; release automation (consistency gate, trusted-main GitHub Release workflow) |

## [Unreleased]

## [0.2.0]

### Added

- Native `aarch64-linux` packages, apps, shells and library outputs alongside
  `x86_64-linux`. Experimental west provides native ARM/RISC-V cross-compilers on
  both hosts. Per-host sdk-manager 1.16.1 archives remain content-pinned.
- Host-aware repository/initializer presets and portable west-generated projects.
  Public `mkNrfShell` retains its nrfutil default; unsupported ARM64 Nordic
  toolchain requests and explicit ARM64 multilib fail without fallback or acquisition.
- SDK-independent core west commands and separate resolved-registry/parser
  diagnostics. General help and doctor distinguish core availability, extension
  discovery and command readiness without importing arbitrary extensions in doctor.
- Optional west Python requirement groups `ncs-extra` and `ncs-ci`, joint
  dependency resolution, selected-root/version checks and read-only `pip check`.
  Caller-owned workspace Python remains check-only, including `--yes`.
- Bounded maintainer-only Nordic advertised-metadata catalog with source
  provenance and explicit coverage limits. It is not a package lock, full mirror
  or consumer-time network dependency; lock/update automation remains future work.

### Changed

- Active development/qualification baseline moves to NCS v3.4.1, Zephyr SDK 1.0.1
  GNU layout and Python 3.12. West metadata/package output replaces v3.3.0 with
  `west-zephyr-sdk-v3_4_1`. West consumers needing v3.3.0 must retain a prior
  nix-nrf-dev revision; explicit consumer SDK pins are not automatically migrated.
- CI runs shared source gates followed by independent native amd64/ARM64 checks,
  packages and generated-consumer smoke tests. Both native entries gate
  trusted-main release publication; normal PR CI never provisions mutable SDKs.

### Fixed

- Managed west setup clears inherited source/CMake/west configuration before
  workspace initialization. Nordic child processes preserve caller CA settings
  or use the Nix trust store without disabling TLS verification.
- Public core/help/alias routing and workspace configuration guards preserve
  selected workspace ownership without requiring build readiness.
- Session regression client consumes complete OpenOCD Tcl frames rather than
  assuming one socket read contains a reply.
- ARM64 udev VM tests support bounded software emulation. A test-image-only
  systemd 261.1 rule-stat path repair fixes false reload detection while retaining
  original guest assertions; consumer systemd and dependency pins are unchanged.

### Refactored

- Selected Python requirement checking is a separate packaged script executed
  under workspace Python, with subprocess tests and unchanged read-only semantics.

### Documentation

- Replace development plans, status diaries and checkpoints with concise current
  guides, source ownership and accepted backend/source-ownership ADRs. Product
  items retain history; public support documentation no longer cites local
  temporary evidence paths. Reconcile retired references and stale source comments.

### Testing and limitations

- Fresh v3.4.1 compile/link qualification passes 12 amd64 baseline cases and six
  ARM64 cases across nRF52840, nRF5340 CPUAPP/CPUNET and nRF54L15 CPUAPP/FLPR.
  Imported-manifest/module qualification passes four amd64 and two ARM64 builds
  with original inputs preserved. These are host/build results, not device execution.
- SDK-independent routing, workspace/Python ownership, initializer refusals,
  metadata acquisition and selected-requirement parsing have hardware-free gates.
  Full native CI and separate Raspberry Pi ARM64 verification pass.
- Offline nRF52840 SMP/MCUboot debug-key signing/package/tamper checks and ARM/RISC-V
  Python-GDB initialization pass. Production signing, device DFU, recovery and
  debugger attachment remain unqualified.
- Stock NCS v3.4.1 still declares missing `suit-manifest` implementation: strict
  parser qualification records eight failures among 312 amd64 cases and four
  among 156 ARM64 cases. No SDK patch or silent skip hides this upstream defect.
  See [support limits](docs/support-matrix.md); PB-026 remains Blocked on disposition.
- Nordic-managed Linux ARM64 toolchain installation remains unavailable. West is
  experimental and does not promise complete Nordic bundle, Python or hardware parity.

## [0.1.3]

### Added

- Independent existing-workspace source selection for both toolchain backends
  through `source.mode = "workspace"`. Manifest-based source diagnostics,
  scoped CMake package discovery, and conflict/cache checks support repository,
  workspace, and freestanding applications without acquiring or updating sources.
  Managed sources remain the default. nrfutil workspace bootstrap provisions
  tools only; west workspace bootstrap checks caller-prepared Python only.
- Pinned contributor-only Backlog.md tooling, an SDK-free product shell, and
  product backlog tracking RTT/debug work and its hardware acceptance blockers.
- `nix-nrf session start/status` for foreground nRF54L15 CPUAPP OpenOCD
  ownership, private session discovery, and opt-in local debug endpoints.
  Physical state-preservation acceptance remains pending.
- Small RTT/debug test firmware, an approval-gated evidence harness, and
  hardware-free process, real Tcl transport, and binary protocol checks.

### Fixed

- Cold-store CI now materializes pinned contributor source paths through
  writable SDK-free product evaluation before `nix flake check --no-build`.
  This avoids the bun2nix nested-source import failure masked by warm caches,
  without changing pins or acquiring an SDK/toolchain.
- West child processes discard unrelated `PYTHONHOME` and `PYTHONPATH` settings
  so the selected Python environment does not import another interpreter's
  libraries. Parent-shell environment remains unchanged.

### Documentation

- Added application-layout/source-ownership guidance, Python setup and
  troubleshooting, and revision-pinned Zephyr/zephyr-nix research.
- Recorded FLPR capability research separating memory observation from unqualified
  run control, plus the probe-diagnosis handoff. Shared-session hardware acceptance
  remains blocked; no working target-reset or FLPR debugger is claimed.
- Reconciled backend comments, architecture, and contributor guidance with source
  selection and explicit ownership boundaries.

### Testing

- Added 13 public source-workspace regression tests using real west/CMake and
  disposable Git manifest imports, plus an opt-in no-bootstrap firmware matrix.
- Qualified 16 single-image/sysbuild builds across all application layouts with
  both backends on NCS v3.3.0, x86_64-linux, and XIAO nRF54L15 CPUAPP. Evidence
  includes source/compiler/module selection, extra-module symbols, and ELF hashes;
  build success is not hardware execution proof.
- Added session process/native-Tcl and fixture binary-protocol checks. Physical
  RTT emission, running/halted preservation, and combined RTT/GDB remain unverified.
- Added local-only independent SDK fixtures and seven disposable Git/west
  lifecycle tests. Qualified four additional single-image/sysbuild builds through
  both backends with an application-owned imported NCS v3.3.0 manifest, relocated
  SDK sources, and a manifest-owned linked module. Source-preservation and negative
  import/conflict checks passed; no downloads or hardware execution involved.

## [0.1.2]

### Fixed

- Default `nrfutil` now combines the Nixpkgs core with sdk-manager `1.16.1`
  from Nordic's versioned, content-pinned package archive. This replaces the
  legacy mutable executable supply path and keeps the NCS v3.3.0 toolchain
  contract stable when a consumer follows another Nixpkgs revision.

### Documentation

- Consolidated and tightened installation, backend, architecture, hardware,
  test, and contributor guidance. Updated supporting workflow and source
  comments to match current contracts.

### Testing

- Make release-note tests derive current notes from `release.json` instead of
  requiring prose from an earlier release.

## [0.1.1]

### Documentation

- README install section restructured into two concise methods: **A —
  Automated** (recommended, via the `init-project` flake app) and **B —
  Manual** (existing project, hand-written `flake.nix` calling
  `mkNrfShell`). The standalone "Choose a backend" section was removed.
- New `docs/install.md`: detailed step-by-step install guide covering
  prerequisites, what gets installed and where, release-tag pinning,
  backend choice, and verification.

## [0.1.0]

First independent nix-nrf-dev release. This entry covers the whole repository
history because no prior tag or release exists.

### Flake and consumer surface

- Reusable flake for `x86_64-linux`: packages (`openocd-master`,
  `openocd-master-unwrapped`, `nrfutil`, `nix-nrf`, `udev-rules`,
  `west-zephyr-sdk-v3_3_0`), `apps.<system>.init-project`, `lib.<system>.mkNrfShell`,
  `devShells.default`/`clean-env-test`, `nixosModules.udevRules`, and a full
  check set.
- Public `mkNrfShell` dev-shell factory with two backends: the default
  **nrfutil** backend (Nordic sdk-manager-managed SDK/toolchain, lazy
  bootstrap, toolchain environment scoped to the `west` wrapper) and the
  experimental **west** backend (Nix-owned exact Zephyr SDK + host tools,
  mutable west workspace + version-local venv). `ncsVersion` is required and
  never defaults to `latest`.

### `nix-nrf` CLI

- `nix-nrf versions` (delegates to sdk-manager search by default, west
  metadata for the west backend), `nix-nrf probes` (read-only CMSIS-DAP
  probe/target identification), `nix-nrf bootstrap` (SDK/toolchain
  provisioning with approval gating), and `nix-nrf doctor` (read-only
  SDK/toolchain and probe-access diagnostics with exact udev-rule
  remediation).
- New global `-V`/`--version` printing exactly the canonical project version
  embedded from `release.json` (`nix-nrf 0.1.0`), independent from the
  selected NCS version.

### Project initializer

- `nix run ...#init-project -- ./my-project` generates a consumer flake
  pinned to one concrete NCS release (never `latest`), with collision-free,
  symlink-safe, non-overwriting output.

### Hardware support

- Pinned from-source OpenOCD with nRF5340 and nRF54L15 flash recipes and
  probe access verified on real hardware.
- Relocation udev package exposing the upstream OpenOCD rule, a narrow NixOS
  module that only sets `services.udev.packages`, and an explicit `plugdev`
  group/membership policy the consumer configures.

### Testing and validation

- Deterministic fake-boundary flake checks (bootstrap, doctor, probes,
  initializer, west backend), booted NixOS VM udev gate, pure west
  metadata/toolchain consistency gates, TCL flash-recipe semantic tests, and
  the release/changelog consistency gate.
- Scheduled latest-NCS initializer validation with bounded-outage
  semantics; manual clean-room bootstrap and hardware workflows with
  resource telemetry recorded to run logs and job summaries.

### Release automation

- Canonical `release.json` manifest (strict stable SemVer) loaded by
  `nix/release.nix`, a fail-closed `scripts/release.py` consistency check
  with regression tests, and a trusted-main-only reusable GitHub Release
  workflow (`workflow_call`) that creates the `v<version>` tag and Release
  after all normal CI checks pass and no-ops on an already published
  version. Pull requests can never publish.

### Key limitations

- `x86_64-linux` only.
- West backend metadata currently covers NCS `v3.3.0`.
- Hardware flashing/probe runs and real clean-room bootstraps remain manual
  (self-hosted runner, explicit approval); normal CI and checks never
  download SDK/toolchain bundles or query Nordic live.
