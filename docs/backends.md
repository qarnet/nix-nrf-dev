# Backends

`mkNrfShell` requires `ncsVersion`. Each project pins one NCS release. The
shell configuration has no `"latest"` alias or default. This repository tests
NCS `v3.4.1` in its shells, hardware harness, and clean-room tests.

| Backend | Status | Toolchain provision | Supported releases |
|---------|--------|---------------------|--------------------|
| `nrfutil` | public factory default; amd64 preset | Nordic sdk-manager manages mutable SDK and toolchain under your home directory | releases sdk-manager advertises through `ncsVersion`, on `x86_64-linux` |
| `west` | experimental; ARM64 preset | Nix provides the Zephyr SDK, host tools, and Python. A mutable west workspace and venv hold the NCS source | `v3.4.1` on `x86_64-linux` and `aarch64-linux` |
| `sdk-nrf` | not implemented | n/a | none; fails at Nix evaluation |

Unknown `backend` values fail at Nix evaluation and list supported backends.

### Native host boundaries

Both Linux hosts publish native packages, apps, shells, checks, and library
outputs. The native ARM64 nrfutil executable and pinned sdk-manager `1.16.1`
extension do **not** imply an ARM64 Nordic toolchain bundle: Nordic's ARM64 bundle
index is empty. `mkNrfShell` with omitted or explicit `backend = "nrfutil"` on
ARM64 fails during evaluation; standalone Nordic bootstrap fails before any
acquisition. Select `backend = "west"` explicitly. Repository shells and the
initializer apply host presets; the public factory never changes its default.

`withMultilib` defaults to `true` on amd64 and `false` on ARM64. Explicit
`withMultilib = true` on ARM64 is rejected. This option provides x86 `-m32`
`native_sim` support, not firmware cross-compilation support. ARM and RISC-V
cross-compilers come from the pinned Zephyr SDK `1.0.1` on both hosts.
Plain compiler/GDB execution and firmware builds do not establish equivalent
Python-enabled GDB features or hardware debug/flash behavior.

Backend chooses tools; `source` chooses SDK source ownership. Omitted `source`
keeps managed behavior below. With `source = { mode = "workspace"; workspace = "."; };`,
nrfutil bootstrap only provisions tools and west bootstrap only checks an existing
Python environment. Neither acquires or updates workspace sources. See
[Application layouts and source selection](application-types.md) for complete examples.

## nrfutil backend (default)

Omit `backend` or pass `backend = "nrfutil"`; both behave identically. The
backend uses Nordic's sdk-manager to install and manage the NCS SDK source and
toolchain bundle under your home directory (for example
`$HOME/ncs/v3.4.1`).

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

`autoBootstrap` defaults to `true`. The west wrapper checks on each SDK-extension invocation
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

- Active metadata selects NCS `v3.4.1` on `x86_64-linux` and `aarch64-linux`. Unknown release fails
  evaluation naming the supported west releases.
- `toolchainBundleId` and non-default `nrfutilPackage` overrides are rejected
  (no nrfutil participates in this backend).

`nix-nrf bootstrap` creates or updates the west workspace and venv. `--yes`
approves up front. `--check` only checks readiness. `nix-nrf versions` lists
west backend releases and never invokes nrfutil.

Managed sources remain under `$HOME/ncs/<version>` with a version-local `.venv`;
the compiler SDK is immutable in the Nix store. Managed bootstrap installs the
existing aggregate Zephyr/Nordic/MCUboot Python requirements. It is not a fully
locked or Nordic-bundle-equivalent Python environment. `--check` verifies selected
requirement roots and version specifiers, selected import probes, west constraints
and installed dependency consistency. It does not prove every command's runtime
imports, native libraries or input requirements. ARM64 package
availability on configured indexes can differ from amd64. No requirements are
silently relaxed, and bootstrap reports installation failures.

Existing-workspace mode checks the caller's `.venv` or explicit
`pythonEnvironment`; even `bootstrap --yes` does not install or repair it. Prepare
that environment explicitly for the required SDK features before building. See
[application-types.md](application-types.md) for source and Python ownership.

## Project initialization (`init-project`)

`nix run ...#init-project` writes a consumer project with a concrete NCS
release. It is a separate public flake app, not a `nix-nrf` subcommand. It has
no prompts or overwrite option.

```sh
nix run github:qarnet/nix-nrf-dev#init-project -- ./my-project
nix run github:qarnet/nix-nrf-dev#init-project -- ./my-project \
  --backend west --ncs-version v3.4.1
```

- `--backend` defaults to `nrfutil` on amd64 and `west` on ARM64. `--ncs-version` defaults to `latest`,
  which resolves to one concrete release and is written into the generated
  flake. Generated projects never contain `ncsVersion = "latest"`.
- nrfutil `latest` asks packaged sdk-manager
  (`sdk-manager search --json --skip-overhead`) for the newest stable
  remotely installable NCS release. Failed or inconclusive lookup aborts
  generation. It does not fall back to hard-coded version. This differs from
  selected `v3.4.1`: latest means newest stable remotely installable release,
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
- West-generated flakes expose both Linux systems; nrfutil-generated flakes
  expose amd64 only. An unsupported ARM64 nrfutil request is rejected before
  latest resolution or destination writes.

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
Nordic, and test explicit `v3.4.1`.

