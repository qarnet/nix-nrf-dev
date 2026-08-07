# West Backend Status

Current status of the west backend: the public, experimental
`backend = "west"` selector in `mkNrfShell` (v3.3.0 / x86_64-linux only).
The hybrid model:

- Nix supplies the exact Zephyr SDK 0.17.0, compiler targets, Python 3.12,
  and host tools;
- standard west creates/updates the mutable NCS v3.3.0 source workspace;
- a standard Python virtual environment contains west and the requirements
  from that checked-out workspace;
- no nrfutil, sdk-manager, or Nordic opaque toolchain bundle participates.

The nrfutil backend remains the default; west is an additional experimental
backend.

## What exists

- `mkNrfShell { backend = "west"; ncsVersion = "v3.3.0"; }` — public backend
  selector. Unknown releases fail evaluation naming the supported west
  versions; `toolchainBundleId` and non-default `nrfutilPackage` overrides are
  rejected for west; `autoBootstrap`, `name`, `packages`, `withMultilib`,
  `extraShellHook`, and `inputsFrom` behave like the nrfutil backend.
- `nix/backends/west/versions.nix` — plain attrset keyed by NCS release
  (`v3.3.0`: NCS version, tested west 1.4.0, Python 3.12 +
  `pythonPackage = "python312"`, Zephyr SDK 0.17.0 with `arm-zephyr-eabi` +
  `riscv64-zephyr-elf`, official x86_64-linux asset URLs + fixed hashes,
  requirement file list, pip constraint lines). Builders contain no
  release-specific literals. The canonical Zephyr SDK asset hashes live here;
  `nix/flake/checks/west.nix` (`checks.west-backend-metadata`) validates the
  schema.
- `nix/backends/west/zephyr-sdk.nix` — exact Zephyr SDK package assembled from
  the official v0.17.0 minimal bundle and the two compiler archives, with
  official directory layout (`sdk_version`, `cmake/`, `<target>/`), the
  interactive setup/host-tools installer scripts removed, auto-patchelf
  applied, a setup hook exporting
  `ZEPHYR_TOOLCHAIN_VARIANT=zephyr` / `ZEPHYR_SDK_INSTALL_DIR=$out`, and
  in-build validation (sdk_version, CMake package files, compiler `--version`
  after patching, no installer scripts left).
- `bin/backends/west/nix-nrf-west-bootstrap` + `nix/backends/west/bootstrap.nix` — west
  bootstrap module packaged at `$out/libexec/nix-nrf/bootstrap` (no standalone
  `$out/bin` command), wrapped with the exact Nix Python (metadata-selected
  `pythonPackage`) and metadata defaults. Public invocation is `nix-nrf
  bootstrap [--workspace PATH] [--yes] [--check] [--quiet]
  [--print-sdk-path]`; the printed SDK path is the west workspace root
  (`$HOME/ncs/<version>`), satisfying the shared doctor/shell read-only
  contract. Approval is `--yes` / `NIX_NRF_BOOTSTRAP_YES=1`. Read-only
  `--check`; a ready non-check invocation is a no-op (never prompts, never
  mutates — nrfutil parity, so the lazy west wrapper needs no approval when
  ready); mutating setup creates the venv, pins `west==<tested>`, runs
  `west init -m ... --mr <ncsVersion>`, `west update`, and installs the
  requirement files in declared order, applying the metadata `pipConstraints`
  via `pip install -c` on every venv pip invocation. A user-supplied
  `--workspace` is normalized to an absolute path (tilde + CWD resolution)
  before any subprocess runs. Never re-inits, never deletes/resets an
  existing workspace, never runs `west zephyr-export`, nrfutil, sudo, or
  sourced scripts.
- `nix/backends/west/versions-command.nix` + `bin/backends/west/nix-nrf-west-versions` —
  exact `nix-nrf versions` command module for the west backend, packaged at
  `$out/libexec/nix-nrf/versions`. Lists the sorted attr names of
  versions.nix (text, one per line) or a `--json` string array; `--help` exit
  0, unknown options exit 2. Never invokes nrfutil; the script source
  contains no release literals.
