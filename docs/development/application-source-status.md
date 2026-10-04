# Existing-workspace source support

PB-023 implementation and PB-024 qualification evidence, 2026-10-04.
User-facing setup and supported boundaries live in
[application-types.md](../application-types.md); design research remains a
[revision-pinned snapshot](application-types-research.md).

## Implementation boundaries

- `nix/backends/default.nix` validates independent `source` options and the
  west workspace's optional `pythonEnvironment`. Managed mode remains default.
- `nix/backends/source.nix` packages `bin/commands/nix-nrf-source`, anchors
  workspace strings on shell entry, and avoids parent source-package exports.
- The resolver reads west manifests/imports with the packaged west API, validates
  the local manifest, actual project paths and NCS VERSION, and diagnoses conflicting
  environment/configuration/CWD and detectable build-cache selections. It does
  not fetch, update, export, or rewrite configuration.
- Backend wrappers bind `ZEPHYR_BASE` and `Zephyr_DIR` only in child processes,
  and pass west `-z` to avoid its implicit `zephyr.base` persistence. Plain and
  environment-hinted `find_package(Zephyr)` declarations are supported there.
- nrfutil workspace bootstrap only checks/provisions toolchains, not SDK sources;
  toolchain installation skips CMake registration. West workspace bootstrap is
  check-only, including `--yes`, and uses a prepared Python environment.
- `nix-nrf source --json` identifies sources. Workspace-mode doctor adds separate
  `sdk.source` and configured `sdk.toolchain_selection` metadata. The latter is
  a configured selector, not a measured compiler version.

## Real-build qualification

Qualified host: x86_64-linux. Sources: installed NCS v3.3.0, Nordic revision
`ba167d9f3db4abbdc9b67887ca3ea66c64f2d956`, Zephyr revision
`fd9204a02d52630660ce8d729945a4dd743feabf`. Board:
`xiao_nrf54l15/nrf54l15/cpuapp`. No flashing or target execution occurred.

| Application | nrfutil single | nrfutil sysbuild | west single | west sysbuild |
| --- | --- | --- | --- | --- |
| Zephyr repository `samples/hello_world` | Pass | Pass | Pass | Pass |
| NCS repository `nrf/samples/basic/empty` | Pass | Pass | Pass | Pass |
| Workspace source fixture | Pass | Pass | Pass | Pass |
| Freestanding source fixture | Pass | Pass | Pass | Pass |

All **16 cases** used the public `mkNrfShell` API with workspace mode and
`autoBootstrap = false`. The workspace fixture was an approved copy of
`tests/firmware/source-fixture` at the SDK workspace root, outside SDK repositories.
Workspace and freestanding fixtures deliberately use plain `find_package(Zephyr)`
and an application-owned `EXTRA_ZEPHYR_MODULES` library. Generated module maps,
linked `source_fixture_value` symbols, and ELF hashes independently confirmed
module inclusion and recorded bytes. Every sampled source cache selected the
intended Zephyr tree.

Selected compilers were distinct:

- nrfutil: `/home/thomas/ncs/toolchains/911f4c5c26/opt/zephyr-sdk/arm-zephyr-eabi/bin/arm-zephyr-eabi-gcc`.
- west: `/nix/store/9abvnlm91zvpb5sgjxrsfl5szrfvdxns-zephyr-sdk-0.17.0/arm-zephyr-eabi/bin/arm-zephyr-eabi-gcc`.

Raw commands/logs, source identities, caches/module maps, and ELF hashes:

```text
/tmp/opencode/application-matrix-nrfutil-verified/result.json
/tmp/opencode/application-matrix-west-verified/result.json
```

These local artifacts are not committed or durable team storage. Preserve them
separately before moving/removing this workspace. The reusable runner is
`tests/application-types/run.py`; procedure is in its adjacent README.

## Independent application-owned import qualification

PB-024 adds a separate four-case real-build run using the same pinned NCS/Zephyr
revisions and board above, but independent working files and Git metadata under
`/tmp/opencode/imported-workspace-qualification-final/workspace`. Its application
manifest imports Nordic at `sdk/nrf`, overrides Zephyr at `sdk/rtos` with Nordic's
exact pinned allowlist, and owns the extra module at `modules/source_import_probe`.
No SDK source patch or `EXTRA_ZEPHYR_MODULES` override is involved.

