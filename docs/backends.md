# Backends

`mkNrfShell` requires `ncsVersion`. Each project pins one NCS release. The
shell configuration has no `"latest"` alias or default. This repository tests
NCS `v3.3.0` in its shells, hardware harness, and clean-room tests.

| Backend | Status | Toolchain provision | Supported releases |
|---------|--------|---------------------|--------------------|
| `nrfutil` | default | Nordic sdk-manager manages mutable SDK and toolchain under your home directory | releases sdk-manager advertises through `ncsVersion` |
| `west` | experimental | Nix provides the Zephyr SDK, host tools, and Python. A mutable west workspace and venv hold the NCS source | `v3.3.0` on `x86_64-linux` only |
| `sdk-nrf` | not implemented | n/a | none; fails at Nix evaluation |

Unknown `backend` values fail at Nix evaluation and list supported backends.

## nrfutil backend (default)

Omit `backend` or pass `backend = "nrfutil"`; both behave identically. The
backend uses Nordic's sdk-manager to install and manage the NCS SDK source and
toolchain bundle under your home directory (for example
`$HOME/ncs/v3.3.0`).

### Toolchain selection

- Omit `toolchainBundleId`. The west wrapper runs
  `nrfutil sdk-manager toolchain env --ncs-version <ncsVersion>`, selecting
  the newest compatible patched toolchain for the release.
- Set `toolchainBundleId = "<bundle-id>"`. The wrapper runs
  `nrfutil sdk-manager toolchain env --toolchain-bundle-id <bundle-id>`,
  selecting that exact bundle. If it fails, the error names the exact bundle
  rather than falling back to the newest compatible one.

### Bootstrap

- `nix-nrf bootstrap` provisions explicitly and prompts before download.
- `nix-nrf bootstrap --yes` approves required downloads up front.
- `nix-nrf bootstrap --check` checks readiness without writing. It exits 1 when
  something is missing and never installs.
- `nix-nrf bootstrap --print-sdk-path` prints absolute SDK root on
  success.

`autoBootstrap` defaults to `true`. The west wrapper checks on each invocation
and installs only missing, approved components. With `autoBootstrap = false`,
the wrapper only checks and prints `nix-nrf bootstrap` when something is missing.

The shell hook runs read-only `--check` and exports `ZEPHYR_BASE` only when the
SDK is installed. Without a terminal, unapproved bootstrap exits 2 and prints
the re-run command.

## west backend (experimental)

`backend = "west"` uses Nix for the Zephyr SDK, host tools, and Python. An
official west workspace and version-local venv hold NCS source, west, and
workspace Python requirements. It does not use nrfutil, sdk-manager, or the
Nordic toolchain bundle.

### Constraints

- Only NCS `v3.3.0` on `x86_64-linux` is supported. Unknown release fails
  evaluation naming the supported west releases.
- `toolchainBundleId` and non-default `nrfutilPackage` overrides are rejected
  (no nrfutil participates in this backend).

`nix-nrf bootstrap` creates or updates the west workspace and venv. `--yes`
approves up front. `--check` only checks readiness. `nix-nrf versions` lists
west backend releases and never invokes nrfutil.

## Project initialization (`init-project`)

`nix run ...#init-project` writes a consumer project with a concrete NCS
release. It is a separate public flake app, not a `nix-nrf` subcommand. It has
no prompts or overwrite option.

```sh
nix run github:qarnet/nix-nrf-dev#init-project -- ./my-project
nix run github:qarnet/nix-nrf-dev#init-project -- ./my-project \
  --backend west --ncs-version v3.3.0
```

- `--backend` defaults to `nrfutil`. `--ncs-version` defaults to `latest`,
  which resolves to one concrete release and is written into the generated
  flake. Generated projects never contain `ncsVersion = "latest"`.
- nrfutil `latest` asks packaged sdk-manager
  (`sdk-manager search --json --skip-overhead`) for the newest stable
  remotely installable NCS release. Failed or inconclusive lookup aborts
  generation. It does not fall back to hard-coded version. This differs from
  tested `v3.3.0`: latest means newest stable remotely installable release,
  not hardware-tested release.
