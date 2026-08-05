# West Backend Prototype Status

Status of the west backend prototype phase (see
`docs/development/west-backend-environment-handoff.md`). The prototype proves
the accepted hybrid installation model before any public `backend = "west"`
integration:

- Nix supplies the exact Zephyr SDK 0.17.0, compiler targets, Python 3.12,
  and host tools;
- standard west creates/updates the mutable NCS v3.3.0 source workspace;
- a standard Python virtual environment contains west and the requirements
  from that checked-out workspace;
- no nrfutil, sdk-manager, or Nordic opaque toolchain bundle participates.

Public `backend = "west"` is **not** implemented: `mkNrfShell` still supports
only `"nrfutil"`, and `"west"` is not even reserved in the selector yet.

## What exists

- `nix/west-backend/versions.nix` — plain attrset keyed by NCS release
  (`v3.3.0`: NCS version, tested west 1.4.0, Python 3.12, Zephyr SDK 0.17.0
  with `arm-zephyr-eabi` + `riscv64-zephyr-elf`, official x86_64-linux asset
  URLs + fixed hashes, requirement file list, pip constraint lines). Builders
  contain no release-specific literals.
- `nix/west-backend/zephyr-sdk.nix` — exact Zephyr SDK package assembled from
  the official v0.17.0 minimal bundle and the two compiler archives, with
  official directory layout (`sdk_version`, `cmake/`, `<target>/`), the
  interactive setup/host-tools installer scripts removed, auto-patchelf
  applied, a setup hook exporting
  `ZEPHYR_TOOLCHAIN_VARIANT=zephyr` / `ZEPHYR_SDK_INSTALL_DIR=$out`, and
  in-build validation (sdk_version, CMake package files, compiler `--version`
  after patching, no installer scripts left).
- `bin/nix-nrf-west-setup` + `nix/nix-nrf-west-setup.nix` — setup helper
  packaged at `$out/libexec/nix-nrf/west-setup` (plus
  `$out/bin/nix-nrf-west-setup`), wrapped with the exact Nix Python and
  metadata defaults. Read-only `--check`; mutating setup creates the venv,
  pins `west==<tested>`, runs `west init -m ... --mr <ncsVersion>`, `west
  update`, and installs the requirement files   in declared order, applying the metadata `pipConstraints` via
  `pip install -c` on every venv pip invocation. A
  user-supplied `--workspace` is normalized to an absolute path (tilde +
  CWD resolution) before any subprocess runs, so relative paths are never
  re-interpreted from inside the workspace. Never re-inits, never
  deletes/resets an existing workspace, never runs `west zephyr-export`,
  nrfutil, sudo, or sourced scripts.
- `nix/west-backend/environment.nix` — `devShells.west-prototype`: exact SDK,
  Python 3.12, cmake/ninja/dtc/gperf/git/ccache/dfu-util/file/xz/make/which,
  multilib GCC, openocd-master, the `nix-nrf` facade (probes/doctor), the
  setup helper, and a scoped `west` wrapper (readiness-gated,
  `.venv/bin` prepended only inside west's process, `ZEPHYR_BASE` +
  `ZEPHYR_TOOLCHAIN_VARIANT` + `ZEPHYR_SDK_INSTALL_DIR` exported, project
  OpenOCD kept ahead, execs the exact venv west). Shell hook is read-only
  and reports setup readiness via the packaged helper's read-only `--check`
  (missing `.west/config`, requirement files, venv structure, imports, or an
  unsatisfied west version all report not-ready). Metadata values are
  assigned to shell variables outside double quotes before composing paths
  and messages, so quote-containing metadata cannot corrupt the workspace
  path.
- `packages.west-zephyr-sdk-v3_3_0` — temporary SDK package output.
- `checks.west-setup-tests` — fake-boundary fixture tests for the setup
  helper (readiness, approval, command order, requirement order, re-run
  without re-init, incompatible-workspace rejection without deletion,
  failure propagation, `--check` non-mutation, isolated-HOME default
  workspace, relative/tilde `--workspace` normalization, and every parsed
  west-constraint operator including strict boundaries).
- `checks.west-backend-metadata` — cheap schema check over versions.nix.
- `checks.west-backend-quoting` — quote-embedding regression: instantiates
  the prototype environment with metadata containing single quotes + spaces
  and proves the shell hook and scoped west wrapper compose the workspace
  path, SDK/Python display values, and ZEPHYR_BASE without literal quote
  artifacts (fails against the pre-fix double-quote interpolation).
