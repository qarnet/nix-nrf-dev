# Fully Nix-Native `sdk-nrf` Backend — Feasibility Draft

Status: rough, non-binding draft. This document records a feasible direction
and staged decision gates. It does not approve implementation, downloads,
public API changes, CI/cache publication, or hardware operations.

## Feasibility verdict

A fully Nix-managed NCS **build environment** appears technically feasible.
No current evidence shows a fundamental blocker for fixed NCS sources, a fixed
Python build environment, and reproducible firmware builds.

A universal replacement for every Nordic development tool is a different and
less realistic target. Optional workflows may depend on proprietary binaries,
J-Link integrations, vendor blobs, platform-specific wheels, or licenses that
should remain outside the core build backend.

Practical target:

- fixed NCS/Zephyr/module source revisions in the Nix store;
- fixed Zephyr SDK and compiler targets (already proven);
- fixed Python build dependencies, with no runtime pip;
- writable consumer application and build output;
- reproducible `west build`/sysbuild firmware artifacts;
- no nrfutil, sdk-manager, Nordic toolchain bundle, `$HOME/ncs`, or network
  access during a build.

This target is sensible when reproducible CI, branch-local SDK selection, and
removal of mutable developer setup justify the maintenance cost. It is not
necessary for users satisfied with the proven hybrid `backend = "west"`.

## Evidence supporting feasibility

Already proven in this repository:

- Zephyr SDK 0.17.0 assembled from fixed official assets in Nix.
- ARM and RISC-V compilers execute from the Nix store.
- Nix host tools and Python 3.12 work for NCS v3.3.0.
- Standard west workspace + Python requirements build nRF54L15 sysbuild
  blinky without nrfutil or Nordic's opaque toolchain bundle.
- Public hybrid `backend = "west"` clean-room proof passes from an isolated
  HOME (`docs/development/west-backend-status.md`).
- NCS manifests expose repository URLs, paths, revisions, imports, groups,
  submodules, and west command declarations needed to construct a lock.
- NCS v3.3.0 supplies a generated `requirements-fixed.txt` with exact Python
  versions for Python 3.12.

Known work, not unknown science:

- Fetching Git repositories at fixed SHAs is standard Nix behavior.
- Assembling source trees at west workspace paths is straightforward.
- Python wheels/sources can be fixed by URL and hash and installed offline in
  a Nix derivation.
- Zephyr build directories already live outside source trees and can remain
  writable while sources stay read-only in the Nix store.

## Important limits discovered

### Workspace size and manifest behavior

NCS v3.3.0 is not a five-repository general workspace:

- 56 visible project entries after manifest imports;
- 49 enabled by default group filtering;
- additional `bsim` imported-manifest resolution must be handled;
- some revisions are branches/tags and must be locked to final commit SHAs;
- project imports, nested imports, group filters, path prefixes, submodules,
  and `west-commands` affect the resolved workspace.

A five-project workspace may prove blinky, but cannot justify a public general
backend. General support needs a real manifest resolver/lock, not a manually
copied source list.

### Python closure

NCS v3.3.0 `nrf/scripts/requirements-fixed.txt` contains 189 pinned packages,
roughly 183 applicable to Linux/Python 3.12. It is a superset of normal NCS,
Zephyr, MCUboot, CI, and extra requirements.

Hard cases include:

- Nordic-index-only packages (`nrf-regtool`, `svada`, `nrfcredstore`, and
  others);
- native packages such as NumPy, lxml, grpcio, cryptography, and pygit2;
- wheel-heavy packages such as wasmtime and opencv-python;
- optional packages that introduce J-Link/proprietary-tool concerns, such as
  pynrfjprog.

First implementation should package a fixed **firmware-build profile**, not
blindly reproduce every CI/compliance/debug package. Additional profiles can
be added only when a supported workflow needs them.

### Read-only source UX

Nix store sources are immutable. Builds are compatible with this model, but
west sometimes expects workspace metadata and Git information near sources.
Prototype must prove:

- west manifest/module discovery works from a synthetic fixed workspace;
- generated version logic does not require mutable `.git` directories;
- application and build output can stay outside the store;
- no source file is modified during configure/build.

If a command needs writable source state, copy only required metadata into a
temporary build workspace; never copy the full SDK into `$HOME` as a hidden
fallback.

### Licensing and binary caches

Building locally and redistributing cached closures are different decisions.
Nordic 5-Clause sources, vendor blobs, J-Link components, and wheel licenses
must be classified before enabling Cachix or normal CI uploads. Prototype
build can remain local and uncached while this is reviewed.

## Rough staged plan

Each stage ends with a stop/go decision. Later stages are not implied by
starting an earlier one.

### Stage 0 — Feasibility inventory (read-only)

Goal: remove remaining unknowns without implementing backend.

Work:

- resolve complete v3.3.0 west manifest, including bsim import;
- classify enabled/disabled projects, submodules, mutable refs, and licenses;
- derive minimal Python package set observed by blinky configure/build;
- classify Python packages by Nixpkgs/source/wheel/vendor/license status;
- identify build-time Git metadata reads.

