# West Backend Status

Status of the west backend (see
`docs/development/west-backend-environment-handoff.md` and
`docs/development/west-backend-public-integration-handoff.md`). The hybrid
model is now integrated as the public, experimental `backend = "west"`
selector in `mkNrfShell` (v3.3.0 / x86_64-linux only):

- Nix supplies the exact Zephyr SDK 0.17.0, compiler targets, Python 3.12,
  and host tools;
- standard west creates/updates the mutable NCS v3.3.0 source workspace;
- a standard Python virtual environment contains west and the requirements
  from that checked-out workspace;
- no nrfutil, sdk-manager, or Nordic opaque toolchain bundle participates.

The prototype phase (`devShells.west-prototype`, the temporary
`nix-nrf-west-setup` command, and `checks.west-setup-tests`) is complete and
removed; the proof history below is preserved.

## What exists

- `mkNrfShell { backend = "west"; ncsVersion = "v3.3.0"; }` — public backend
  selector. Unknown releases fail evaluation naming the supported west
  versions; `toolchainBundleId` and non-default `nrfutilPackage` overrides are
  rejected for west; `autoBootstrap`, `name`, `packages`, `withMultilib`,
  `extraShellHook`, and `inputsFrom` behave like the nrfutil backend. The
  nrfutil backend remains the default and is unchanged.
- `nix/west-backend/versions.nix` — plain attrset keyed by NCS release
  (`v3.3.0`: NCS version, tested west 1.4.0, Python 3.12 +
  `pythonPackage = "python312"`, Zephyr SDK 0.17.0 with `arm-zephyr-eabi` +
  `riscv64-zephyr-elf`, official x86_64-linux asset URLs + fixed hashes,
  requirement file list, pip constraint lines). Builders contain no
  release-specific literals.
- `nix/west-backend/zephyr-sdk.nix` — exact Zephyr SDK package assembled from
  the official v0.17.0 minimal bundle and the two compiler archives, with
  official directory layout (`sdk_version`, `cmake/`, `<target>/`), the
  interactive setup/host-tools installer scripts removed, auto-patchelf
  applied, a setup hook exporting
  `ZEPHYR_TOOLCHAIN_VARIANT=zephyr` / `ZEPHYR_SDK_INSTALL_DIR=$out`, and
  in-build validation (sdk_version, CMake package files, compiler `--version`
  after patching, no installer scripts left).
- `bin/nix-nrf-west-bootstrap` + `nix/nix-nrf-west-bootstrap.nix` — west
  bootstrap module packaged at `$out/libexec/nix-nrf/bootstrap` (no standalone
  `$out/bin` command), wrapped with the exact Nix Python (metadata-selected
  `pythonPackage`) and metadata defaults. Public invocation is `nix-nrf
  bootstrap [--workspace PATH] [--yes] [--check] [--quiet]
  [--print-sdk-path]`; the printed SDK path is the west workspace root
  (`$HOME/ncs/<version>`), satisfying the shared doctor/shell read-only
  contract. Approval is `--yes` / `NIX_NRF_BOOTSTRAP_YES=1` (the temporary
  `NIX_NRF_WEST_SETUP_YES` is removed). Read-only `--check`; mutating setup
  creates the venv, pins `west==<tested>`, runs `west init -m ... --mr
  <ncsVersion>`, `west update`, and installs the requirement files in declared
  order, applying the metadata `pipConstraints` via `pip install -c` on every
  venv pip invocation. A user-supplied `--workspace` is normalized to an
  absolute path (tilde + CWD resolution) before any subprocess runs. Never
  re-inits, never deletes/resets an existing workspace, never runs `west
  zephyr-export`, nrfutil, sudo, or sourced scripts.
- `nix/west-backend/versions-command.nix` + `bin/nix-nrf-west-versions` —
  exact `nix-nrf versions` command module for the west backend, packaged at
  `$out/libexec/nix-nrf/versions`. Lists the sorted attr names of
  versions.nix (text, one per line) or a `--json` string array; `--help` exit
  0, unknown options exit 2. Never invokes nrfutil; the script source
  contains no release literals.
- `nix/nix-nrf.nix` — accepts optional exact `versionsCommand` /
  `bootstrapCommand` store paths. The standalone `packages.nix-nrf` and the
  nrfutil shells keep today's nrfutil-backed versions/bootstrap; the west
  shell dispatches to its exact west command modules (no nrfutil constructed
  or referenced).
