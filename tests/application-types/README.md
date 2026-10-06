# Existing-workspace firmware qualification

Normal `source-workspace-tests` use real west/CMake with synthetic packages. This
optional matrix instead builds firmware with the public `mkNrfShell` API and
already installed tools. It never initializes or updates sources, installs Python
packages, downloads an SDK/toolchain, exports CMake packages, or accesses hardware.
Nix may realize its normal package closure from configured caches.

Prerequisites:

- A complete existing NCS workspace, compatible with the chosen explicit release.
- Its existing `zephyr/samples/hello_world` and `nrf/samples/basic/empty` (actual
  project locations are resolved from the manifest).
- A small workspace application outside SDK repositories and a freestanding
  application outside the workspace. Supply their existing paths; the runner does
  not create applications inside a user-owned workspace.
  `tests/firmware/source-fixture` supplies a minimal freestanding fixture; an
  explicitly approved copy at the workspace root provides the workspace case.
  Its plain package lookup and linked extra-module symbol exercise more than
  the default SDK samples.
- Nordic tools already installed, or a prepared Python environment for the west
  backend. Missing readiness produces a recorded blocker, not automatic setup.
- A supported board and enough space for eight fresh build directories per backend.

Example, after reviewing paths and approving build-only work:

```bash
python3 tests/application-types/run.py --approve-build \
  --backend nrfutil --workspace /home/me/product-workspace \
  --workspace-app /home/me/product-workspace/product/app \
  --freestanding-app /home/me/experiment \
  --output /tmp/opencode/application-matrix-nrfutil
```

Repeat with `--backend west`, a different new output directory, and optionally
`--python-environment /path/to/prepared/venv`. `--ncs-version` defaults to v3.4.1;
`--board` defaults to `xiao_nrf54l15/nrf54l15/cpuapp`. The west backend retains its
documented release limits.

Both runners select `builtins.currentSystem`, not an amd64 library output.
An unsupported backend request fails before creating matrix output. Imported
workspace qualification uses the backends declared in `nix/platforms.nix`:
both on amd64, west only on ARM64. Results record host and exercised backends;
ARM64 refusal behavior is covered separately by normal flake checks.

The matrix covers Zephyr and NCS repository samples, workspace and freestanding
applications, each with single-image and sysbuild builds. It retains commands,
raw logs, source/manifest identity, selected CMake source/compiler/module paths,
ELF hashes, and `result.json`. Output must be a new directory and is never deleted.
Build success is not hardware execution proof. Failed or unavailable cases must
not be marked passed. Record extra-module/custom-board cases separately when
qualifying a consumer manifest.

## West command-layer qualification

`command_layers.py` dynamically reads every command descriptor declared by the
resolved manifest, then queries the public `nix-nrf doctor --json` west registry
from each layout. This uses west's own manifest/configuration and extension-spec
loader, not a sample command as an availability proxy. Effective names/owners
must agree across layouts; missing implementations and shadowed declarations
remain explicit failures. It probes each effective command with `west help <name>` through the
public scoped wrapper from Zephyr-repository, Nordic-repository, workspace-application, and
freestanding directories, for each native-supported backend. No command list is
silently truncated; missing descriptors/implementations, collisions, import
failures, and parser failures make the result fail.
The workspace application must already exist inside the selected workspace;
the runner never creates an application inside caller-owned SDK sources. A
freestanding test directory is created under the new output root. Resolved
application-owned manifest imports use the same catalog path, without a fixed
SDK-directory command list. Command-owner Git HEAD/status/diff and workspace
configuration are compared before/after; this does not snapshot every SDK project.

Only with `--sbom-smoke`, it separately runs `ncs-sbom` with test-owned SPDX-tagged input, only the
`spdx-tag` detector, one process, and explicit report output. The report must
contain SPDX 2.2, MIT license, and the input SHA-1. No firmware is flashed, runner
operations executed, packages installed, sources updated, or online license
detectors used. `REUSE_ENCODING_MODULE=charset_normalizer` scopes the installed
REUSE dependency's help-import backend to avoid magic-library discovery side
effects. This does not qualify hardware commands or lazy runtime dependencies.
SBOM has a separate `sbom_smoke_outcome`; success or failure never determines
the registry/parser availability verdict. By default it is not executed.

```bash
env -u PYTHONPATH -u PYTHONHOME /path/to/prepared/venv/bin/python -B \
  tests/application-types/command_layers.py --approve-command-tests \
  --workspace /home/me/ncs/v3.4.1 \
  --workspace-app /home/me/ncs/v3.4.1/product/app \
  --python-environment /path/to/prepared/venv \
  --output /tmp/opencode/command-layer-qualification
```

Output must be new; progress and final `result.json` retain every outcome and raw
logs. Interrupted runs are not accepted as complete. Existing Python remains
caller-owned: failures never trigger dependency repair. Current stock v3.4.1
registers `suit-manifest` without its Python implementation; qualification reports
that failure even with a complete environment. Record SDK exclusions explicitly
when qualifying an imported fixture with fewer command-owning projects.
Zephyr-only synthetic tests verify that Nordic registrations are absent despite
Nordic files being present, and report NCS environment readiness separately.
Every declaration gets an outcome,
including shadowed names; individual 180-second command timeouts fail their case
but do not truncate the remaining inventory.

