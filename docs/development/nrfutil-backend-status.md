# nRF Util Backend Status

Status of the nrfutil backend after the Nixpkgs migration. The previous
custom-launcher/core-bootstrap direction (see git history) was rejected and
removed: there is no custom `nrfutil-core` package, no launcher/core tarball
pinning, no runtime `nrfutil install sdk-manager=<version>` step, and no
controlled `NRFUTIL_HOME` scheme.

## Current state

- nrfutil and the sdk-manager extension come from Nixpkgs:
  `pkgs.nrfutil.withExtensions [ "nrfutil-sdk-manager" ]`, pinned via
  `flake.lock` on `nixos-unstable`. Extension versions and hashes are
  Nixpkgs' responsibility.
- `mkNrfShell` requires `ncsVersion` (no default/`"latest"` alias) and accepts
  optional `toolchainBundleId` (exact bundle) and `nrfutilPackage` (advanced
  package override). `west` selects `--ncs-version` or
  `--toolchain-bundle-id` accordingly. Failure diagnostics distinguish missing
  SDK source from toolchain selection: `nrfutil sdk-manager install
  <ncsVersion>` alone, plus `nrfutil sdk-manager toolchain install
  --toolchain-bundle-id <bundle-id>` when an exact bundle is configured.
- `nrf-sdk-versions` delegates to `nrfutil sdk-manager search`; sdk-manager is
  the runtime authority for available NCS versions. No repository-owned
  supported-version list exists.
- The packaged nrfutil derivation unconditionally depends on
  `segger-jlink-headless`; the flake config sets
  `segger-jlink.acceptLicense = true`. There is no sdk-manager-only
  composition that avoids J-Link.
- CI builds `.#nrfutil` and `.#nrf-sdk-versions`, smoke-tests nrfutil
  version, runs `nrf-sdk-versions --help`, and checks the devshell provides
  `nrfutil`, `nrf-sdk-versions`, `openocd`, `nrf-probes`.

## Open follow-up (not this phase)

- Lazy SDK/toolchain bootstrap (`autoBootstrap` / explicit `nrf-bootstrap`)
  and clean-home blinky build verification — see
  `docs/development/clean-bootstrap-versioning-plan.md`.
- Nix-native `sdk-nrf` backend — reserved, rejected at evaluation until
  implemented.
- Scheduled version-discovery PR automation — needs separate workflow
  permission, update policy, and failure-semantics design.