- `nix/commands/default.nix` — accepts optional exact `versionsCommand` /
  `bootstrapCommand` store paths. The standalone `packages.nix-nrf` and the
  nrfutil shells keep today's nrfutil-backed versions/bootstrap; the west
  shell dispatches to its exact west command modules (no nrfutil constructed
  or referenced).
- `nix/commands/doctor.nix` + `bin/commands/nix-nrf-doctor` — accept an
  `environmentLabel` (default `"SDK/toolchain"`; west shell passes `"west
  workspace/Zephyr SDK"`). Only human message strings use the label; JSON
  field names/schema and exit semantics never change. The doctor still
  invokes bootstrap only with `--check --quiet --print-sdk-path` (read-only).
- `nix/backends/west/shell.nix` — the public west backend shell: exact SDK,
  metadata-selected Python, host tools
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

## Validation

Normal CI runs the west gates named in `nix/flake/checks/default.nix` (see
`nix/flake/checks/west.nix` for each): `checks.west-bootstrap-tests`
(fake-boundary bootstrap lifecycle incl. approval, ready no-op, workspace
normalization, and the shared `tests/fixtures/west-workspace.py` safety
suite), `checks.west-versions-tests`, `checks.west-backend-metadata`
(versions.nix schema incl. sorted attr names), `checks.west-backend-quoting`
(quote-embedding regression through the public `mkNrfShell`), and
`checks.west-shell-boundary` (public shell hook + scoped wrapper against a
fake-ready workspace). These run with no network, no workspace download, and
no hardware. The real multi-gigabyte clean-home proof is
`tests/west-backend/run.sh` (see `tests/west-backend/README.md`): manual,
requires fresh explicit approval per run, and is not part of normal CI.

## Constraints

- The west backend supports only `x86_64-linux`; any other system fails
  evaluation with a clear message.
- `gdb-py` (python-enabled gdb) binaries remain unpatched: they need
  `libpython3.10.so.1.0` (Python 3.10 EOL, absent from pinned Nixpkgs) and
  the legacy `libcrypt.so.1` ABI (Nixpkgs libxcrypt ships `libcrypt.so.2`).
  Plain `gdb` and all compilers work.
- `nix-nrf bootstrap` on a fully ready workspace is a no-op (nrfutil parity):
  never prompts, never mutates. The mutating path — venv creation, west init,
  `west update`, and requirement installs — runs only when something is
  missing (approval-gated). This is what keeps the lazy `autoBootstrap =
  true` west wrapper approval-free on every ready invocation.
- West version readiness resolves `-r` includes in the requirement files and
  compares every parsed operator (==, >=, >, <=, <); it accepts any version
  satisfying the resolved constraints (e.g. `west>=1.4.0`) and never demands
  the tested 1.4.0 pin after requirement installation. The mutating path
  warns that completing setup runs `west update` + requirement installs,
  which may access the network.
- NCS v3.3.0's loose requirement files cannot alone produce a working venv:
  `zcbor==0.8.1` imports `CBORDecodeValueError`, removed in `cbor2` 6.x,
  while `nrf/scripts/requirements-build.txt` allows `cbor2>=5.4.2.post1`
  unbounded, which admits the incompatible `cbor2` 6.x line. NCS's own
  `requirements-fixed.txt` pins `cbor2==5.9.0`; the backend encodes that
  verbatim as the metadata `pipConstraints = ["cbor2==5.9.0"]` and applies
  it via `pip install -c`. Additionally, `nrf-regtool` 9.2.1 provides the
  `nrfregtool` module (not `nrf_regtool`), which the readiness import check
  uses.
- No scheduled CI workflow; normal CI runs the fixture/metadata/quoting/
  boundary gates and builds the west SDK package (no workspace download).
  The real clean-home proof remains manual and requires fresh explicit
  approval for each run.

## Future work

Open direction is tracked in `docs/development/roadmap.md`: additional NCS
releases and platforms once their metadata and clean-home proof exist, plus
workflow/caching policy for CI. Pure Nix-native `sdk-nrf` backend research
lives in `docs/development/sdk-nrf-feasibility-draft.md`.