Likely files:

```text
docs/development/sdk-nrf-feasibility-status.md
```

Verification: report contains exact project count, final SHAs, Python package
inventory, licensing categories, and unresolved blockers. No production code.

Go only if fixed sources and a build-only Python environment look packageable
without prohibited redistribution or proprietary runtime dependencies.

### Stage 1 — Lock format and generator

Goal: produce reviewable, deterministic NCS workspace metadata.

Likely files:

```text
tools/lock-ncs-workspace.py
nix/sdk-nrf/versions.nix
nix/sdk-nrf/locks/v3.3.0.json
tests/unit/test_lock_ncs_workspace.py
```

Lock records final SHA, URL, path, groups, import origin, submodules,
west-commands, and license metadata. Lock generation may use network when run
explicitly; consuming lock in Nix must not.

Verification:

- deterministic output from same manifest state;
- no branch/tag remains as fetch revision;
- every enabled imported project represented exactly once;
- schema and fixture tests pass without network.

Stop if imports/submodules cannot be resolved deterministically.

### Stage 2 — Fixed workspace derivation

Goal: materialize locked NCS workspace in Nix store.

Likely files:

```text
nix/sdk-nrf/workspace.nix
nix/sdk-nrf/manifest.nix
```

Verification:

```bash
nix build -L .#sdk-nrf-v3_3_0-workspace
```

Assert exact projects/SHAs/paths, no network during build, no developer paths,
and no source mutation. Run read-only west manifest/list checks.

Stop if west or NCS requires mutable Git repositories and no small,
deterministic metadata substitute works.

### Stage 3 — Fixed Python build profile

Goal: build only Python closure required for normal firmware builds.

Likely files:

```text
tools/lock-ncs-python.py
nix/sdk-nrf/python-lock.nix
nix/sdk-nrf/python-env.nix
tests/sdk-nrf/python-env.nix
```

Prefer exact offline wheel/source inputs with committed hashes. Use Nixpkgs
packages where versions and behavior match; package Nordic-only or exact
version exceptions explicitly. No network or runtime pip.

Verification includes imports and CLIs actually needed by NCS build, including
`west`, `zcbor`, `nrfregtool`, and `svada`.

Stop if required build packages have incompatible licenses, unavailable
artifacts, or unpatchable native binaries.

### Stage 4 — Pure firmware build proof

Goal: build one firmware package entirely from fixed Nix inputs.

Likely files:

```text
nix/sdk-nrf/build.nix
nix/sdk-nrf/blinky.nix
docs/development/sdk-nrf-proof-status.md
```

Initial proof:

```text
application: zephyr/samples/basic/blinky
board: xiao_nrf54l15/nrf54l15/cpuapp
mode: sysbuild
```

Verification:

```bash
nix build -L .#sdk-nrf-v3_3_0-blinky
nix build --rebuild -L .#sdk-nrf-v3_3_0-blinky
```

Assert non-empty ELF/HEX/domains.yaml/devicetree/config, identical rebuild
output, no nrfutil/J-Link/developer paths, and no network after fixed inputs
exist.

Public `backend = "sdk-nrf"` remains rejected after this stage.

### Stage 5 — Consumer development shell

Goal: make fixed environment useful for applications outside SDK tree.

Work:

- support writable external application and build directories;
- provide fixed west/workspace context through wrapper;
- make bootstrap unnecessary/read-only;
- integrate backend-aware versions/doctor commands;
- preserve existing nrfutil and hybrid west backends.

Likely files:

```text
nix/backends/default.nix
nix/sdk-nrf/environment.nix
nix/commands/default.nix
flake.nix
```

Public selector stays experimental. No default change.

### Stage 6 — Generality proof

Before describing backend as general:

- add second NCS release;
- build at least one application requiring MCUboot/TF-M or another module set;
- prove clean consumer shell lifecycle;
- run hardware parity when explicitly approved;
- review cache/redistribution policy.

Only then consider promoting `sdk-nrf` beyond experimental.

## Stop conditions

Stop and reassess rather than expanding scope when:

- required source cannot be fetched at immutable revision;
- manifest import cannot be resolved deterministically;
- build requires proprietary toolchain runtime rather than public Zephyr SDK;
- required Python build dependency cannot be packaged legally or technically;
- successful build depends on developer `$HOME/ncs`, ambient venv, or network;
- fixed source must be made broadly writable;
- two materially different attempts fail at same architecture boundary;
- prototype closure unexpectedly includes nrfutil, sdk-manager, SEGGER/J-Link,
  or Nordic opaque toolchain bundle.

Failure at one stop condition does not invalidate the existing hybrid west
backend. That backend remains useful fallback and current supported path.

## Sensible commitment boundary

No commitment beyond Stage 0 is needed now. Stage 0 is documentation/research
only and should answer whether source locking, Python build profile, and
licensing are tractable enough to justify implementation.

If Stage 0 is favorable, Stages 1–4 form one technical prototype. Stages 5–6
are separate productization decisions.
