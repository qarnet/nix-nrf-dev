# nRF Util Backend Status

Current status of the nrfutil backend. nrfutil is the default backend and
provides the NCS toolchain environment via Nordic sdk-manager (Nixpkgs
packaged nrfutil with the sdk-manager extension). The experimental west
backend (`backend = "west"`, v3.3.0 / x86_64-linux only) is an additional
backend — see `docs/development/west-backend-status.md`.

## Current state

- nrfutil and the sdk-manager extension come from Nixpkgs:
  `pkgs.nrfutil.withExtensions [ "nrfutil-sdk-manager" ]`, pinned via
  `flake.lock` on `nixos-unstable`. Extension versions and hashes are
  Nixpkgs' responsibility.
- `mkNrfShell` requires `ncsVersion` (no default/`"latest"` alias) and accepts
  optional `toolchainBundleId` (exact bundle), `autoBootstrap` (default true),
  and `nrfutilPackage` (advanced package override). `west` selects
  `--ncs-version` or `--toolchain-bundle-id` accordingly.
- SDK/toolchain bootstrap is the internal `nix-nrf bootstrap` command module
  (`$out/libexec/nix-nrf/bootstrap`, wrapped with the exact selected nrfutil
  executable; no standalone `nrf-bootstrap` binary or package). The `west`
  wrapper bootstraps lazily on every invocation (`autoBootstrap = true`):
  it checks the configured SDK source and selected toolchain, installs only
  when something is missing (with confirmation), exports `ZEPHYR_BASE` inside
  west's process, then loads the scoped toolchain env. With
  `autoBootstrap = false`, west checks only and reports the exact
  `nix-nrf bootstrap` remediation without mutating. Shell entry stays
  non-mutating (read-only `--check` path through the same helper).
  Missing/install paths are proven by the fake-boundary
  `checks.bootstrap-tests` unit suite; normal CI never downloads
  SDK/toolchain bundles.
- `nix-nrf versions` delegates to `nrfutil sdk-manager search`; sdk-manager is
  the runtime authority for available NCS versions. No repository-owned
  supported-version list exists. `nix-nrf probes` runs the internal probe
  command module (`$out/libexec/nix-nrf/probes`); there is no standalone
  `nrf-probes` binary or package.
- `nix-nrf doctor` runs the internal read-only diagnostics command module
  (`$out/libexec/nix-nrf/doctor`): it checks the configured SDK/toolchain via
  the same bootstrap module's read-only `--check --quiet --print-sdk-path`
  path (never a mutating invocation), discovers CMSIS-DAP/J-Link candidates
  from sysfs descriptors, classifies hidraw/USB node access with `os.access`,
  and prints exact NixOS/generic-Linux udev remediation without sudo. Fixture
  tests are `checks.doctor-tests`; `packages.udev-rules` +
  `nixosModules.default` provide the remediated OpenOCD udev rules
  (`checks.udev-rules` proves the installed rule is byte-identical to the
  pinned OpenOCD contrib file).
- The packaged nrfutil derivation unconditionally depends on
  `segger-jlink-headless`; the flake config sets
  `segger-jlink.acceptLicense = true`. There is no sdk-manager-only
  composition that avoids J-Link.
- CI builds `.#nrfutil`, `.#nix-nrf`, and `.#udev-rules`, smoke-tests
  `nix-nrf --help`, `nix-nrf versions --help`, `nix-nrf probes --help`,
  `nix-nrf bootstrap --help`, and `nix-nrf doctor --help`, verifies unknown
  subcommands exit 2, and checks the devshell provides `nrfutil`, `nix-nrf`,
  `openocd`, `west` while `nrf-probes` is absent.
- Clean-home bootstrap/build is proven: `tests/clean-room/run.sh` bootstraps
  NCS v3.3.0 and the selected toolchain under an isolated, script-created
  HOME, re-enters the shell, derives `ZEPHYR_BASE` from that installation,
  and builds the XIAO nRF54L15 sysbuild blinky. It runs manually
  (`.github/workflows/clean-room.yml`, `workflow_dispatch` on the
  `nrf-hardware` runner); normal PR CI never downloads SDK/toolchain bundles.
  See `tests/clean-room/README.md` for the full contract.

## Future work

Open direction for the nrfutil backend and its surroundings is tracked in
`docs/development/roadmap.md` (CI caching, automation, doctor extras) and in
`docs/development/sdk-nrf-feasibility-draft.md` for the pure Nix-native
`sdk-nrf` backend research question (reserved, rejected at evaluation until
implemented). Parallel-bootstrap locking — confirming whether sdk-manager
serializes installs itself — remains an open verification item.
