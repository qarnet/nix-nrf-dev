# nix-nrf CLI Plan

Status: Phase 1 implemented. This document records the two-phase migration of
the project's standalone command helpers behind the single public `nix-nrf`
CLI facade.

## Phase 1 — facade (done)

Add the `nix-nrf` dispatcher package, move version listing to
`nix-nrf versions`, expose probe identification through the dispatcher as
`nix-nrf probes`, and retain `nrf-probes` as a temporary compatibility
command.

Behavior:

- `nix-nrf versions` — delegates to `nrfutil sdk-manager search "$@"` (NCS
  version list; sdk-manager remains the runtime authority).
- `nix-nrf probes` — delegates to the packaged `nrf-probes "$@"`.
- `nix-nrf --help`, `nix-nrf help` — concise usage, exit 0.
- `nix-nrf help versions` / `nix-nrf help probes` — delegated `--help`.
- Unknown command or unsupported `help <name>` — error plus usage on stderr,
  exit 2.

Packaging: `nix/nix-nrf.nix` builds a fixed `case` dispatcher via
`pkgs.writeShellApplication`; it resolves exact Nix store executable paths
from the selected `nrfutilPackage` and `nrfProbesPackage` (never ambient
PATH) and `exec`s the delegated command, so delegated stdout, stderr,
options, and exit status are unchanged. `packages.nix-nrf` is exported and
`packages.default` aliases it, so `nix run .#nix-nrf` and `nix run .#` expose
the same CLI. `mkNrfShell` instantiates `nix-nrf` from the caller-selected
`nrfutilPackage`, preserving advanced nrfutil overrides for `versions`, and
keeps `nrf-probes` in shell packages as the temporary compatibility command.
The standalone `nrf-sdk-versions` package and `nix/nrf-sdk-versions.nix` were
removed.

## Phase 2 — script migration (next)

Move project-owned script implementations to internal `nix-nrf` subcommand
modules, migrate repository callers such as `tests/hardware/run.sh`, update
packaging/tests/docs, then remove the old standalone project command aliases.

Constraints:

- Preserve subcommand behavior and exit codes across the migration.
- Do not rename upstream `west`, `openocd`, or `nrfutil` command surfaces.
- `nrf-probes` is a project-owned script (`bin/nrf-probes`); its migration
  must not change its observable behavior (table output, `--find`
  disambiguation, exit codes).
