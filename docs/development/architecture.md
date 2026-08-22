# Repository architecture

Maintainer reference for source ownership and construction. User-facing backend
behavior lives in [backends.md](../backends.md). Backend implementation notes
live in [nrfutil-backend-status.md](nrfutil-backend-status.md) and
[west-backend-status.md](west-backend-status.md).

## Public outputs

- Root `flake.nix` supports `x86_64-linux` and exports per-system outputs.
- `lib.<system>.mkNrfShell` creates NCS development shells.
- `packages.<system>.nix-nrf` is command facade for `nix run .# -- ...`.
- `apps.<system>.init-project` creates consumer `.envrc` and `flake.nix`.
- `packages.<system>.udev-rules` relocates upstream `60-openocd.rules`.
- `nixosModules.udevRules` adds that package to `services.udev.packages`. It
  does not create `plugdev` or change user groups.

## Construction flow

`nix/flake/per-system.nix` imports configured Nixpkgs, formatter, hooks,
components, shells, and checks. `nix/flake/components.nix` creates OpenOCD,
udev rules, nrfutil, `nix-nrf`, west builders, and `mkNrfShell`.

`nix/flake/dev-shells.nix` creates repository default and clean-environment
shells. `nix/flake/checks/default.nix` combines domain check modules. Duplicate
check keys fail during Nix attrset construction.

## Backend boundaries

`nix/backends/default.nix` owns public `mkNrfShell` argument validation and
backend dispatch. It requires `ncsVersion`, accepts `nrfutil` and experimental
`west`, and rejects unsupported combinations during evaluation.

`nix/backends/nrfutil/` owns sdk-manager shell behavior. Its scoped `west`
wrapper loads Nordic toolchain environment only in west process tree. Shell
entry uses read-only bootstrap check. `bootstrap.nix` packages internal
`nix-nrf bootstrap` command.

`nix/backends/west/` owns experimental hybrid backend. Nix provides Zephyr SDK,
host tools, and Python. Mutable west workspace and version-local venv contain
NCS source and Python requirements. `versions.nix` holds every release-specific
version, requirement path, asset URL, and hash.

Backends do not import each other's implementation. Shared code receives
backend-specific commands and configuration as explicit arguments.

## Commands and initialization

`nix/commands/default.nix` builds the public `nix-nrf` dispatcher. It routes
`versions`, `probes`, `bootstrap`, and `doctor` to internal commands installed
under `$out/libexec/nix-nrf/`. `nix/init-project/default.nix` packages the
separate public `nix-nrf-init-project` executable.

`nix/init-project/default.nix` packages initializer with pinned nrfutil path,
west version metadata, and skeleton. `bin/commands/nix-nrf-init-project` owns
CLI parsing, latest resolution, template rendering, collision checks, and
symlink-safe writes. It runs neither generated commands nor hooks.

`nix/lib/mk-python-command.nix` packages internal Python commands. Callers pass
ordered wrapper arguments. Helper installs script, patches its shebang, then
wraps it once.

## Hardware support

`nix/hardware/openocd.nix` pins OpenOCD source. `nix/hardware/udev-rules.nix`
copies pinned `60-openocd.rules` without modifying it. Host configuration owns
`plugdev` group and user membership.

`tcl/nrf53_flash.tcl` handles nRF5340 app and net core flashing. It can recover
locked app core only when caller permits it. `tcl/nrf54l_flash.tcl` writes and
verifies nRF54L RRAM images. See [hardware.md](../hardware.md) before running
either recipe on a board.

## Release files

`release.json` is only project-version source. `nix/release.nix` validates and
exports it. `scripts/release.py` checks matching changelog row and release
body. CI invokes `.github/workflows/release.yml` only after trusted push to
`main` passes normal checks. Pull requests cannot publish releases.

## Tests

- `nix/flake/checks/` contains deterministic evaluation, packaging, shell,
  metadata, and NixOS module checks.
- `tests/unit/` contains fake-boundary subprocess tests.
- `tests/fixtures/` contains fake sdk-manager and west-workspace helpers.
- `tests/tcl/test_flash_recipes.tcl` runs real recipes against fake OpenOCD
  commands and checks command order, arguments, and recovery branches.
- `tests/clean-room/run.sh`, `tests/west-backend/run.sh`, and
  `tests/hardware/run.sh` use real downloads or hardware. They require explicit
  approval and are not normal CI checks.

## Invariants

- `nrfutil` is default backend. Omitted and explicit `backend = "nrfutil"`
  create same derivation.
- `ncsVersion` is required. Initializer replaces `latest` with concrete
  release before it writes consumer flake.
- Shell entry does not change SDK state. Mutation needs explicit bootstrap or
  scoped `west` invocation and approval when state is missing.
- Invalid backend or release never falls back silently.
- Initializer refuses overwrite and symlink escapes, and uses
  `renameat2(RENAME_NOREPLACE)` for new destination.
- Normal checks do not run mutable NCS setup, real hardware work, or live
  Nordic queries. Scheduled/manual latest initializer workflow is exception.