- `tests/west-backend/run.sh` — clean-room proof script (real setup + blinky
  sysbuild from an isolated HOME). Dry-run/`bash -n` validated; the real run
  is explicitly approved and not part of normal CI.

## Zephyr SDK asset hashes (verified against official sha256.sum)

| Asset | SHA-256 |
|---|---|
| `zephyr-sdk-0.17.0_linux-x86_64_minimal.tar.xz` | `0514d2c684dfb5f6327374bfed0b3dcf727ff1500195d26b3730f98252fed095` |
| `toolchain_linux-x86_64_arm-zephyr-eabi.tar.xz` | `c3992a788a0896ecc87f7fb3a3be3f234ec0509220bd4e9dbd99b22edd55e97f` |
| `toolchain_linux-x86_64_riscv64-zephyr-elf.tar.xz` | `cd97784c88de0207c93cf386f79d8d2606b46598dc74d4ad12cadd5617595964` |

## Evidence (local gates, 2026-08-05)

- `nix build -L .#west-zephyr-sdk-v3_3_0` — exit 0. In-build validation:
  `sdk_version` = 0.17.0, both compiler `--version` runs inside the sandbox
  (`arm-zephyr-eabi-gcc (Zephyr SDK 0.17.0) 12.2.0`,
  `riscv64-zephyr-elf-gcc (Zephyr SDK 0.17.0) 12.2.0`), CMake package files
  present, `setup.sh` absent. Host spot-check: `arm-zephyr-eabi-gdb --version`
  works (ncurses patched), `sdk_version` file = 0.17.0, setup hook exports
  `ZEPHYR_SDK_INSTALL_DIR` into `/nix/store`.
- Fixture tests — `python3 tests/unit/test_nix_nrf_west_setup.py`: 30 tests
  OK (also as `checks.west-setup-tests`), covering every parsed west
  constraint operator (==, >=, >, <=, < including strict boundaries and
  mixed ranges) and relative/tilde `--workspace` normalization.
- `checks.west-backend-quoting` — passes with the fixed variable composition
  and FAILS when the escapeShellArg-in-double-quotes defect is reintroduced
  (verified both ways).
- Real clean-home proof — passed 2026-08-05 (see the section below); the
  temp home was removed by the script's default cleanup.
- `nix develop .#west-prototype --ignore-env --command sh -ceu '...'` — exit
  0: `ZEPHYR_SDK_INSTALL_DIR` under `/nix/store`,
  `ZEPHYR_TOOLCHAIN_VARIANT=zephyr`, no `nrfutil` on PATH,
  `nix-nrf-west-setup --help` works.
- `NIX_NRF_WEST_DRY_RUN=1 bash tests/west-backend/run.sh` — exit 0
  (preconditions, plan, cleanup).

## Real clean-home proof (2026-08-05, Linux x86_64)

`bash tests/west-backend/run.sh` exited 0. The script created an isolated
`/tmp` HOME (`/tmp/nix-nrf-west-home-w2adfa5L`), ran the cold setup, built
blinky via the scoped west wrapper, asserted the artifacts, and removed the
script-created home on exit (default cleanup; `NIX_NRF_CLEAN_KEEP`/west
equivalent not set). No developer `$HOME/ncs` state, no nrfutil, no
hardware.

Lifecycle 1 (cold setup):

- `nix-nrf-west-setup --yes` — **setup elapsed: 436 s**; `west init`
  (`sdk-nrf` v3.3.0) + full `west update` (25+ projects) + pip requirement
  installs with the metadata constraint `cbor2<6`.
- Workspace: `$HOME/ncs/v3.3.0` with `.west/config`, `nrf/west.yml`,
  `zephyr/zephyr-env.sh`, `.venv/bin/west` — all asserted.
- Readiness re-check via `nix-nrf-west-setup --check --print-workspace`
  returned the exact workspace path (exit 0).
- Venv west: **v1.4.0** (the tested pin; satisfies the workspace
  `west>=1.4.0` requirement — pip does not upgrade already-satisfied
  packages).
