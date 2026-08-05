# Nix-Native `sdk-nrf` v3.3.0 Prototype Handoff

## Goal

Prove one NCS application can build from fixed Nix inputs without nrfutil,
sdk-manager, `$HOME/ncs`, or Nordic's opaque toolchain bundle:

```text
nix build -L .#sdk-nrf-v3_3_0-blinky
```

Target:

```text
zephyr/samples/basic/blinky
xiao_nrf54l15/nrf54l15/cpuapp
--sysbuild
```

This is an experimental package prototype, not the public backend. Keep
`mkNrfShell { backend = "sdk-nrf"; }` rejected until a later phase proves
multiple NCS releases and consumer-shell behavior.

## Grounding

### Installed NCS v3.3.0 metadata

Authoritative local source:

- `/home/thomas-workstation/ncs/v3.3.0/nrf/west.yml`
- `/home/thomas-workstation/ncs/v3.3.0/zephyr/west.yml`
- `/home/thomas-workstation/ncs/v3.3.0/nrf/scripts/tools-versions-linux.yml`
- `/home/thomas-workstation/ncs/v3.3.0/nrf/scripts/requirements-fixed.txt`

Required versions:

- NCS: `v3.3.0`;
- Nordic Zephyr: `ncs-v3.3.0`;
- Zephyr SDK: `0.17.0`;
- compiler target: `arm-zephyr-eabi` (riscv target is not needed for this
  proof);
- Python: NCS pins Python 3.12-compatible requirements;
- west: `>=1.4.0` (pinned Nixpkgs currently provides 1.5.0).

Minimal source projects for this board/sample:

| Workspace path | Repository | Revision |
|---|---|---|
| `nrf` | `nrfconnect/sdk-nrf` | `v3.3.0` |
| `zephyr` | `nrfconnect/sdk-zephyr` | `ncs-v3.3.0` |
| `modules/hal/nordic` | `zephyrproject-rtos/hal_nordic` | `1acb428a205bad58f3dfd4e38f2d1663bb784ba1` |
| `modules/hal/cmsis` | `zephyrproject-rtos/cmsis` | `512cc7e895e8491696b61f7ba8066b4a182569b8` |
| `modules/hal/cmsis_6` | `zephyrproject-rtos/CMSIS_6` | `30a859f44ef8ab4dc8f84b03ed586fd16ccf9d74` |

Do not fetch the full 26-project NCS manifest in this prototype. If a real
build error proves another module is required, stop and escalate before adding
it; do not silently grow toward a full workspace.

### Python gaps in Nixpkgs

Pinned Nixpkgs supplies most Zephyr/NCS build dependencies, but:

- `nrf-regtool` is absent;
- Nixpkgs `zcbor` is 0.9.1 while NCS v3.3.0 pins 0.8.1.

Use fixed pure-Python wheels from Nordic's public package index:

| Package | Wheel | SHA-256 |
|---|---|---|
| nrf-regtool 9.2.1 | `nrf_regtool-9.2.1-py3-none-any.whl` | `8b30007011a611be3ec420004987a1193730ee3ad7c8f0023f5fb9241920d8f8` |
| svada 2.2.0 | `svada-2.2.0-py3-none-any.whl` | `3d59c2000354f14d9d46443a9f178fc6d01fb61ac8e7e9a3776c7916ea19df17` |
| zcbor 0.8.1 | `zcbor-0.8.1-py3-none-any.whl` | `3aca62602be395ed1a1f0772ec239ad28a3ab09fa9c709a725cc89865ad243af` |

Base URL:
`https://files.nordicsemi.com/artifactory/api/pypi/nordic-pypi/public/`.

Installed wheel metadata confirms nrf-regtool is Apache-2.0 and requires
`intelhex` + `svada~=2.2.0`; svada requires `lxml~=5.3`, `numpy~=2.1`, and
`typing-extensions`. Package only dependencies actually declared by wheel
metadata; do not copy installed toolchain site-packages.

### Zephyr SDK

Use official Zephyr SDK v0.17.0 GitHub release assets:

- `zephyr-sdk-0.17.0_linux-x86_64_minimal.tar.xz`;
- `toolchain_linux-x86_64_arm-zephyr-eabi.tar.xz`.

Verify hashes against release `sha256.sum`; commit fixed Nix hashes. Combine
minimal archive and compiler archive into one store path, remove installer
scripts not needed at runtime, apply `autoPatchelfHook` as required, and expose
`ZEPHYR_SDK_INSTALL_DIR` through setup hook or explicit build environment.

Do not use Nordic's `911f4c5c26` toolchain bundle or any path under
`$HOME/ncs/toolchains`.

### Host tools

Use pinned Nixpkgs packages for:

- Python 3.12 environment;
- west;
- cmake;
- ninja;
- dtc;
- gperf;
- git;
- ccache only if build requests it (otherwise disable ccache);
- coreutils/findutils/which as build plumbing.

Set:

```text
ZEPHYR_TOOLCHAIN_VARIANT=zephyr
ZEPHYR_SDK_INSTALL_DIR=<Nix SDK path>
```

