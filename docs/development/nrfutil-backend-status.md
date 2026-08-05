# nRF Util Backend Status

Status of the nrfutil backend after the Nixpkgs migration. The previous
custom-launcher/core-bootstrap direction (see git history) was rejected and
removed: there is no custom `nrfutil-core` package, no launcher/core tarball
pinning, no runtime `nrfutil install sdk-manager=<version>` step, and no
controlled `NRFUTIL_HOME` scheme.

The nrfutil backend remains the default and its behavior is unchanged. It is
no longer the *only* implemented backend: the experimental west backend
(`backend = "west"`, v3.3.0 / x86_64-linux only) is also public — see
`docs/development/west-backend-status.md`.

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
  and builds the XIAO nRF54L15 sysbuild blinky (see
  `docs/development/clean-bootstrap-versioning-plan.md`, Phase 3 evidence).

## Open follow-up (not this phase)

- Version-keyed SDK/toolchain CI caching — see
  `docs/development/clean-bootstrap-versioning-plan.md` (Phase 3 CI-split
  discussion; the current manual clean-room workflow bypasses any cache).
- Parallel-bootstrap locking: confirm whether sdk-manager serializes installs
  itself; document a lock as follow-up if it does not.
- Nix-native `sdk-nrf` backend — reserved, rejected at evaluation until
  implemented.
- Scheduled version-discovery PR automation — needs separate workflow
  permission, update policy, and failure-semantics design.
- Doctor extras from `goals.md` 3.3: `ZEPHYR_BASE`/multilib checks, a
  shellHook "warn once" mode, and a standalone `packages.nrf-doctor` output.
