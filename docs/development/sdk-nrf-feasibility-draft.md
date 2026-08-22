# sdk-nrf backend feasibility

Research draft. This document does not approve implementation, downloads,
public API changes, CI publication, cache publication, or hardware work.

## Assessment

Fixed NCS sources, fixed Python build environment, and reproducible firmware
builds appear feasible in Nix. No evidence shows a fundamental blocker.

Replacing every Nordic development tool is not target. Proprietary binaries,
J-Link integration, vendor blobs, platform-specific wheels, and licenses may
remain outside build backend.

Target build environment:

- fixed NCS, Zephyr, and module source revisions in Nix store;
- fixed Zephyr SDK and compiler targets;
- fixed Python build dependencies with no runtime pip;
- writable consumer application and build output;
- reproducible `west build` and sysbuild artifacts;
- no nrfutil, sdk-manager, Nordic toolchain bundle, `$HOME/ncs`, or network
  access while building.

Build backend is worth cost only when reproducible CI, branch-local SDK
selection, and removing mutable setup outweigh maintenance. Existing hybrid
`backend = "west"` remains right choice for users who do not need this.

## Evidence

Repository already assembles Zephyr SDK `0.17.0` from fixed assets, runs ARM
and RISC-V compilers from Nix store, and builds NCS `v3.3.0` with Nix host
tools and Python `3.12`. Real west clean-room test builds XIAO nRF54L15
sysbuild blinky without nrfutil or Nordic toolchain bundle.

NCS manifests expose repository URLs, paths, revisions, imports, groups,
submodules, and west commands. NCS `v3.3.0` also has
`requirements-fixed.txt` with Python `3.12` versions.

## Limits found

### Workspace and manifest

NCS `v3.3.0` has 56 visible projects after manifest imports and 49 enabled by
default group filtering. A resolver must handle the imported bsim manifest,
mutable branch or tag refs converted to final commit SHAs, nested imports,
group filters, path prefixes, submodules, and `west-commands`.

Five-project workspace can build blinky. It cannot support general backend.
General backend needs manifest resolver and lock file, not hand-copied source
list.

### Python closure

`nrf/scripts/requirements-fixed.txt` contains 189 pinned packages. About 183
apply to Linux and Python `3.12`. It covers normal NCS, Zephyr, MCUboot, CI,
and extra requirements.

Hard cases include Nordic-index packages such as `nrf-regtool`, `svada`, and
`nrfcredstore`; native packages such as NumPy, lxml, grpcio, cryptography, and
pygit2; wheel-heavy packages such as wasmtime and opencv-python; and optional
packages such as `pynrfjprog` that bring J-Link or proprietary tool concerns.

First implementation should package fixed firmware-build profile. Add more
profiles only for supported workflow.

### Read-only source behavior

Nix store sources are immutable. Builds work with this model, but west may
expect workspace metadata and Git information near sources. Prototype must
show manifest and module discovery from synthetic fixed workspace, no mutable
`.git` requirement, writable application and build output, and no source
modification during configure or build.

If command needs writable source state, copy only needed metadata into
temporary workspace. Do not copy SDK to `$HOME` as hidden fallback.

### Licensing and binary caches

Local builds and cached closure redistribution are separate decisions. Nordic
5-Clause sources, vendor blobs, J-Link components, and wheel licenses need
classification before Cachix or normal CI upload. Prototype can stay local and
uncached during review.

## Staged work

Every stage ends with stop or go decision. Starting one stage does not approve
later stages.

### Stage 0: feasibility inventory

Do read-only research. Resolve full `v3.3.0` manifest including bsim. Classify
projects, submodules, refs, and licenses. Derive Python packages used by
blinky configuration and build. Record build-time Git reads.

Write `docs/development/sdk-nrf-feasibility-status.md`. Report exact project
count, final SHAs, Python inventory, license categories, and open blockers.
Continue only if sources and build-only Python environment can be packaged
without prohibited redistribution or proprietary runtime dependency.

### Stage 1: lock format and generator

Create:

```text
tools/lock-ncs-workspace.py
nix/sdk-nrf/versions.nix
nix/sdk-nrf/locks/v3.3.0.json
tests/unit/test_lock_ncs_workspace.py
```

Lock records final SHA, URL, path, groups, import origin, submodules,
west commands, and license metadata. Generator may use network when explicitly
run. Nix build consumes lock without network.

Verify deterministic output, no branch or tag fetch ref, one record per enabled
imported project, and offline schema and fixture tests. Stop if imports or
submodules cannot resolve deterministically.

### Stage 2: fixed workspace derivation

Create `nix/sdk-nrf/workspace.nix` and `nix/sdk-nrf/manifest.nix`. Build:

```bash
nix build -L .#sdk-nrf-v3_3_0-workspace
```

Check project SHAs and paths, no build-time network, no developer paths, no
source mutation, and read-only west manifest/list behavior. Stop if west or
NCS needs mutable Git repositories and no small deterministic metadata copy
works.

### Stage 3: fixed Python build profile

Create:

```text
tools/lock-ncs-python.py
nix/sdk-nrf/python-lock.nix
nix/sdk-nrf/python-env.nix
tests/sdk-nrf/python-env.nix
```

Use exact offline wheel or source inputs with committed hashes. Use Nixpkgs
when version and behavior match. Package Nordic-only and version exceptions
explicitly. Test imports and CLIs needed by builds, including `west`, `zcbor`,
`nrfregtool`, and `svada`. Stop if required packages have incompatible licenses,
unavailable artifacts, or unpatchable native binaries.

### Stage 4: firmware build

Create `nix/sdk-nrf/build.nix`, `nix/sdk-nrf/blinky.nix`, and
`docs/development/sdk-nrf-build-status.md`. Start with:

```text
application: zephyr/samples/basic/blinky
board: xiao_nrf54l15/nrf54l15/cpuapp
mode: sysbuild
```

Verify with:

```bash
nix build -L .#sdk-nrf-v3_3_0-blinky
nix build --rebuild -L .#sdk-nrf-v3_3_0-blinky
```

Check nonempty ELF, HEX, `domains.yaml`, devicetree, and configuration; equal
rebuild output; no nrfutil, J-Link, developer paths, or network after fixed
inputs exist. Keep public `backend = "sdk-nrf"` rejected.

### Stage 5: consumer shell

Support writable external application and build directories. Provide fixed west
and workspace context through wrapper. Make bootstrap unnecessary or read-only.
Integrate backend-aware versions and doctor commands. Preserve nrfutil and west
backends. Keep selector experimental.

### Stage 6: general support

Before calling backend general, add second NCS release, build application using
MCUboot, TF-M, or another module set, test clean consumer shell lifecycle, run
hardware parity only with approval, and review cache redistribution policy.

## Stop conditions

Stop and reassess if immutable source cannot be fetched, imports cannot resolve
deterministically, a build needs proprietary toolchain runtime, a required
Python dependency cannot be packaged legally or technically, or a successful
build depends on developer `$HOME/ncs`, an ambient venv, or network access.
Also stop if fixed source must become broadly writable or the prototype closure
contains nrfutil, sdk-manager, SEGGER/J-Link, or the Nordic toolchain bundle.

One failed condition does not invalidate hybrid west backend. It remains
supported fallback.

## Commitment limit

No work past Stage 0 is approved. Stage 0 must establish whether source
locking, a Python build profile, and licensing are tractable. Stages 1 through
4 form a technical prototype only. Stages 5 and 6 are separate product
decisions.