| Case | Result | Build seconds |
| --- | --- | --- |
| nrfutil single-image | Pass | 22.4 |
| nrfutil sysbuild | Pass | 24.9 |
| west single-image | Pass | 22.1 |
| west sysbuild | Pass | 27.6 |

Both public shells selected the new application manifest and relocated sources.
Every sampled module map selected paths inside the new workspace, including
Nordic and the manifest-owned module. Compiler selections matched the distinct
paths above; nrfutil selected its bundle's Python 3.12 and west selected
`/tmp/opencode/source-qualification-venv/bin/python`. Each final ELF contains
`source_import_fixture_value`; all four recorded hashes were independently
recomputed with `sha256sum`.

Four negative checks passed: each backend rejected the original SDK's conflicting
`ZEPHYR_BASE` and a removed destination Nordic `manifest-rev` ref. Neither command
repaired that ref. The test restores only its own destination ref afterward.
The original SDK's tracked state, refs, HEAD, index/config fingerprints, and
workspace configuration remained unchanged, as did the fixture manifest/config.
The runner's final preservation check also controls its exit status.

Preparation reused 48 local repositories through shared Git object stores, not
hardlinked working files or source Git worktrees. Tracked blob estimate was
1,489,276,214 bytes (1.39 GiB), below the 3 GiB configured estimate cap. Allocated
workspace space measured about 1.9 GiB, with another 113 MiB for builds. Setup took
12.2 seconds; total run took 146.6 seconds. These local costs are not universal
limits; the estimate excludes block-allocation overhead, Git metadata, and builds.

Matter and CMock were explicitly excluded because their populated submodules are
outside this fixture's local-only preparation. Twenty other unpopulated gitlinks
remain empty; features requiring those assets are not qualified. Shared clones
depend on retained seed object stores and can break after seed removal or garbage
collection. Stock Nordic module metadata requires the `nrf` basename for these
unpatched sources. No download, provisioning, flashing, or target execution
occurred in this qualification.

Raw report, commands, logs, source snapshots, and artifacts are retained at:

```text
/tmp/opencode/imported-workspace-qualification-final/result.json
```

Repeatable command and lifetime/resource rules live in
[`tests/application-types/README.md`](../../tests/application-types/README.md).
Seven SDK-free CI tests exercise real disposable Git/west import resolution,
independent working-file mutation, and refusals for existing destinations, dirty
inputs, copy-budget/free-space shortage, missing importer refs/revisions, and
absolute source symlinks. The real-build run remains separate from normal CI.

## Python preparation and limitations

The user approved isolated Python dependency downloads and temporary test fixture
creation. `/tmp/opencode/source-qualification-venv` uses Nix Python 3.12, west 1.5.0,
nrf-regtool 9.2.1, zcbor 0.8.1 and cbor2 5.9.0. Preparation used SDK base/build
requirement profiles constrained by an extras-free copy of SDK fixed requirements.
The original SDK requirements were not edited.

Nordic's mirror returned 404 for pinned GitPython and Pillow wheels during broader
profile preparation. PyPI supplied the build profile with unchanged SDK pins.
The fixed requirements file contains extras and cannot directly be used with pip
`-c`; the user guide documents valid setup alternatives.

Preparation also exposed inherited Python 3.14 library paths. West child processes
now unset foreign `PYTHONHOME`/`PYTHONPATH`, without changing the parent. This is
covered by a public CLI regression test.

This qualification does not establish every board, NCS release, fork, custom board,
or custom nested build layout. Relocated projects and application-owned imports
have the focused real-build evidence above; more varied imported manifests,
same-version modified sources, conflicts, quoting, cancellation, child failures,
and read-only ownership are covered separately by host tests. Source acquisition,
manifest scaffolding, an outer-shell direct-CMake execution API, and SDK baseline
upgrades remain outside this feature.

Retained temporary workspace application:
`/home/thomas/ncs/v3.3.0/nix-nrf-source-fixture-qualification`.
It is test-owned, outside `nrf`/`zephyr` Git trees, and was never flashed.
