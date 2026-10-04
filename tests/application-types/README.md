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
`--python-environment /path/to/prepared/venv`. `--ncs-version` defaults to v3.3.0;
`--board` defaults to `xiao_nrf54l15/nrf54l15/cpuapp`. The west backend retains its
documented release limits.

The matrix covers Zephyr and NCS repository samples, workspace and freestanding
applications, each with single-image and sysbuild builds. It retains commands,
raw logs, source/manifest identity, selected CMake source/compiler/module paths,
ELF hashes, and `result.json`. Output must be a new directory and is never deleted.
Build success is not hardware execution proof. Failed or unavailable cases must
not be marked passed. Record extra-module/custom-board cases separately when
qualifying a consumer manifest.

## Independent application-owned imported workspace

`imported_workspace.py` adds four focused builds: both backends, each with
single-image and sysbuild. Unlike the matrix above, it creates a new test-owned
workspace using only already available local Git objects. It imports Nordic from
an application manifest, overrides Zephyr at `sdk/rtos` with the same pinned
Nordic import allowlist, and discovers an extra module through the manifest alone.
`tests/firmware/workspace-import-fixture` uses plain `find_package(Zephyr)` and
does not set `EXTRA_ZEPHYR_MODULES`.

Prerequisites: a clean SDK-owned NCS v3.3.0 seed workspace at its manifest-pinned
revisions, Git, Nix, installed Nordic tools, and an existing Python environment
with west/PyYAML and the SDK build dependencies. Run the harness using that Python.
Neither dependency installation nor source acquisition is part of this runner.

After reviewing paths and approving local fixture creation and builds:

```bash
env -u PYTHONPATH -u PYTHONHOME /path/to/prepared/venv/bin/python -B \
  tests/application-types/imported_workspace.py --approve-local-setup-build \
  --sdk-workspace /home/me/ncs/v3.3.0 \
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
- Stock Nordic v3.3.0 module metadata derives its module name from directory
  basename. Keep `sdk/nrf`, not `sdk/nordic`, for these unmodified sources.
  Manifest source resolution alone does not fix upstream module naming.

Each build checks selected source/module/compiler/Python paths, the final linked
`source_import_fixture_value` symbol, and ELF hashes. Both backends must reject a
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
