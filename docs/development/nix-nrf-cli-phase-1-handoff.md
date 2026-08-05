# `nix-nrf` CLI Phase 1 Handoff

## Goal

Introduce one public project CLI, `nix-nrf`, with subcommands. Replace the
standalone `nrf-sdk-versions` helper with `nix-nrf versions`, expose existing
probe behavior as `nix-nrf probes`, and keep `nrf-probes` as a temporary
compatibility command until the next migration phase.

User-observable behavior:

```text
nix-nrf --help
nix-nrf versions [sdk-manager search options]
nix-nrf probes [nrf-probes options]
```

`nix run .#nix-nrf -- ...` and, through the default package,
`nix run .# -- ...` must expose the same CLI.

## Grounding

- `nix/nrf-sdk-versions.nix` currently contains only a shell wrapper around
  `nrfutil sdk-manager search "$@"`.
- `bin/nrf-probes` is the existing Python implementation and
  `nix/nrf-probes.nix` packages it as `nrf-probes`.
- `flake.nix` currently exports both packages and `nix/mk-nrf-shell.nix`
  independently adds both commands to development shells.
- No tagged release exists. This phase may remove `nrf-sdk-versions` rather
  than preserving a compatibility alias. Existing `nrf-probes` callers exist
  in hardware tests and docs, so that command remains available for now.
- `west`, `openocd`, and `nrfutil` are upstream command surfaces and remain
  standalone.

## Exact implementation shape

### Dispatcher package

Add `nix/nix-nrf.nix`, taking these arguments:

```nix
{
  pkgs,
  nrfutilPackage,
  nrfProbesPackage,
}:
```

Build a `pkgs.writeShellApplication` named `nix-nrf`. Use a fixed `case`
dispatcher; do not implement dynamic plugin discovery in this phase.

Supported top-level forms:

- no arguments, `help`, `-h`, or `--help`: print concise usage and list
  `versions` and `probes`; exit 0.
- `help versions`: execute the selected nrfutil package as
  `nrfutil sdk-manager search --help`.
- `help probes`: execute the selected probe package as `nrf-probes --help`.
- `versions`: shift the subcommand and `exec` the selected nrfutil package as
  `nrfutil sdk-manager search "$@"`.
- `probes`: shift the subcommand and `exec` the selected probe package as
  `nrf-probes "$@"`.
- unknown command or unsupported `help <name>`: print error plus usage to
  stderr and exit 2.

Use exact Nix store executable paths derived from `nrfutilPackage` and
`nrfProbesPackage`, not ambient PATH lookup. Delegated stdout, stderr, options,
and exit status must remain unchanged because dispatcher uses `exec`.

Do not add project version metadata or `--version` in this phase; repository
has no release version source yet.

### Flake and shell wiring

In `flake.nix`:

1. Instantiate `nix-nrf` from default composed `nrfutil` and `nrf-probes`.
2. Export it as `packages.nix-nrf`.
3. Set `packages.default = nix-nrf`.
4. Remove `packages.nrf-sdk-versions` and its import.
5. Pass dependencies needed to construct caller-specific `nix-nrf` into
   `mkNrfShell`.

In `nix/mk-nrf-shell.nix`:

1. Instantiate `nix-nrf` using caller-selected `nrfutilPackage` and existing
   `nrf-probes`; this preserves advanced nrfutil overrides for `versions`.
2. Include `nix-nrf` in shell packages.
3. Remove standalone `nrf-sdk-versions` construction and shell inclusion.
4. Keep `nrf-probes` in shell packages as temporary compatibility command.
5. Update comments to describe current command set.

Delete `nix/nrf-sdk-versions.nix`.

### Documentation and roadmap

Update current user-facing and status references in:

- `README.md`
- `CONTRIBUTING.md` where command inventory is described
- `docs/development/nrfutil-backend-status.md`
- `docs/development/clean-bootstrap-versioning-plan.md`
- `goals.md` where current package/command names appear

Examples should lead with `nix-nrf versions` and `nix-nrf probes`. Clearly mark
`nrf-probes` as a compatibility command, not preferred new API. Remove claims
that `nrf-sdk-versions` remains available.

Add `docs/development/nix-nrf-cli-plan.md` with two phases:

1. **Phase 1 — facade (this phase):** add dispatcher, move version listing to
   `nix-nrf versions`, expose probes through dispatcher, retain `nrf-probes`.
2. **Phase 2 — script migration (next):** move project-owned script
   implementations to internal `nix-nrf` subcommand modules, migrate repository
   callers such as `tests/hardware/run.sh`, update packaging/tests/docs, then
   remove old standalone project command aliases. Phase 2 must preserve
   subcommand behavior and exit codes; it must not rename upstream `west`,
   `openocd`, or `nrfutil`.

Do not rewrite historical handoff documents that only describe completed past
phases unless they are currently presented as live behavior. Preserve useful
historical evidence.

### CI

Update `.github/workflows/ci.yml`:

- Build `.#nix-nrf` instead of `.#nrf-sdk-versions`.
- Smoke-test `nix run .#nix-nrf -- --help`.
- Smoke-test `nix run .#nix-nrf -- versions --help` without querying Nordic's
  live version index.
- Smoke-test `nix run .#nix-nrf -- probes --help`.
- Verify unknown subcommand exits 2.
- Devshell check must require `nix-nrf`, `nrf-probes`, `nrfutil`, `openocd`,
  and `west`; it must no longer require `nrf-sdk-versions`.
- Template check should verify `nix-nrf` plus existing tools.

## Scope

In scope:

- New fixed `nix-nrf` dispatcher and package/default output.
- `versions` and `probes` subcommands.
- Removal of `nrf-sdk-versions`.
- Temporary retention of `nrf-probes`.
- Current docs, roadmap, and CI updates.

Out of scope:

- Bootstrap implementation, downloads, or mutation.
- Flash, doctor, RTT, debug, or console commands.
- Moving/refactoring `bin/nrf-probes` internals; that is Phase 2.
- Dynamic plugin discovery.
- Native `nix nrf` integration.
- Changes to `west`, `openocd`, or `nrfutil` command names.
- Release/version metadata.

## Verification

Run from repository root:

```bash
nix fmt
nix flake check -L
nix build -L .#nix-nrf .#nrf-probes .#nrfutil
nix run .#nix-nrf -- --help
nix run .#nix-nrf -- versions --help
nix run .#nix-nrf -- probes --help
nix run .# -- --help
nix develop --command sh -ceu 'command -v nix-nrf; command -v nrf-probes; command -v nrfutil; command -v openocd; command -v west; ! command -v nrf-sdk-versions'
```

Also verify unknown-command contract:

```bash
set +e
nix run .#nix-nrf -- does-not-exist
rc=$?
set -e
test "$rc" -eq 2
```

Acceptance requires public-boundary behavior above. `versions --help` must not
depend on live Nordic index availability. No SDK/toolchain install may run.

## Commit and recap

Inspect `git status`, `git diff`, and recent log before committing. Stage only
phase files. Commit completed, passing work with a concise Conventional Commit,
for example:

```text
feat(cli): add nix-nrf command facade
```

Do not push, merge, amend, open a PR, or add attribution. Return files changed,
behavior changed, every verification command and result, commit hash/message,
blockers, deviations, and suggested follow-up.
