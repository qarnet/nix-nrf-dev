# Contributing to nix-nrf-dev

## Development environment

```bash
direnv allow     # or: nix develop
```

The shell provides `openocd` (master build), `nrf-probes`, `nrfutil`, the
scoped `west` wrapper, and the NCS toolchain (via nrfutil sdk-manager for the
configured NCS version).

## Before committing

Formatting and lint hooks run automatically via `pre-commit` (wired through
`git-hooks.nix`). To run them manually:

```bash
nix fmt                       # format all files (alejandra for Nix, black for Python)
nix flake check -L             # run all checks in a sandbox
pre-commit run --all-files      # run hooks without committing
```

## Commit messages

This repo uses [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): description
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `ci`,
`perf`, `build`. Scope is optional but encouraged (e.g. `flake`, `tcl`,
`nrf-probes`, `ci`).

Examples:

- `feat(nrf-probes): add --find flag`
- `fix(tcl): correct nRF5340 UICR address`
- `docs(readme): document scoped toolchain env`
- `chore(flake): add treefmt-nix and git-hooks.nix`

## Bumping the openocd pin

`nix/openocd-master.nix` pins a specific upstream `openocd` revision. To bump:

1. Find a newer revision at <https://github.com/openocd-org/openocd> that has
   the nRF53/nRF54L support you need.
2. Update `rev` in `nix/openocd-master.nix`.
3. Update `hash` (run `nix build .#openocd-master-unwrapped` — Nix will print
   the correct `sha256-...` hash for the failed fetch; paste it in).
4. Run `nix build .#openocd-master-unwrapped -L` and `nix build .#openocd-master -L`.
5. Verify on hardware that the flash recipes still work (see
   `tests/hardware/` once it exists).

## Adding a flash recipe

Flash recipes live in `tcl/`. Each recipe is a standalone TCL file sourced by
openocd. To add one:

1. Add `tcl/<chip>_flash.tcl` with the flashing procs.
2. Document it in `README.md` under "Flash recipes (`tcl/`)".
3. If the chip needs probe identification, ensure `bin/nrf-probes` knows its
   family signature (DPIDR → AP IDR map → FICR PART/VARIANT).

## CI and the openocd-master build

`openocd-master` is built from source in CI on every PR and nightly, cached
via [Cachix](https://app.cachix.org) under the `qarnet` cache. The first build
takes ~10 minutes; subsequent builds pull from the cache in under a minute.

Hardware integration tests run on a self-hosted GitHub Actions runner with
CMSIS-DAP probes and target boards attached. See
`tests/hardware/README.md` (added in a later phase) for runner setup and the
test procedure.

## What this repo is not

This is a Nix flake library, not a firmware project. The `tcl/` recipes and
`bin/nrf-probes` are reusable tools consumed by other repos; they are not
flashed here. Do not add board-specific firmware or build artifacts.