## Independent application-owned imported workspace

The compile-only active-baseline runner also covers nRF52840 single/sysbuild,
nRF5340 CPUAPP/CPUNET, and nRF54L15 CPUAPP/FLPR on every native-supported backend:

```sh
python3 -B tests/application-types/baseline.py --approve-builds \
  --workspace /home/me/ncs/v3.4.1 \
  --python-environment /path/to/prepared/venv \
  --output /tmp/opencode/baseline-qualification
```

It uses prepared sources/Python and existing tools; never installs, flashes or
runs firmware. It retains per-build logs and ELF32 machine/hash evidence. FLPR
uses sysbuild with its CPUAPP launcher and DTS partitioning. Output must be new;
interrupted reports are incomplete, not successful acceptance.

`imported_workspace.py` adds four focused builds on amd64 and two on ARM64:
each supported backend with single-image and sysbuild. Unlike the matrix above,
it creates a new test-owned
workspace using only already available local Git objects. It imports Nordic from
an application manifest, overrides Zephyr at `sdk/rtos` with the same pinned
Nordic import allowlist, and discovers an extra module through the manifest alone.
`tests/firmware/workspace-import-fixture` uses plain `find_package(Zephyr)` and
does not set `EXTRA_ZEPHYR_MODULES`.

Prerequisites: a clean SDK-owned NCS v3.4.1 seed workspace at its manifest-pinned
revisions, Git, Nix, installed Nordic tools on amd64, and an existing Python environment
with west/PyYAML and the SDK build dependencies. Run the harness using that Python.
Neither dependency installation nor source acquisition is part of this runner.

After reviewing paths and approving local fixture creation and builds:

```bash
env -u PYTHONPATH -u PYTHONHOME /path/to/prepared/venv/bin/python -B \
  tests/application-types/imported_workspace.py --approve-local-setup-build \
  --sdk-workspace /home/me/ncs/v3.4.1 \
  --python-environment /path/to/prepared/venv \
  --exclude-project matter --exclude-project cmock \
  --max-copy-gib 3 --reserve-gib 1 \
  --output /tmp/opencode/imported-workspace-qualification
```

The output parent must already exist; output must be new and is retained even on
failure. Default board is `xiao_nrf54l15/nrf54l15/cpuapp`. The recorded exclusions
omit unused Matter/CMock stacks whose populated submodules are not supported by
this bounded local preparation. Other unpopulated gitlinks remain empty as in
the seed; builds requiring them fail rather than fetch. This is not qualification
of those excluded features or a general-purpose workspace bootstrap tool.

Safety and resource boundaries:

- `git clone --shared` borrows local objects but creates independent refs, index,
  configuration, and ordinary working files. No source Git worktrees, hardlinked
  source files, source-external symlinks, source patches, or `west update` are used.
- **Keep the seed repositories and their object stores for the fixture's entire
  lifetime.** Removing them or garbage-collecting borrowed objects can break the
  shared clones. This fixture is not an independent archival copy.
- Dirty tracked inputs, missing local revisions/import refs, populated
  submodules, existing destinations, and absolute source symlinks fail explicitly.
  Relative source symlinks must resolve inside the new workspace. Partial setup
  remains retained for diagnosis; rerun with another new output path.
- `--max-copy-gib` caps the sum of tracked blob sizes, not allocated disk usage.
  `--reserve-gib` adds a free-space margin before cloning. Filesystem block
  allocation, Git metadata, and builds need extra space. Measured NCS v3.3.0
  qualification used 1.39 GiB of tracked bytes, about 1.9 GiB of allocated
  workspace space, and 113 MiB of builds; total run took about 147 seconds on
  the qualified host. These are measurements, not portable bounds.
- Stock Nordic v3.4.1 module metadata derives its module name from directory
  basename. Keep `sdk/nrf`, not `sdk/nordic`, for these unmodified sources.
  Manifest source resolution alone does not fix upstream module naming.

Each build checks selected source/module/compiler/Python paths, the final linked
`source_import_fixture_value` symbol, and ELF hashes. Each supported backend must reject a
conflicting original `ZEPHYR_BASE` and a missing Nordic importer `manifest-rev`
without repair. Seed tracked status, refs, HEAD, index/config fingerprints, and
workspace configuration are compared before and after. Commands, raw logs,
measurements, source identities, and checks remain in `result.json` alongside
the retained builds. Exit status reflects final source-preservation checks too.

Normal CI runs the SDK-free, real disposable Git/west preparation tests with:

```bash
nix build -L .#checks.x86_64-linux.local-sdk-fixture-tests
```

Real builds remain opt-in and hardware-free. Pinned results and limits live in
[application-source-status.md](../../docs/development/application-source-status.md).
