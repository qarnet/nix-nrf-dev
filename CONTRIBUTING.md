# Contributing to nix-nrf-dev

## Development environment

```bash
direnv allow     # or: nix develop
```

The shell provides `openocd` (master build), `nrfutil`, the
`nix-nrf` CLI facade (`nix-nrf versions`, `nix-nrf probes`,
`nix-nrf bootstrap`, `nix-nrf doctor`), the scoped `west`
wrapper, and the NCS toolchain (via nrfutil sdk-manager for the configured NCS
version; lazily bootstrapped by `west` when missing). Probe identification is
the `nix-nrf probes` subcommand; hardware-access diagnostics is the
`nix-nrf doctor` subcommand (read-only, never runs `sudo`); there are no
standalone `nrf-probes`/`nrf-doctor` commands.

## Before committing

Formatting and lint hooks run automatically via `pre-commit` (wired through
`git-hooks.nix`). To run them manually:

```bash
nix fmt                       # format all files (alejandra for Nix, black for Python)
nix flake check -L             # run all checks in a sandbox (incl. doctor-tests
                               # and the udev-rules byte-for-byte check)
pre-commit run --all-files      # run hooks without committing
nix develop .#clean-env-test --command sh -ceu '
  case "${LD_LIBRARY_PATH:-}" in *ncs/toolchains*) exit 1;; esac
  case "${PYTHONPATH:-}" in *ncs/toolchains*) exit 1;; esac
  case "${GIT_EXEC_PATH:-}" in *ncs/toolchains*) exit 1;; esac
  test -z "${PYTHONHOME:-}"
  nix --version
  node --version
  git --version
  python3 -c "import json"
'  # prove Nordic sdk-manager variables do not poison external tools
```

## Clean-room bootstrap test

`tests/clean-room/run.sh` proves the project works from an empty, isolated
home directory: it bootstraps NCS v3.3.0 and the selected toolchain with
`nix-nrf bootstrap --yes` inside an isolated `HOME`, re-enters the shell,
derives `ZEPHYR_BASE` from the isolated installation, and builds the XIAO
nRF54L15 sysbuild blinky with a real `west build`. It never flashes hardware.

```bash
bash tests/clean-room/run.sh
```

**This downloads several GiB from Nordic and requires at least 25 GiB free**
on the filesystem hosting the isolated home (configurable via
`NIX_NRF_CLEAN_MIN_FREE_GIB`). The isolated home defaults to a
script-created temporary directory that is removed on exit unless
`NIX_NRF_CLEAN_KEEP=1`; a caller-provided `NIX_NRF_CLEAN_HOME` is never
removed. See `tests/clean-room/README.md` for the full safety contract.

The clean-room test is **not** part of the normal pre-commit/flake-check
gate, and normal PR CI never downloads SDK/toolchain bundles. It runs
manually via `.github/workflows/clean-room.yml` (`workflow_dispatch`, no
schedule) on the `nrf-hardware` self-hosted runner. Use `nix-nrf bootstrap`
locally when you need the SDK/toolchain in your own home.

## Commit messages

This repo uses [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): description
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `ci`,
`perf`, `build`. Scope is optional but encouraged (e.g. `flake`, `tcl`,
`nix-nrf`, `ci`).

Examples:

- `feat(nix-nrf): add --find flag to probes`
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
3. If the chip needs probe identification, ensure `bin/nix-nrf-probes` knows its
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
`bin/nix-nrf-probes` are reusable tools consumed by other repos; they are not
flashed here. Do not add board-specific firmware or build artifacts.
