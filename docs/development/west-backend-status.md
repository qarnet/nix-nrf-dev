# west backend

`backend = "west"` is experimental. It supports NCS `v3.3.0` on
`x86_64-linux`.

Nix provides Zephyr SDK `0.17.0`, compiler targets, Python `3.12`, and host
tools. Standard west creates mutable NCS workspace. Version-local venv holds
west and workspace Python requirements. This backend does not use nrfutil,
sdk-manager, or the Nordic toolchain bundle.

## What exists

- `mkNrfShell { backend = "west"; ncsVersion = "v3.3.0"; }` is public
  selector. It rejects unknown releases, `toolchainBundleId`, and non-default
  `nrfutilPackage`. Other shell options match nrfutil backend.
- `nix/backends/west/versions.nix` owns NCS release, Python package, Zephyr SDK
  assets and hashes, requirements, and pip constraints. Builders contain no
  release-specific literals.
- `nix/backends/west/zephyr-sdk.nix` assembles official minimal SDK and compiler
  archives. It removes interactive installers, patches ELF binaries, exports
  `ZEPHYR_TOOLCHAIN_VARIANT=zephyr` and `ZEPHYR_SDK_INSTALL_DIR`, and validates
  SDK files and compilers.
- `nix-nrf bootstrap` creates or updates `$HOME/ncs/<version>` workspace and
  `.venv`. `--check` only checks state. Ready non-check invocation does not
  prompt or mutate. Setup creates venv, installs `west`, runs `west init` and
  `west update`, then installs declared requirements.
- `nix-nrf versions` lists sorted keys from `versions.nix` and does not invoke
  nrfutil.
- `nix-nrf doctor` accepts `west workspace/Zephyr SDK` human label while JSON
  schema and exit behavior remain same.
- `nix/backends/west/shell.nix` provides host tools, OpenOCD, backend-aware
  `nix-nrf`, and scoped `west`. It prepends `.venv/bin` only for west and
  exports workspace and Zephyr SDK variables there.

## Validation

Normal CI runs `checks.west-bootstrap-tests`, `checks.west-versions-tests`,
`checks.west-backend-metadata`, `checks.west-target-toolchain-consistency`,
`checks.west-backend-quoting`, and `checks.west-shell-boundary`. They use fake
boundaries and do not download workspace or touch hardware.

`tests/west-backend/run.sh` starts with empty home, creates real workspace and
venv, then builds Zephyr blinky. It downloads several GiB, needs explicit
approval, and is not part of normal CI.

## Constraints

- Only `x86_64-linux` is supported.
- Python-enabled `gdb-py` remains unpatched. It needs unavailable
  `libpython3.10.so.1.0` and legacy `libcrypt.so.1`. Plain `gdb` and compilers
  work.
- Workspace readiness resolves `-r` includes and accepts any west version that
  satisfies all constraints. It does not require initial `1.4.0` after
  requirements installation.
- NCS `v3.3.0` requirements allow `cbor2` 6.x, but `zcbor==0.8.1` imports an
  alias removed in 6.x. Metadata pins `cbor2==5.9.0` from NCS
  `requirements-fixed.txt` through every venv pip command.
- No scheduled workflow runs full workspace setup. Normal CI builds fixed SDK
  package and runs deterministic tests.

## Open work

[roadmap.md](roadmap.md) tracks new releases, platforms, caching, and CI
policy. [sdk-nrf-feasibility-draft.md](sdk-nrf-feasibility-draft.md) tracks
pure Nix backend research.