Do not set Nordic bundle `PYTHONHOME`, `PYTHONPATH`, `LD_LIBRARY_PATH`,
`GIT_EXEC_PATH`, or `NRFUTIL_HOME`.

### Prior art and licensing

`nix-community/zephyr-nix` demonstrates minimal SDK archive + selected compiler
archive and Nix host-tool patterns. `adisbladis/west2nix` demonstrates fixed
west workspaces. As checked in August 2026, both repositories return 404 for a
root `LICENSE` file. Do not add either as dependency and do not copy source.
Implement this small prototype independently from official archive/manifests.

`sdk-nrf` uses `LicenseRef-Nordic-5-Clause`: redistribution is permitted with
conditions and use is limited to Nordic integrated circuits. Target is a Nordic
nRF54L15. Preserve `nrf/LICENSE` in output documentation. Do not include
nrfxlib/precompiled crypto blobs; they are not needed by blinky.

## Exact file structure

Add:

```text
nix/sdk-nrf/default.nix
nix/sdk-nrf/versions.nix
nix/sdk-nrf/zephyr-sdk.nix
nix/sdk-nrf/python-env.nix
nix/sdk-nrf/workspace.nix
nix/sdk-nrf/blinky.nix
docs/development/sdk-nrf-prototype-status.md
```

Names may be collapsed only when a file would contain trivial forwarding;
preserve separation between version metadata, toolchain, Python, workspace,
and proof build.

## Version metadata model

`nix/sdk-nrf/versions.nix` must be a plain attrset keyed by NCS release:

```nix
{
  "v3.3.0" = {
    ncsVersion = "v3.3.0";
    zephyrSdk = {
      version = "0.17.0";
      targets = [ "arm-zephyr-eabi" ];
      # per-system official asset URLs/hashes
    };
    sources = {
      nrf = { owner; repo; rev; hash; path = "nrf"; };
      zephyr = { ...; path = "zephyr"; };
      hal_nordic = { ...; path = "modules/hal/nordic"; };
      cmsis = { ...; path = "modules/hal/cmsis"; };
      cmsis_6 = { ...; path = "modules/hal/cmsis_6"; };
    };
    python = { ...wheel versions/URLs/hashes...; };
    proof = {
      board = "xiao_nrf54l15/nrf54l15/cpuapp";
      appPath = "zephyr/samples/basic/blinky";
      sysbuild = true;
      image = "blinky";
    };
  };
}
```

Builder code selects metadata by key and contains no v3.3.0-specific revision,
URL, board, or Python version literals. One entry is sufficient for prototype;
public backend remains blocked until a second release proves model.

Assert required metadata fields and target list at evaluation.

## Fixed sources and synthetic workspace

Fetch every source with `pkgs.fetchFromGitHub` using committed hashes. Build a
synthetic west workspace derivation containing symlinks at exact metadata
paths. Add writable workspace materialization during proof build because `.west`
config/build state cannot live in Nix store.

Generate a minimal manifest repository at `manifest/west.yml` listing exactly
the five projects above. For Zephyr project set:

```yaml
west-commands: scripts/west-commands.yml
```

Use fixed URLs/revisions from metadata. Set manifest self path to `manifest`.
Create `.west/config`:

```ini
[manifest]
path = manifest
file = west.yml
[zephyr]
base = zephyr
```

Do not run `west update`, `git clone`, or any network command during build.
All source directories are fixed Nix inputs. `west list` must report exactly
the five projects plus manifest.

If west/module discovery needs explicit module selection, set
`ZEPHYR_MODULES` to semicolon-separated nrf/cmsis/cmsis_6/hal_nordic paths from
metadata. Prefer manifest discovery first; add explicit value only with build
evidence and document it.

## Python environment

Build `python312.withPackages` (or equivalent) from pinned Nixpkgs plus custom
wheel packages. Include build-critical requirements from Zephyr and NCS:

- west, pyelftools, pyyaml, pykwalify, jsonschema, packaging, intelhex,
  psutil, requests, anytree;
- cbor2, click, ecdsa, construct, cryptography, imagesize, setuptools,
  unidiff, pycryptodome, python-dotenv;
- pinned zcbor 0.8.1;
- nrf-regtool 9.2.1 + svada 2.2.0 dependencies;
- any transitive wheel dependency declared in metadata.

Use `buildPythonPackage` with wheel format and disabled upstream tests only when
wheel contains no test suite. Add import/CLI checks:

```text
python -c 'import west, zcbor, nrf_regtool, svada'
west --version
nrf-regtool --version
```

Do not use pip at build/runtime or Nordic's broad `requirements-fixed.txt` as a
network resolver.

## Proof build derivation

`nix/sdk-nrf/blinky.nix` must:

