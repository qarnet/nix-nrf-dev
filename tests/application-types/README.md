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
