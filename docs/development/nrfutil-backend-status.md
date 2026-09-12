# nrfutil backend

`nrfutil` is default backend. Nordic sdk-manager manages SDK and toolchain
state under `$HOME`. Experimental `west` backend supports NCS `v3.3.0` on
`x86_64-linux`. See [west-backend-status.md](west-backend-status.md).

## Current behavior

- Nixpkgs provides the `nrfutil` core. This repository composes it with
  sdk-manager `1.16.1` from Nordic's versioned package archive and fixed
  content hash. `flake.lock` pins the core's Nixpkgs revision; a consumer's
  `nixpkgs.follows` input cannot change the default sdk-manager version.
- `mkNrfShell` requires `ncsVersion`. Optional `toolchainBundleId` selects
  exact bundle. `autoBootstrap` defaults to `true`. `nrfutilPackage` is an
  advanced package override.
- Internal `nix-nrf bootstrap` checks selected SDK and toolchain. With
  `autoBootstrap = true`, scoped `west` wrapper installs missing components
  only after confirmation. With `false`, it reports required command without
  changing state. Shell entry uses read-only `--check` path.
- `nix-nrf versions` delegates to `nrfutil sdk-manager search`. Repository
  has no static nrfutil release list. `nix-nrf probes` has no standalone
  binary or package.
- `nix-nrf doctor` runs read-only SDK check and probe diagnostics. It prefers
  explicit CMSIS-DAP v2 bulk USB, then hidraw, then legacy USB fallback. It
  uses `os.access` for production node access and prints udev setup without
  running `sudo`.
- Packaged nrfutil depends on `segger-jlink-headless`. Flake accepts J-Link
  license with `segger-jlink.acceptLicense = true`. sdk-manager-only package
  composition is unavailable.
- CI builds `.#nrfutil`, `.#nix-nrf`, and `.#udev-rules`; it smoke-tests CLI
  help and verifies removed standalone commands are absent.
- `tests/clean-room/run.sh` manually bootstraps NCS `v3.3.0` in isolated
  `HOME`, re-enters shell, and builds XIAO nRF54L15 sysbuild blinky. Normal PR
  CI never downloads SDK or toolchain bundles.

## Open work

[roadmap.md](roadmap.md) tracks caching, automation, and doctor work.
[sdk-nrf-feasibility-draft.md](sdk-nrf-feasibility-draft.md) tracks research
for pure Nix `sdk-nrf` backend. Verify whether sdk-manager serializes parallel
bootstrap installs before adding locking.