- `nix/nix-nrf-doctor.nix` + `bin/nix-nrf-doctor` — accept an
  `environmentLabel` (default `"SDK/toolchain"`; west shell passes `"west
  workspace/Zephyr SDK"`). Only human message strings use the label; JSON
  field names/schema and exit semantics never change. The doctor still
  invokes bootstrap only with `--check --quiet --print-sdk-path` (read-only).
- `nix/west-backend/environment.nix` — the public west backend shell (no
  `west-prototype` name): exact SDK, metadata-selected Python, host tools
  (cmake/ninja/dtc/gperf/git/ccache/dfu-util/file/xz/make/which), optional
  multilib GCC, openocd-master, the backend-aware `nix-nrf` facade, and a
  scoped `west` wrapper (readiness via `nix-nrf bootstrap`, `.venv/bin`
  prepended only inside west's process, `ZEPHYR_BASE` +
  `ZEPHYR_TOOLCHAIN_VARIANT` + `ZEPHYR_SDK_INSTALL_DIR` exported, project
  OpenOCD kept first, execs the exact venv west). `autoBootstrap = true`
  (default) runs `nix-nrf bootstrap --print-sdk-path` inside the wrapper
  (setup prompts when missing); `autoBootstrap = false` runs the read-only
  `--check` path and reports `Run: nix-nrf bootstrap` on failure. Shell hook
  is read-only (`nix-nrf bootstrap --check --quiet --print-sdk-path`) and
  exports `ZEPHYR_BASE` only when ready. Metadata values are assigned to
  shell variables outside double quotes, so quote-containing metadata cannot
  corrupt the workspace path.
- `packages.west-zephyr-sdk-v3_3_0` — west backend SDK package output.
- `checks.west-bootstrap-tests` — fake-boundary fixture tests for the
  bootstrap module (readiness, approval incl. `NIX_NRF_BOOTSTRAP_YES` and the
  removed old variable, public program prefix, command order, requirement
  order, re-run without re-init, incompatible-workspace rejection without
  deletion, failure propagation, `--check` non-mutation, `--print-sdk-path`
  stdout, isolated-HOME default workspace, relative/tilde `--workspace`
  normalization, and every parsed west-constraint operator including strict
  boundaries). The gate also builds the packaged module and asserts it
  installs only `$out/libexec/nix-nrf/bootstrap` (no standalone command).
- `checks.west-versions-tests` — fake-boundary tests for the west `nix-nrf
  versions` command module (text, JSON string array, help, unknown-option exit
  2, and the packaged module reporting exactly the metadata release).
- `checks.west-backend-metadata` — schema check over versions.nix
  (`pythonPackage` included, sorted attr names).
- `checks.west-backend-quoting` — quote-embedding regression: instantiates
  the PUBLIC `mkNrfShell { backend = "west"; }` with metadata containing
  single quotes + spaces and proves the shell hook and scoped west wrapper
  compose the workspace path and Python display values without literal quote
  artifacts.
- `checks.west-shell-boundary` — public shell boundary gate: a public west
  `mkNrfShell` instance with caller name/packages/extraShellHook/inputsFrom/
  withMultilib, run against a fake-ready workspace + fake venv executables
  (no network, no west update/pip/workspace downloads). Proves the hook is
  read-only and quote-clean, `nix-nrf versions`/`bootstrap --check`/`doctor`
  contracts, the scoped west environment, `autoBootstrap = false` refusal
  without mutation, nrfutil/`nix-nrf-west-setup` absence, and option
  propagation.
- `tests/west-backend/run.sh` — clean-room proof script (real setup + blinky
  sysbuild from an isolated HOME), updated to the public shell/API names
  (enters `mkNrfShell { backend = "west"; }` via `nix develop --expr`; uses
  `nix-nrf bootstrap`). Dry-run/`bash -n` validated; the real run is
  explicitly approved and not part of normal CI.

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
- Fixture tests — `python3 tests/unit/test_nix_nrf_west_bootstrap.py`: the
  bootstrap suite grew from the prototype's 32 cases to 35 (public
  `nix-nrf bootstrap` program prefix, `NIX_NRF_BOOTSTRAP_YES` approval,
  removed `NIX_NRF_WEST_SETUP_YES` no-effect, `--print-sdk-path` exact
  stdout, temporary-command removal) — OK standalone and as
  `checks.west-bootstrap-tests`, covering every parsed west constraint
  operator (==, >=, >, <=, < including strict boundaries and mixed
  ranges), relative/tilde `--workspace` normalization, and pip constraint
  application.