1. materialize writable workspace from fixed symlink-tree derivation;
2. create writable build directory;
3. export only Nix-native toolchain variables;
4. prove `nrfutil` is absent from PATH (`command -v nrfutil` must fail);
5. prove `ZEPHYR_SDK_INSTALL_DIR` does not point under `$HOME`;
6. run `west list` and assert expected project count/names;
7. run:

   ```bash
   west build -p always \
     -b xiao_nrf54l15/nrf54l15/cpuapp \
     --sysbuild \
     -d build \
     zephyr/samples/basic/blinky
   ```

8. assert non-empty:
   - `build/blinky/zephyr/zephyr.elf`;
   - `build/blinky/zephyr/zephyr.hex`;
   - `build/domains.yaml`;
   - `build/blinky/zephyr/zephyr.dts`;
9. install artifacts under `$out/firmware` and build evidence under
   `$out/share/nix-nrf-dev`:
   - source/revision manifest;
   - tool versions (`west`, cmake, ninja, dtc, Python, compiler);
   - resolved `.config` and `zephyr.dts`;
   - `nrf/LICENSE`.

Set package metadata as experimental, Linux x86_64 only, and license including
Nordic 5-Clause plus licenses inherited from Zephyr/SDK. Do not expose as
default package.

## Flake outputs and CI policy

Add packages:

```text
packages.sdk-nrf-v3_3_0-toolchain
packages.sdk-nrf-v3_3_0-workspace
packages.sdk-nrf-v3_3_0-blinky
```

Do **not**:

- change `mkNrfShell` backend selector;
- add sdk-nrf package to normal `checks` yet;
- add it to `.github/workflows/ci.yml` or Cachix upload path;
- claim consumer support.

Reason: prototype includes conditionally licensed Nordic sources and needs cache
redistribution policy review before normal CI. Local real build is acceptance.

Add cheap metadata evaluation check only: required fields, exact five projects,
one compiler target, and v3.3.0 key. This check must not fetch/build sources.

## Verification

Cheap gate first:

```bash
nix fmt
nix flake check -L
nix eval --json .#packages.x86_64-linux.sdk-nrf-v3_3_0-blinky.meta
```

Real approved prototype build (downloads official archives/fixed source inputs):

```bash
nix build -L .#sdk-nrf-v3_3_0-blinky
test -s result/firmware/zephyr.elf
test -s result/firmware/zephyr.hex
test -s result/share/nix-nrf-dev/zephyr.dts
```

Closure check:

```bash
nix path-info -r .#sdk-nrf-v3_3_0-blinky
```

Assert closure/output evidence contains no:

- packaged `nrfutil`;
- `segger-jlink`;
- `/home/thomas-workstation/ncs` reference;
- `/home/thomas-workstation/ncs/toolchains` reference.

Use `nix why-depends` or store-reference inspection, not filename guess alone.

Rebuild once with `nix build --rebuild` and compare output store path/hash; no
network should be needed after fixed inputs are present.

Final full gate:

```bash
nix flake check -L
```

## Documentation

Add `docs/development/sdk-nrf-prototype-status.md` recording:

- exact metadata and source count;
- toolchain/Python composition;
- build command, elapsed time, artifact sizes/hashes;
- closure size;
- proof that nrfutil/J-Link/developer paths are absent;
- licenses and reason prototype is excluded from Cachix/normal CI;
- limitations: one release, one board/sample, minimal modules, no consumer
  shell, no flashing, no binary-cache policy.

Update `goals.md`, README experimental section, and
`docs/development/clean-bootstrap-versioning-plan.md`. Keep `sdk-nrf` backend
status open/rejected. Do not mark roadmap item 3.1 complete.

## Scope

In scope:

- Metadata-driven v3.3.0 prototype.
- Fixed five-source synthetic workspace.
- Minimal upstream Zephyr SDK/ARM compiler.
- Nix Python/host tools.
- Real Nix build of one nRF54L15 blinky artifact.
- Local reproducibility and closure evidence.

Out of scope:

- Public `sdk-nrf` backend activation.
- Second NCS release.
- Full west manifest.
- Consumer devshell/writable source workflow.
- Flash/debug/hardware execution.
- nrfxlib/TF-M/MCUboot/Matter/Bluetooth/networking.
- Cachix or normal CI upload.
- Copying or depending on unlicensed prior-art repositories.

## Escalation conditions

Stop and return evidence rather than expanding scope when:

- build requires any project beyond fixed five;
- Nordic wheel dependency graph requires unavailable/non-redistributable
  package;
- Zephyr SDK binaries cannot be patched cleanly;
- west requires mutable Git repositories rather than fixed source trees;
- build succeeds only by referencing installed `$HOME/ncs` or nrfutil bundle;
- two materially different fixes fail for same blocker.

Do not add projects, fall back to installed SDK, weaken path/closure checks, or
enable backend silently.

## Commit and recap

Commit planning separately. Commit implementation only after real build and
final gate pass:

```text
feat(sdk-nrf): prototype Nix-native v3.3.0 build
```

Do not push, merge, amend, open PR, upload to Cachix, flash hardware, or add
attribution. Return exact downloads, files, source hashes, build timings,
artifact hashes/sizes, closure evidence, tests, commit hash/message, blockers,
deviations, and explicit statement that public backend remains disabled.
