# Changelog

All notable changes to the nix-nrf-dev project (and its `nix-nrf` CLI).

> The project version is independent from Nordic NCS versions. `release.json`
> holds the canonical strict SemVer of this nix-nrf-dev release; `ncsVersion`
> (e.g. `v3.3.0`) is an upstream SDK selection and tested baseline, never the
> project version.

| Version | Date | Highlights |
|---|---|---|
| [0.1.1](#011) | 2026-08-17 | Documentation: install section split into automated (`init-project`) and manual (hand-written `flake.nix`) quick start methods; new detailed install guide (`docs/install.md`) |
| [0.1.0](#010) | 2026-08-08 | First release: reusable x86_64-linux flake and public `mkNrfShell` (default nrfutil/sdk-manager backend, experimental west backend); `nix-nrf` CLI (`versions`, `probes`, `bootstrap`, `doctor`, `--version`); dynamic concrete-version `init-project` app; pinned OpenOCD, udev package, narrow NixOS module with explicit plugdev policy; NCS v3.3.0 tested baseline with nRF5340/nRF54L15 flash and probe verification; deterministic flake/unit/VM/metadata checks, scheduled latest-NCS validation, manual hardware/clean-room workflows, clean-room telemetry; release automation (consistency gate, trusted-main GitHub Release workflow) |

## [Unreleased]

### Fixed

- Default `nrfutil` now combines the Nixpkgs core with sdk-manager `1.16.1`
  from Nordic's versioned, content-pinned package archive. This replaces the
  legacy mutable executable supply path and keeps the NCS v3.3.0 toolchain
  contract stable when a consumer follows another Nixpkgs revision.

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
