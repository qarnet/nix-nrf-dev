# Repository architecture

Maintainer reference for source ownership and construction. User-facing backend
behavior lives in [backends.md](../backends.md). Lasting design rationale lives
in [architecture decision records](../adr/README.md); execution history and
acceptance evidence belong in [the product backlog](../product/README.md).

## Public outputs

- Root `flake.nix` supports `x86_64-linux` and `aarch64-linux` and exports per-system outputs.
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

`nix/platforms.nix` owns native host backend capabilities, repository/initializer
presets, and multilib defaults. It does not describe firmware target architectures.
The public factory keeps its nrfutil default; ARM64 rejects that backend rather
than silently selecting west. Per-host sdk-manager assets remain pinned even
where Nordic-managed firmware workflows are unavailable.

`nix/flake/dev-shells.nix` creates repository default and clean-environment
shells, plus SDK-free product and hardware-tests shells. Backlog.md and the
hardware harness's Python ELF parser are contributor-only and do not enter
consumer `mkNrfShell` packages. `nix/flake/checks/default.nix` combines domain
check modules. Duplicate
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

`nix/backends/west-core.nix` packages SDK-independent core west and registration
inspection in `bin/commands/nix-nrf-west-core`. Both public wrappers classify
core requests before bootstrap; workspace-dependent core commands bind selected
configuration without requiring NCS source/Python readiness. SDK extensions stay
on their backend's original scoped execution path. The same read-only inspector
feeds doctor's additive `west` states without importing extension implementations.

`nix/backends/source.nix` packages read-only existing-workspace resolution in
`bin/commands/nix-nrf-source`. It uses west's manifest API rather than a hard-coded
Zephyr directory. Workspace roots are anchored at shell entry, while toolchain
readiness stays backend-owned. Managed mode does not construct the resolver.
Existing-source bootstrap never updates manifests/repositories or repairs Python
environments. Public behavior and examples live in [application-types.md](../application-types.md).

## Commands and initialization

`nix/commands/default.nix` builds the public `nix-nrf` dispatcher. It routes
`versions`, `probes`, `bootstrap`, `doctor`, and `session` to internal commands installed
under `$out/libexec/nix-nrf/`. `nix/init-project/default.nix` packages the
separate public `nix-nrf-init-project` executable.
Existing-workspace shells additionally route `source` to their exact resolver.

`nix/init-project/default.nix` packages initializer with pinned nrfutil path,
west version metadata, and skeleton. `bin/commands/nix-nrf-init-project` owns
CLI parsing, latest resolution, template rendering, collision checks, and
symlink-safe writes. It runs neither generated commands nor hooks.

`nix/lib/mk-python-command.nix` packages internal Python commands. Callers pass
ordered wrapper arguments. Helper installs script, patches its shebang, then
wraps it once.

`bin/commands/nix-nrf-session` owns foreground OpenOCD lifecycle and same-user
probe locks. `nix/commands/session.nix` injects exact OpenOCD and doctor paths.
It does not share flash-recipe lifecycle or bootstrap SDK state. The session
JSON is client discovery metadata, not authorization to kill its recorded PIDs.

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
- `tests/product/test_backlog.py` exercises the pinned Backlog.md CLI against
  the repository configuration in a disposable Git repository. The product
  check also validates real backlog items without changing them.
- `tests/fixtures/` contains fake sdk-manager and west-workspace helpers.
- `tests/unit/test_source_workspace.py` exercises public shell hooks, real west,
  and CMake package discovery with synthetic source packages. The opt-in
  `tests/application-types/run.py` records real firmware-build qualification
  separately and never provisions dependencies or accesses hardware.
- `tests/application-types/local_workspace.py` prepares a bounded local-only SDK
  fixture with borrowed Git objects and independent working files/metadata.
   `imported_workspace.py` qualifies application-owned imports with host-supported opt-in
  real builds; `test_local_sdk_fixture.py` verifies preparation/refusals with
  disposable Git repositories in normal CI. Shared clones require retained seed
  object stores; procedures and limits live in `tests/application-types/README.md`.
- `tests/unit/test_nix_nrf_session.py` tests owner/client process boundaries and
  actual pinned OpenOCD Tcl traffic through a no-hardware dummy target.
- `tests/firmware/debug-fixture/` contains small CPUAPP verification firmware;
  `tests/hardware/debug/` owns the approval-gated evidence harness and decoder.
  The C serializer also supplies real encoded bytes to host protocol tests.
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
- Core west never triggers SDK bootstrap. Explicit `init`/`update`/writable
  `config`/`forall` remain caller-requested operations, not readiness repair.

## CI ownership

`scripts/ci.py` runs source-only formatting, pre-commit, and release-consistency
checks once in the shared job, including both-host evaluation. The dependent
native matrix dynamically enumerates every remaining check and all package
outputs for its own system. `fail-fast: false` preserves independent failures.
Trusted-main release needs shared and both native entries; PRs do not publish.
Branch protection must require their reported names: `Shared source checks`,
`Native (x86_64-linux)` and `Native (aarch64-linux)`, not the internal job ID
`check`.
`nix/flake/checks/udev-systemd.nix` backports a same-version rule-stat path fix
only into the test image. Both boot stages keep correct change detection through
NixOS's symlinked rules tree. Consumer packages and dependency pins are unchanged.
ARM64 permits QEMU TCG and uses bounded device-only coldplug and startup waits.
It does not qualify subsystem/driver-event stress. Original guest assertions
remain intact; amd64 retains its KVM requirement.