- Nix Zephyr SDK: `ZEPHYR_SDK_INSTALL_DIR=/nix/store/9abvnlm91zvpb5sgjxrsfl5szrfvdxns-zephyr-sdk-0.17.0`
  (store path, not clean HOME, no Nordic toolchain bundle).
- Compilers: `arm-zephyr-eabi-gcc (Zephyr SDK 0.17.0) 12.2.0` and
  `riscv64-zephyr-elf-gcc (Zephyr SDK 0.17.0) 12.2.0`.
- `nrfutil` absent from PATH (`! command -v nrfutil` asserted).

Lifecycle 2 (fresh shell, scoped west wrapper):

- `west build -p always -b xiao_nrf54l15/nrf54l15/cpuapp --sysbuild`
  of `zephyr/samples/basic/blinky` — **build elapsed: 18 s**; wrapper
  exported `ZEPHYR_BASE`/`ZEPHYR_TOOLCHAIN_VARIANT`/`ZEPHYR_SDK_INSTALL_DIR`
  and exec'd the venv west.
- Artifacts asserted non-empty:
  `$HOME/build/blinky/blinky/zephyr/zephyr.elf` and
  `$HOME/build/blinky/domains.yaml`; sysbuild also produced `merged.hex`.
  Blinky memory: FLASH 32968 B (2.25% of 1428 KB), RAM 6744 B (3.50%).
- Sizes: workspace (incl. venv) **6.4 G**, build **29 M** — the west
  workspace is roughly half the nrfutil backend's 13 G clean-home install
  (no toolchain bundle is stored under the home).
- Second `! command -v nrfutil` assertion passed.

First proof attempt (same day) failed during readiness: `zcbor==0.8.1`
imported `CBORDecodeValueError`, removed in `cbor2` 6.x, which the loose NCS
requirement files resolve to today (unbounded `cbor2>=5.4.2.post1`; NCS's
own `requirements-fixed.txt` pins `cbor2==5.9.0`). Fixed by the metadata
`pipConstraints = ["cbor2<6"]` applied via `pip install -c`; the import
check also uses the actual module name `nrfregtool` (nrf-regtool 9.2.1).
Second run passed end-to-end.

## Limitations

- Prototype supports only `x86_64-linux`; any other system fails evaluation
  with a clear message.
- `gdb-py` (python-enabled gdb) binaries remain unpatched: they need
  `libpython3.10.so.1.0` (Python 3.10 EOL, absent from pinned Nixpkgs) and
  the legacy `libcrypt.so.1` ABI (Nixpkgs libxcrypt ships `libcrypt.so.2`).
  Plain `gdb` and all compilers work.
- `nix-nrf-west-setup` re-runs always refresh `west update` + requirement
  installs (documented mutation); a ready re-run performs no re-init and no
  re-pin of west.
- West version readiness resolves `-r` includes in the requirement files and
  compares every parsed operator (==, >=, >, <=, <); it accepts any version
  satisfying the resolved constraints (e.g. `west>=1.4.0`) and never demands
  the tested 1.4.0 pin after requirement installation. A re-run always
  refreshes `west update` + requirement installs, which may access the
  network; the setup helper warns accordingly.
- NCS v3.3.0's loose requirement files cannot alone produce a working venv
  on today's PyPI: `zcbor==0.8.1` imports `CBORDecodeValueError`, removed in
  `cbor2` 6.x, while `nrf/scripts/requirements-build.txt` allows
  `cbor2>=5.4.2.post1` unbounded (current resolution: 6.1.4). NCS's own
  `requirements-fixed.txt` pins `cbor2==5.9.0`; the prototype encodes that
  as the metadata `pipConstraints = ["cbor2<6"]` and applies it via
  `pip install -c`. Additionally, `nrf-regtool` 9.2.1 provides the
  `nrfregtool` module (not `nrf_regtool`), which the readiness import check
  uses.
- No scheduled CI workflow; normal CI runs only the fixture tests, metadata
  check, and quoting gate (no SDK download, no workspace download). The SDK
  package may now be added to normal checks: the real clean-home proof has
  passed (2026-08-05) — wiring it into `checks` is left to the public
  integration phase.

## Follow-up (next phases)

- Public `backend = "west"` selector in `mkNrfShell` (proof passed).
- CLI replacement of the temporary `nix-nrf-west-setup` name.
- Full Nix Python environment (not needed by this model).
- Manual workflow/caching policy for CI once public integration starts.
