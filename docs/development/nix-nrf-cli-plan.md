# nix-nrf CLI Plan

Status: Phase 2 implemented. This document records the two-phase migration of
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

## Phase 2 — script migration (done)

Move project-owned script implementations to internal `nix-nrf` subcommand
modules, migrate repository callers such as `tests/hardware/run.sh`, update
packaging/tests/docs, then remove the old standalone project command aliases.

Behavior after this phase:

- `nix-nrf probes` — runs the internal probe command module; help and errors
  use the public `nix-nrf probes` name (parser `prog="nix-nrf probes"`,
  error prefixes `nix-nrf probes:`). All probe options, table columns,
  matching rules, OpenOCD commands, and exit codes are unchanged from the
  standalone script.
- The probe implementation moved Git-aware:
  `bin/nrf-probes` → `bin/nix-nrf-probes` and
  `nix/nrf-probes.nix` → `nix/nix-nrf-probes.nix`.
- `nix/nix-nrf-probes.nix` is an internal derivation: it installs the wrapped
  command at `$out/libexec/nix-nrf/probes` (no `$out/bin` binary), with the
  Python shebang patched and `openocd` plus `coreutils` on PATH.
- `nix/nix-nrf.nix` owns the module: it imports `./nix-nrf-probes.nix`
  internally with `pkgs` and `openocd` and execs the exact
  `$out/libexec/nix-nrf/probes` path; `nrfProbesPackage` is gone.
- `packages.nrf-probes` is removed; the standalone `nrf-probes` executable no
  longer exists anywhere (no `$out/bin/nrf-probes`, no shell package).
- Repository callers migrated to `nix-nrf probes`:
  `tests/hardware/run.sh`, `tests/hardware/README.md`, `.github/workflows/ci.yml`
  (no longer builds/smoke-runs `.#nrf-probes`; devshell and template checks
  assert `nrf-probes` is absent), `README.md`, `CONTRIBUTING.md`, `treefmt.nix`,
  `goals.md`, `nrfutil-backend-status.md`, and this plan document.
  `clean-bootstrap-versioning-plan.md` live references were updated while its
  historical Phase 1 record was preserved.

Constraints:

- Preserve subcommand behavior and exit codes across the migration.
- Do not rename upstream `west`, `openocd`, or `nrfutil` command surfaces.
- The probe module (`bin/nix-nrf-probes`) must keep its observable behavior
  unchanged: table output, `--find` disambiguation, exit codes.
