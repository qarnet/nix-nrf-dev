# `nix-nrf` CLI Phase 2 Handoff

## Goal

Complete probe-command migration from standalone `nrf-probes` packaging to an
internal `nix-nrf probes` command module. Migrate repository callers and remove
the old public binary/package alias without changing probe discovery behavior.

User-observable command after this phase:

```text
nix-nrf probes [SERIAL ...]
nix-nrf probes --find FAMILY
```

`nrf-probes` and `packages.nrf-probes` must no longer exist.

## Grounding

- Phase 1 dispatcher: `nix/nix-nrf.nix` delegates `probes` to an exact store
  path supplied as `nrfProbesPackage`.
- Probe implementation: `bin/nrf-probes`, a 250-line Python script using
  `argparse`, Linux sysfs, and `openocd`.
- Probe packaging: `nix/nrf-probes.nix` installs and wraps that script with
  `openocd` and `coreutils` on PATH.
- Public wiring: `flake.nix` exports `packages.nrf-probes`; both
  `flake.nix` and `nix/mk-nrf-shell.nix` pass/add that package separately.
- Active repository callers: `.github/workflows/ci.yml`, `README.md`,
  `CONTRIBUTING.md`, `tests/hardware/run.sh`, `tests/hardware/README.md`,
  `treefmt.nix`, `goals.md`, and current development status/plan documents.
- Probe behavior to preserve lives in `bin/nrf-probes`: table output;
  serial filtering; family/chip matching; `--find` exit 0 for one match, 1 for
  no match, 2 for ambiguity; read-only OpenOCD fingerprinting.

## Exact migration

### Source and internal package

Use Git-aware moves so history follows the implementation:

```text
bin/nrf-probes       -> bin/nix-nrf-probes
nix/nrf-probes.nix   -> nix/nix-nrf-probes.nix
```

The Python source remains one command module in this phase; do not refactor its
probe logic. Update command-facing text only:

- top comments and usage examples use `nix-nrf probes`;
- `argparse.ArgumentParser` sets `prog="nix-nrf probes"` so delegated help
  displays public syntax rather than internal filename;
- user-facing error prefixes use `nix-nrf probes:`.

Keep all options, table columns, matching rules, OpenOCD commands, and exit
codes unchanged.

Change `nix/nix-nrf-probes.nix` into an internal derivation. Install wrapped
command at:

```text
$out/libexec/nix-nrf/probes
```

Do not install any `$out/bin/nrf-probes` or other public compatibility binary.
Keep the current wrapped runtime environment: Python shebang patched and
`openocd` plus `coreutils` available to implementation.

### Dispatcher ownership

Change `nix/nix-nrf.nix` arguments to:

```nix
{
  pkgs,
  nrfutilPackage,
  openocd,
}:
```

Import `./nix-nrf-probes.nix` internally with `pkgs` and `openocd`, and have
the fixed dispatcher execute its exact
`$out/libexec/nix-nrf/probes` path. `nix-nrf` now owns its project command
module rather than receiving a public probe package from callers.

Version delegation remains unchanged and continues using exact selected
`nrfutilPackage` path.

### Flake and shell wiring

In `flake.nix`:

- remove standalone `nrf-probes` instantiation;
- remove `packages.nrf-probes` export;
- construct `nix-nrf` with `openocd = openocd-master`;
- stop passing `nrf-probes` into `mkNrfShell`.

In `nix/mk-nrf-shell.nix`:

- remove top-level `nrf-probes` dependency;
- construct `nix-nrf` with `openocd = openocd-master` and caller-selected
  `nrfutilPackage`;
- remove standalone probe package from shell packages;
- update comments to state probe command is `nix-nrf probes`.

Do not change `west`, `openocd`, or `nrfutil` public command names.

### Repository caller migration

Update active callers atomically:

- `tests/hardware/run.sh`: command presence, enumeration, and both `--find`
  calls use `nix-nrf probes`; preserve test labels and exit handling where
  useful, but diagnostics must name current command.
- `tests/hardware/README.md`: procedures use `nix-nrf probes`.
- `.github/workflows/ci.yml`: stop building/smoke-running `.#nrf-probes`;
  retain `nix-nrf probes --help`; devshell and template checks require
  `nix-nrf` and assert `nrf-probes` is absent.
- `README.md`: remove compatibility language and `packages.nrf-probes` output;
  document only `nix-nrf probes`.
- `CONTRIBUTING.md`, `treefmt.nix`, `goals.md`,
  `docs/development/archive/nix-nrf-cli-plan.md`, and
  `docs/development/nrfutil-backend-status.md`: update live paths, commands,
  package inventories, planned composition, and status.
- Update live/future references in
  `docs/development/clean-bootstrap-versioning-plan.md`; preserve its explicit
  historical Phase 1 record where old names document what that completed
  phase originally shipped.

Do not rewrite completed historical handoff documents solely to erase old
names.

Mark Phase 2 done in `docs/development/archive/nix-nrf-cli-plan.md` only after all old
public aliases and active callers are removed.

## Scope

In scope:

- Physical source/package moves.
- Internal libexec packaging.
- Dispatcher ownership of probe module.
- Removal of standalone probe binary/package.
- Migration of active repository callers, tests, CI, and current docs.

Out of scope:

- Refactoring probe logic or adding chip families.
- Adding bootstrap, flash, doctor, RTT, debug, or console commands.
- Dynamic plugin discovery.
- Probe unit-test refactor tracked separately in `goals.md`.
- Hardware execution or flashing.
- Changes to upstream command surfaces.

## Verification

Run:

```bash
nix fmt
nix flake check -L
nix build -L .#nix-nrf .#nrfutil
nix run .#nix-nrf -- --help
nix run .#nix-nrf -- probes --help
nix run .# -- probes --help
nix develop --ignore-environment --command sh -ceu 'command -v nix-nrf; command -v nrfutil; command -v openocd; command -v west; ! command -v nrf-probes; ! command -v nrf-sdk-versions'
```

Verify removed flake output fails evaluation/build:

```bash
set +e
nix build .#nrf-probes
rc=$?
set -e
test "$rc" -ne 0
```

Verify command help advertises public syntax:

```bash
nix run .#nix-nrf -- probes --help 2>&1 | grep -F 'usage: nix-nrf probes'
```

Run current-checkout template flow from Phase 1 CI and confirm generated shell
contains `nix-nrf`, lacks `nrf-probes`, and runs `nix-nrf probes --help`.

No hardware test is required for this move-only phase. `tests/hardware/run.sh`
must pass shell/static checks through repository gate; hardware behavior stays
covered by its next real runner execution.

## Acceptance

- `nix-nrf probes` preserves existing options and probe behavior.
- Help and errors use `nix-nrf probes` public name.
- Probe implementation exists only as internal libexec command module.
- No public `nrf-probes` executable or flake package remains.
- All active repository callers use new command.
- Full non-hardware gate passes.

## Commit and recap

Inspect status, diff, moves, and recent log. Stage only phase files. Commit
completed passing work with a concise Conventional Commit such as:

```text
refactor(cli): move probes behind nix-nrf
```

Do not push, merge, amend, open a PR, or add attribution. Return moved/changed
files, observable behavior, every verification result, commit hash/message,
blockers, deviations, and hardware verification status.