- `checks.west-backend-quoting` — passes with the fixed variable composition
  and FAILS when the escapeShellArg-in-double-quotes defect is reintroduced
  (verified both ways).
- Real clean-home proof — passed 2026-08-05 (see the section below); the
  temp home was removed by the script's default cleanup.
- Public shell entry (integration phase) —
  `nix develop --impure --expr '<mkNrfShell { backend = "west"; ... }>'
  --ignore-env --command sh -c '...'` — exit 0:
  `ZEPHYR_SDK_INSTALL_DIR` under `/nix/store`,
  `ZEPHYR_TOOLCHAIN_VARIANT=zephyr`, no `nrfutil` on PATH, no
  `nix-nrf-west-setup` on PATH, `nix-nrf versions` reports v3.3.0.
- `NIX_NRF_WEST_DRY_RUN=1 bash tests/west-backend/run.sh` — exit 0
  (preconditions, plan, cleanup).

## Real clean-home proof (2026-08-05, Linux x86_64)

`bash tests/west-backend/run.sh` exited 0. This run received explicit user
approval; each future real run requires its own fresh explicit approval (the
helper's interactive confirmation and the script's documented approval
requirement still apply — approval is never permanent). The script created
an isolated `/tmp` HOME (`/tmp/nix-nrf-west-home-w2adfa5L`), ran the cold
setup, built blinky via the scoped west wrapper, asserted the artifacts, and
removed the script-created home on exit (default cleanup; the keep-variable
`NIX_NRF_WEST_CLEAN_KEEP` was not set). No developer `$HOME/ncs` state, no
nrfutil, no hardware.

Lifecycle 1 (cold setup):

- `nix-nrf bootstrap --yes` (then named `nix-nrf-west-setup`) — **setup
  elapsed: 436 s**; `west init`
  (`sdk-nrf` v3.3.0) + full `west update` (25+ projects) + pip requirement
  installs with the then-current metadata constraint `cbor2<6`, which
  resolved and installed `cbor2==5.9.0`.
- Workspace: `$HOME/ncs/v3.3.0` with `.west/config`, `nrf/west.yml`,
  `zephyr/zephyr-env.sh`, `.venv/bin/west` — all asserted.
- Readiness re-check via `nix-nrf bootstrap --check --print-sdk-path`
  (then named `nix-nrf-west-setup --check --print-workspace`) returned the
  exact workspace path (exit 0).
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
`pipConstraints` applied via `pip install -c`; the import check also uses
the actual module name `nrfregtool` (nrf-regtool 9.2.1). Second run passed
end-to-end.

Constraint pinning history: the proof runs used the metadata constraint
`cbor2<6`, which happened to resolve and install `cbor2==5.9.0`. After
review the metadata was tightened to the exact `cbor2==5.9.0` pin — the
verbatim `requirements-fixed.txt` value — because `<6` would admit any
future, unverified 5.x release. No second multi-gigabyte proof was required:
the effective installed cbor2 version is unchanged.

## Limitations

- The west backend supports only `x86_64-linux`; any other system fails
  evaluation with a clear message.
- `gdb-py` (python-enabled gdb) binaries remain unpatched: they need
  `libpython3.10.so.1.0` (Python 3.10 EOL, absent from pinned Nixpkgs) and
  the legacy `libcrypt.so.1` ABI (Nixpkgs libxcrypt ships `libcrypt.so.2`).
  Plain `gdb` and all compilers work.
- `nix-nrf bootstrap` re-runs always refresh `west update` + requirement
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
  `requirements-fixed.txt` pins `cbor2==5.9.0`; the backend encodes that
  verbatim as the metadata `pipConstraints = ["cbor2==5.9.0"]` and applies
  it via `pip install -c`. Additionally, `nrf-regtool` 9.2.1 provides the
  `nrfregtool` module (not `nrf_regtool`), which the readiness import check
  uses.
- The west backend supports only `v3.3.0` on `x86_64-linux`; other releases
  and platforms are out of scope until their own metadata/proof exist.
- No scheduled CI workflow; normal CI runs the fixture/metadata/quoting/
  boundary gates and builds the west SDK package (no workspace download).
  The real clean-home proof remains manual and explicitly approved.

## Follow-up (next phases)

- Full Nix Python environment (not needed by this model).
- Manual workflow/caching policy for CI.
- Additional NCS releases / platforms once their metadata and clean-room
  proof exist.
