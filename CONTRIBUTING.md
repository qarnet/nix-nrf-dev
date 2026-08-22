# Contributing to nix-nrf-dev

## Development environment

```bash
direnv allow     # or: nix develop
```

Shell provides `openocd`, `nrfutil`, `nix-nrf`, scoped `west` wrapper, and
NCS toolchain. `nix-nrf probes` identifies probes. `nix-nrf doctor` reports
hardware access without running `sudo`. There are no standalone
`nrf-probes` or `nrf-doctor` commands. Create consumer project with
`nix run .#init-project -- ./my-project`.

## Repository architecture

See [docs/development/architecture.md](docs/development/architecture.md) for
source ownership and construction flow.

## Before committing

Formatting and lint hooks run automatically via `pre-commit` (wired through
`git-hooks.nix`). To run them manually:

```bash
nix fmt                                 # format all files (alejandra for Nix, black for Python)
python3 tests/unit/test_nix_nrf_init_project.py  # initializer unit suite (raw source mode)
python3 scripts/release.py check       # release manifest/changelog consistency
python3 tests/unit/test_release.py     # release contract regression suite
nix build -L .#checks.x86_64-linux.release-consistency  # sandboxed release gate (same as `nix flake check`)
nix build -L .#checks.x86_64-linux.init-project-tests  # raw + packaged initializer gate
nix flake check --all-systems --no-build -L  # evaluate all checks without building (fast pass)
nix flake check -L                      # build and run all checks (incl. doctor-tests
                                        # and the udev-rules byte-for-byte check)
pre-commit run --all-files              # run hooks without committing
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

`scripts/release.py check` and `tests/unit/test_release.py` run in CI and as
`checks.<system>.release-consistency`. A manifest bump without matching
changelog table row and body fails.

Flake checks cover evaluation, fake-boundary units, shell boundaries, and
wiring checks. They do not build `packages.*`. CI builds packages separately.
Run `nix build` after changing package derivation.

## Clean-room bootstrap test

`tests/clean-room/run.sh` uses an empty, isolated home. It bootstraps NCS
`v3.3.0` and selected toolchain with `nix-nrf bootstrap --yes`, re-enters
shell, derives `ZEPHYR_BASE`, and builds XIAO nRF54L15 sysbuild blinky with
real `west build`. It never flashes hardware.

```bash
bash tests/clean-room/run.sh
```

This downloads several GiB from Nordic and requires at least 25 GiB free on
the filesystem hosting the isolated home. Configure the limit with
`NIX_NRF_CLEAN_MIN_FREE_GIB`. The isolated home defaults to a
script-created temporary directory that is removed on exit unless
`NIX_NRF_CLEAN_KEEP=1`; a caller-provided `NIX_NRF_CLEAN_HOME` is never
removed. See `tests/clean-room/README.md` for the full safety contract.

Clean-room test is not in normal pre-commit or flake checks. Normal PR CI
never downloads SDK or toolchain bundles. Run it manually through
`.github/workflows/clean-room.yml` on `nrf-hardware` runner. Use
`nix-nrf bootstrap` locally for SDK and toolchain in home directory.

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

## Release process

Project version is independent from NCS versions. `release.json` holds the
strict stable SemVer
(`MAJOR.MINOR.PATCH`, no leading `v`, no prerelease/build metadata) of the
nix-nrf-dev/nix-nrf release, while `ncsVersion` (e.g. `v3.3.0`) is an
upstream SDK selection and tested baseline. Never align the project release
with an NCS release.

To prepare a new release:

1. Bump `release.json` to the new version.
2. Add the matching changelog row to the `CHANGELOG.md` table and a release
   body under the exact `## [<version>]` heading, keeping
   `## [Unreleased]` above the current release.
3. Run the gates:
   `python3 scripts/release.py check`, `python3 tests/unit/test_release.py`,
   `nix build -L .#checks.x86_64-linux.release-consistency`, and the normal
   `nix flake check`.
4. Open and merge the reviewed PR.

Trusted release workflow creates tag and GitHub Release after successful push
to `main`. `.github/workflows/ci.yml` calls reusable
`.github/workflows/release.yml` with merge SHA. Re-running published version
does nothing. Do not manually create, force, or move release tags. Workflow
fails on conflicting or annotated tags rather than changing them.

## Bumping the openocd pin

`nix/hardware/openocd.nix` pins a specific upstream `openocd` revision, fetched
from the SourceForge Git repository
(<https://git.code.sf.net/p/openocd/code>) with submodules. To bump:

1. Inspect the repository at
   <https://sourceforge.net/p/openocd/code/ci/master/tree/> for a revision
   with the nRF53/nRF54L support you need.
2. Resolve SourceForge `master` to its exact commit, then put that immutable
   SHA in `rev` in `nix/hardware/openocd.nix`. Moving branch names or tags are
   not Nix pins.
3. Update `hash` for fetch *with submodules included*. Run
   `nix build .#openocd-master-unwrapped`. Nix prints the correct
   `sha256-...` hash for the failed fetch. Paste it into `hash`.
4. Run `nix build .#openocd-master-unwrapped -L` and `nix build .#openocd-master -L`.
5. Run normal flake check: `nix flake check --all-systems -L`.
6. Verify flash recipes on hardware. `tests/hardware/` requires explicit,
   manual work on self-hosted runner and is not part of default check.

## Adding a flash recipe

Flash recipes live in `tcl/`. Each recipe is a standalone TCL file sourced by
openocd. To add one:

1. Add `tcl/<chip>_flash.tcl` with the flashing procs.
2. Document it in `docs/hardware.md` under "Flash recipes".
3. If the chip needs probe identification, add its family signature to
   `bin/commands/nix-nrf-probes` (DPIDR → AP IDR
   map → FICR PART/VARIANT).

## CI and the openocd-master build

`openocd-master` is built from source in CI on every PR and nightly, cached
via [Cachix](https://app.cachix.org) under the `qarnet` cache.

Hardware integration tests run on a self-hosted GitHub Actions runner with
CMSIS-DAP probes and target boards attached. See
`tests/hardware/README.md` for runner setup and the test procedure.

## What this repo is not

This is a Nix flake library, not a firmware project. The `tcl/` recipes and
`bin/commands/nix-nrf-probes` are reusable tools consumed by other repos; they are not
flashed here. Do not add board-specific firmware or build artifacts.