- west `latest` selects newest release in local
  `nix/backends/west/versions.nix` metadata (numeric semantic maximum over
  strict stable keys). It never queries GitHub or Nordic's global latest, and
  never selects a release the local west metadata does not support. An
  explicit `--ncs-version` must be an exact key in that metadata.
- Exact `--ncs-version` generates offline for both
  backends; the nrfutil backend does not check explicit values against the
  remote index.
- Existing `flake.nix` or `.envrc`, symlink escapes, and invalid
  backend/version values abort with `init-project: ...` on stderr and leave
  no generated output. `nix run ...#init-project -- --help` shows the full
  CLI.

## Nightly latest validation

Only `.github/workflows/latest-ncs-init.yml` runs live Nordic queries in normal
automation. It runs nightly at `37 2 * * *` and through manual
`workflow_dispatch`. It asks packaged sdk-manager for latest strict-stable,
remotely installable NCS release. It then runs `init-project --ncs-version
latest`, recomputes expected release from raw `sdk-manager search --json
--skip-overhead` output with separate stdlib parser, checks generated flake,
evaluates it against current checkout, and enters dev shell under isolated
`HOME` and `NRFUTIL_HOME`.

### What a passing run verifies

A passing run selects the latest strict-stable NCS release advertised by the
packaged sdk-manager, independently checks it, writes valid Nix, evaluates it,
and enters a non-mutating shell with expected missing-SDK readiness.

### What it does not verify

The workflow never downloads or installs an SDK or toolchain. It invokes only
`bootstrap --check`, checks that `$HOME/ncs` and a `zephyr` directory do not
appear, and rejects nrfutil install invocations in logs. It does not test SDK
or toolchain download, firmware build, or hardware.

### Inconclusive runs

Only bounded Nordic sdk-manager transport or index outages produce
`INCONCLUSIVE` after up to three retries. Cases include explicit remote-config
or index-unavailable messages, DNS failure, refused or reset connection,
TLS/transport/request timeout, HTTP 5xx, and command timeout status 124.
Malformed search data, no stable remotely installable release, wrong
selection, generated-Nix drift, evaluation/shell failure, or any mutation
fails workflow. Normal PR and CI checks stay deterministic, never contact
Nordic, and test explicit `v3.3.0`.

## Scoped toolchain environment

Nordic sdk-manager environment script exports `PYTHONHOME`, `PYTHONPATH`,
`LD_LIBRARY_PATH`, and `GIT_EXEC_PATH`. These variables break non-toolchain
tools, including Nix. The shell does not evaluate the script globally. The
`west` wrapper loads it only for the west process tree.

## Should I use `inputs.nixpkgs.follows`?

No. nix-nrf-dev works with the nixpkgs revision pinned in its `flake.lock`.

If your project already pins its own nixpkgs, adding `inputs.nixpkgs.follows`
makes nix-nrf-dev reuse that revision and reduces duplicate nixpkgs inputs.
It changes the Nixpkgs `nrfutil` core and optional-extension versions. Default
sdk-manager stays at repository-pinned `1.16.1`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-nrf-dev = {
      url = "github:qarnet/nix-nrf-dev";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

Omit `follows` to keep nix-nrf-dev's tested/pinned nixpkgs revision. See the
official [Nix flake documentation](https://nix.dev/concepts/flakes.html) for
how `follows` propagates input revisions.

## SEGGER / J-Link caveat

The packaged nrfutil derivation in Nixpkgs unconditionally depends on
`segger-jlink-headless` and sets `NRF_JLINK_DLL_PATH`, including when only
the sdk-manager extension is composed. The default flake therefore imports
Nixpkgs with `allowUnfree = true` and `segger-jlink.acceptLicense = true`,
so most users need no action, even when they only use a CMSIS-DAP probe.
CMSIS-DAP use does **not** remove the packaged J-Link dependency.

Consumers who construct or override nrfutil from their own `pkgs`, such as a
`nrfutilPackage` override or `pkgs.nrfutil.withExtensions
["nrfutil-sdk-manager"]`, must configure the same license handling. No
sdk-manager-only composition avoids J-Link.

## See also

- [hardware.md](hardware.md) covers probes, flashing, and recovery.
- [README](../README.md) has quick start and project initialization.
