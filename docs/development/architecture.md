# Repository Architecture

Current maintainer reference for the nix-nrf-dev repository after the
repository refactor (see `docs/development/archive/` for the phased plan
history). Backend-specific proof and behavior details live in
`docs/development/west-backend-status.md` and
`docs/development/nrfutil-backend-status.md`; this document describes
ownership and construction only.

## 1. Public entry points

- Root `flake.nix` — thin flake: inputs, `eachDefaultSystem` delegating to
  `nix/flake/per-system.nix`, plus the non-system `templates.default` and
  `nixosModules.default` outputs.
- `nix/flake/per-system.nix` — per-system construction: configured Nixpkgs
  (allowUnfree + SEGGER acceptance), components, formatter/pre-commit,
  checks, dev shells.
- `lib.<system>.mkNrfShell` — public dev-shell factory (dispatcher
  `nix/backends/default.nix`), exported via `nix/flake/per-system.nix`
  `lib` output.
- `packages.<system>.nix-nrf` — standalone CLI facade (`nix run .# -- ...`).
- `nixosModules.default` — activates the packaged udev rules
  (`services.udev.packages = [ self.packages.<system>.udev-rules ]`).
- `templates.default` — consumer skeleton flake.

## 2. Construction flow

- `nix/flake/components.nix` is the single per-system composition root: it
  builds OpenOCD (wrapped/unwrapped), udev rules, the composed nrfutil, the
  standalone `nix-nrf` dispatcher, west metadata/builders, and the public
  `mkNrfShell`.
- `nix/flake/dev-shells.nix` composes `mkNrfShell` into the `default` and
  `clean-env-test` shells.
- `nix/flake/checks/*.nix` build the check derivations; `checks/default.nix`
  composes them (duplicate keys are a Nix attrset construction error).
- Plain Nix imports throughout; no flake-parts or other framework.

## 3. Backend ownership

- `nix/backends/default.nix` — public `mkNrfShell` dispatcher: argument
  signature, supported-backend list, required `ncsVersion`, west release
  validation, west-only rejection of `toolchainBundleId` / non-default
  `nrfutilPackage`, and dispatch. It constructs nothing.
- `nix/backends/nrfutil/` — default backend: `default.nix` (entry point over
  internal deps incl. the shared nix-nrf constructor), `shell.nix` (scoped
  toolchain-env shell, lazy bootstrap west wrapper, non-mutating hook),
  `bootstrap.nix` (SDK/toolchain bootstrap command module).
- `nix/backends/west/` — experimental hybrid backend: `default.nix`
  (metadata-selected Python, exact Zephyr SDK, west bootstrap/versions
  command modules, backend-aware nix-nrf, doctor label), `shell.nix` (public
  west dev shell), `bootstrap.nix`, `versions.nix`, `versions-command.nix`,
  `zephyr-sdk.nix`.
- No backend imports implementation details from the other backend; shared
  code receives backend commands/configuration as explicit arguments.

## 4. Shared ownership

- `nix/commands/` — `default.nix` (backend-aware `nix-nrf` dispatcher),
  `doctor.nix`, `probes.nix`. Backend constructors inject exact command
  module store paths (`versionsCommand`, `bootstrapCommand`); the doctor and
  the dispatcher share one identical bootstrap store path per shell.
- `nix/hardware/` — `openocd.nix` (from-source OpenOCD build) and
  `udev-rules.nix` (relocation package for the pinned 60-openocd.rules).
- `nix/lib/mk-python-command.nix` — narrow packaging helper for the internal
  Python command modules: install to `$out/libexec/nix-nrf/<destination>`,
  patch shebang, single ordered `wrapProgram`. Callers own every wrapper
  argument.
- Default nrfutil bootstrap module lives at
  `nix/backends/nrfutil/bootstrap.nix`; `nix/commands/default.nix` imports
  it unless a west `bootstrapCommand` is injected.

## 5. Script layout under `bin/`

- `bin/backends/nrfutil/nix-nrf-bootstrap`,
  `bin/backends/west/nix-nrf-west-bootstrap`,
  `bin/backends/west/nix-nrf-west-versions` — backend command scripts.
- `bin/commands/nix-nrf-doctor`, `bin/commands/nix-nrf-probes` — shared
  command scripts.
- Script basenames are stable; each script is packaged by exactly one Nix
  command module and installed **only** under `$out/libexec/nix-nrf/` (no
  standalone `$out/bin` commands) so public invocation stays exclusively
  through the `nix-nrf` facade.

## 6. Tests

- Flake checks split by domain: `nix/flake/checks/` — `backend-selector.nix`
  (evaluation gate), `nrfutil.nix` (bootstrap tests + quoting), `west.nix`
  (bootstrap/versions/metadata/quoting/shell-boundary), `core.nix`
  (doctor/help/probes/udev wiring). See README for the full 15-check list.
- Unit tests in `tests/unit/` run fake-boundary subprocess suites (sandboxed
  stdlib) wired into the corresponding checks; `tests/fixtures/`
  `west-workspace.py` is the shared fake workspace creator covered by
  `tests/unit/test_west_workspace_fixture.py` inside `checks.west-bootstrap-tests`.
- Manual harnesses require explicit approval and real resources:
  `tests/clean-room/run.sh` (real SDK bootstrap + blinky build),
  `tests/west-backend/run.sh` (real west workspace), `tests/hardware/run.sh`
  (self-hosted hardware runner). Dry runs are gated by
  `NIX_NRF_CLEAN_DRY_RUN=1` / `NIX_NRF_WEST_DRY_RUN=1`.

## 7. Adding/changing

- New west metadata release: add an entry to
  `nix/backends/west/versions.nix` (version, Python, SDK assets, hashes,
  requirements, constraints); no builder or command code changes.
- New backend: add `nix/backends/<name>/` with a constructor, register it in
  the dispatcher's supported list, and keep the no-cross-import rule.
- New shared command: add `bin/commands/<name>` + a module using
  `mk-python-command.nix`, and a dispatch case in `nix/commands/default.nix`.
- New check without growing root flake: add it to the appropriate module in
  `nix/flake/checks/` and name it in `checks/default.nix`.

## 8. Invariants

- `nrfutil` is the default backend; omitted and explicit `backend =
  "nrfutil"` produce identical derivations.
- `ncsVersion` is required for both backends.
- Shell entry stays non-mutating (read-only `--check` bootstrap path);
  mutation happens only through an explicit `nix-nrf bootstrap` invocation or
  the scoped `west` wrapper, and is approval-gated (interactive confirmation
  unless `NIX_NRF_BOOTSTRAP_YES=1` / `--yes`) when state is missing.
- No backend silently falls back: unsupported values fail Nix evaluation
  naming the supported list.
- Normal checks never perform mutable NCS workspace `west update`, pip
  workspace setup, sdk-manager bundle installs, or hardware access (fake
  boundaries or dry runs only); fixed Nix fetch/build inputs — such as the
  west backend's exact Zephyr SDK package assets — may still be realized by
  normal builds and checks.
- Hardware and real clean-room runs require explicit user approval and are
  never part of the default gate.