## Optional west Python tooling

Baseline SDK requirement files are always installed by approved managed
bootstrap. Additional Nordic groups are opt-in:

```nix
mkNrfShell {
  backend = "west";
  ncsVersion = "v3.4.1";
  pythonRequirementGroups = [ "ncs-extra" "ncs-ci" ];
}
```

`ncs-extra` adds Nordic `scripts/requirements-extra.txt` (including `pygit2`
for NCS repository commands). `ncs-ci` adds `scripts/requirements-ci.txt`
(including `pyusb` for Thingy command imports). These are SDK-maintained groups,
not a promise to install just one package. Empty list is the default. Unknown
names and nonempty groups on `nrfutil` are rejected: Nordic owns bundled Python.

When `ncs-extra` is selected, approved managed bootstrap explicitly preinstalls
`pygit2>=1.15.0` from PyPI because Nordic's index lacks usable ARM64 distributions.
This is a named prerequisite recipe, not generic multi-index fallback. Baseline
and selected SDK group files then resolve together in one pip invocation, with
release constraints applied to both steps. Readiness runs read-only `pip check`.

Selected group files, requested package presence/version checks and import probes participate in `bootstrap --check`;
mandatory `natsort` is checked for Zephyr's test tools. In existing-workspace
mode, paths resolve from manifest project identities even when repositories are
relocated. Discovered module test requirements are not silently selected; the
configured SDK baseline and optional groups define the checked profile. No shell
entry or check installs packages. Caller-owned Python must be
prepared explicitly; `--yes` never repairs it. Import probes do not establish
every command's runtime readiness; use the separate registry/parser audit.

The active NCS baseline is v3.4.1. Nordic's
[v3.4 LTS release notes](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/doc/nrf/releases_and_maturity/releases/release-notes-3.4.1.rst)
identify this as the last release branch supporting nRF52, including nRF52840;
future v3.4 patch releases remain possible. Earlier v3.3.0 qualification is
historical evidence, not acceptance of the new baseline.

## Three west command states

See [qualified capabilities and known limitations](support-matrix.md) for exact
support boundaries, missing suit-manifest functionality and separate DFU/signing
qualification requirements.

The public `west` command is available before SDK/Python readiness. Its core
commands use immutable Nix-packaged west, without implicit bootstrap or Nordic
toolchain environment activation. SDK extensions still use the configured
backend's selected Python/toolchain, source validation, and readiness policy.

1. **Core available:** version/help, workspace setup and inspection are usable.
   `west --version`, general help, and core-command help require no SDK. Built-in
   does not mean workspace-free: `topdir`, `list`, `manifest`, `status`, `diff`,
   `forall`, and `update` need a suitable workspace/manifest/projects.
2. **Extensions discovered:** the resolved manifest registers extension names.
   Zephyr registers `build` and runner commands; Nordic registers `ncs-sbom` and
   other NCS commands. Imported manifests propagate registrations. Merely having
   SDK directories or a `ZEPHYR_BASE` string is not proof of activation. Disabled,
   missing, or malformed registrations are reported separately. Discovery uses
   west's resolved manifest and extension-spec loader, including its built-in and
   duplicate-name filtering. Doctor's `commands` lists effective registrations;
   `registrations` accounts for individual declarations, owners, descriptor and
   implementation paths, file presence, and whether west accepts the name.
   `west topdir` alone proves only workspace location, not extension availability.
3. **Command ready:** the requested command's Python imports, arguments, tools,
   and inputs are usable. Baseline `bootstrap --check` does not prove every
   extension ready. Command-specific help proves import/parser loading, not
   hardware execution or all lazy runner dependencies.

General help and SDK-command diagnostics show these states on stderr, leaving
version stdout clean. `nix-nrf doctor --json` adds a `west` object in configured
shells; human output shows the same states. Doctor inspects registration metadata
without importing extension implementations. It reports command readiness as
**unverified**, or **blocked** by missing selected environment—not as universally
ready. Use `west help <command>` for explicit import/parser qualification.
The opt-in command-layer runner checks this registry separately from parser
activation. Optional offline SBOM smoke is not a readiness signal for other
commands and does not determine its availability verdict.

Workspace-dependent core operations are bound to the configured workspace when
initialized, including from freestanding directories, and reject a conflicting
workspace. They do not require populated Zephyr/Nordic sources or a build venv.
`west init` follows its explicit arguments and normal west workspace rules; it
can create a new caller-owned workspace. `west update`, writable `config`, and
`forall` remain explicit mutations. No core request silently installs SDK sources
or Python packages. Extension requests retain managed bootstrap approval and
existing-workspace check-only ownership.

## Scoped toolchain environment

Nordic bundled Python/libgit2 may use Ubuntu certificate defaults absent on
NixOS. The nrfutil child preserves explicit caller CA settings or uses the Nix
CA bundle. TLS verification is never disabled; parent environment is unchanged.

All-command qualification is opt-in with prepared SDK/Python. See
[command-layer qualification](../tests/application-types/README.md#west-command-layer-qualification).
Known NCS v3.4.1 issue: `suit-manifest` is registered but its implementation file
is absent. Missing optional Python dependencies also block particular commands.
These are explicit qualification failures, not skipped tests or proof that all
NCS commands work.

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
