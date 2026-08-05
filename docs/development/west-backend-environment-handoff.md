# `west` Backend Phase 1 — Environment and Manual-Flow Proof

## Goal

Prove the accepted hybrid installation model before changing public
`mkNrfShell` backend selection:

- Nix supplies exact Zephyr SDK 0.17.0, compiler targets, Python 3.12, and host
  tools.
- Standard west creates/updates mutable NCS v3.3.0 source workspace.
- Standard Python virtual environment contains west and requirements from that
  checked-out workspace.
- No nrfutil, sdk-manager, or Nordic opaque toolchain bundle participates.
- Real XIAO nRF54L15 sysbuild succeeds from a clean isolated HOME.

This phase adds a dedicated prototype environment and setup helper. Public
`backend = "west"` integration follows only after this behavior passes.

## Grounding

### Official NCS v3.3.0 manual flow

`nrf/doc/nrf/installation/install_ncs.rst:434-703` documents alternative
system-wide installation:

1. install Zephyr host dependencies;
2. create/activate Python venv (`python3 -m venv ~/ncs/.venv`);
3. `pip install west`;
4. `west init -m https://github.com/nrfconnect/sdk-nrf --mr v3.3.0`;
5. `west update`;
6. install:
   - `zephyr/scripts/requirements.txt`;
   - `nrf/scripts/requirements.txt`;
   - `bootloader/mcuboot/scripts/requirements.txt`;
7. install matching Zephyr SDK;
8. source `zephyr/zephyr-env.sh` for command-line work.

Nordic explicitly recommends a venv to avoid Python conflicts
(`install_ncs.rst:454-459`). Updating remains ordinary Git + west:
`git fetch`, `git checkout`, `west update` (`updating.rst:99-150`).

### Nix boundary

This phase replaces system package installation and Zephyr SDK installation,
but preserves official workspace/venv ownership:

| Concern | Owner |
|---|---|
| Python 3.12 interpreter | Nix |
| CMake/Ninja/dtc/gperf/Git/ccache/dfu-util | Nix |
| Zephyr SDK 0.17.0 + compiler archives | Nix |
| OpenOCD/udev/probe tools | nix-nrf-dev |
| NCS Git repositories | west workspace |
| west executable and NCS Python requirements | version-local venv |
| application/build output | consumer workspace/project |

Venv-owned west is intentional: Zephyr/NCS requirements may upgrade or
downgrade west, and CMake checks that west uses the expected interpreter.

### zephyr-nix comparison

Current `nix-community/zephyr-nix` validates architecture pattern—minimal SDK
archive, selected compiler archives, setup hook, Nix host tools—but is not a
drop-in dependency:

- current `sdks."0_17"` metadata is Zephyr SDK 0.17.4, while NCS v3.3.0
  specifies 0.17.0 in `nrf/scripts/tools-versions-linux.yml`;
- `pythonEnv` reads Zephyr requirements only, not NCS/module requirements;
- it does not manage west workspaces;
- repository has no declared root license as checked August 2026.

Do not add it as input or copy code. Independently package official SDK assets.

## Exact files

Add:

```text
nix/west-backend/versions.nix
nix/west-backend/zephyr-sdk.nix
nix/west-backend/environment.nix
bin/nix-nrf-west-setup
nix/nix-nrf-west-setup.nix
tests/west-backend/run.sh
tests/west-backend/README.md
docs/development/west-backend-status.md
```

## Version metadata

`nix/west-backend/versions.nix` is plain attrset keyed by NCS release. Initial
entry:

```nix
"v3.3.0" = {
  ncsVersion = "v3.3.0";
  testedWestVersion = "1.4.0";
  python = "3.12";
  zephyrSdk = {
    version = "0.17.0";
    targets = [ "arm-zephyr-eabi" "riscv64-zephyr-elf" ];
    # x86_64-linux official asset URLs + hashes
  };
  requirements = [
    "zephyr/scripts/requirements.txt"
    "nrf/scripts/requirements.txt"
    "bootloader/mcuboot/scripts/requirements.txt"
  ];
};
```

No builder file may contain v3.3.0-specific versions, requirements, asset
names, or target lists. Assert metadata shape. Prototype supports only
`x86_64-linux`; fail clearly elsewhere.

## Zephyr SDK package

`nix/west-backend/zephyr-sdk.nix` takes `pkgs` + selected metadata.

Fetch official v0.17.0 release assets with fixed hashes verified against
official `sha256.sum`:

- `zephyr-sdk-0.17.0_linux-x86_64_minimal.tar.xz`;
- `toolchain_linux-x86_64_arm-zephyr-eabi.tar.xz`;
- `toolchain_linux-x86_64_riscv64-zephyr-elf.tar.xz`.

Unpack minimal archive and compiler archives into one derivation, matching
official SDK directory layout. Remove interactive setup/registration need;
apply `autoPatchelfHook` and required runtime libraries. Add setup hook:

```bash
export ZEPHYR_TOOLCHAIN_VARIANT=zephyr
export ZEPHYR_SDK_INSTALL_DIR=@out@
```

Validation inside derivation:

- `sdk_version` equals 0.17.0;
- ARM and RISC-V compiler binaries execute `--version`;
- CMake package files exist;
- no installer downloads occur during build.

Expose temporary package:

```text
packages.west-zephyr-sdk-v3_3_0
```

## Setup helper

Add Python `bin/nix-nrf-west-setup`, packaged internally at
`$out/libexec/nix-nrf/west-setup` by `nix/nix-nrf-west-setup.nix`.

Wrapper sets exact Nix Python executable and metadata defaults:

- `NIX_NRF_WEST_PYTHON`;
- `NIX_NRF_WEST_NCS_VERSION`;
- `NIX_NRF_WEST_TESTED_WEST_VERSION`;
- serialized requirement paths.

Public prototype command is temporary:

```text
nix-nrf-west-setup [--workspace PATH] [--yes] [--check] [--print-workspace]
```

Default workspace at runtime:

```text
$HOME/ncs/<ncsVersion>
```

Workspace layout:

```text
$HOME/ncs/v3.3.0/
├── .venv/
├── .west/
├── nrf/
├── zephyr/
├── bootloader/
└── modules/...
```

### Setup behavior

`--check` is read-only. Ready requires:

- workspace `.west/config`;
- `nrf/west.yml`;
- `zephyr/zephyr-env.sh`;
- all configured requirements files;
- `.venv/bin/python`, `.venv/bin/pip`, `.venv/bin/west`;
- venv Python import checks for `west`, `yaml`, `elftools`, `zcbor`, and
  `nrf_regtool`;
- venv west reports a version satisfying installed workspace requirements
  (do not require exact 1.4.0 after requirement installation).

Exit 0 ready, 1 missing/broken, 2 CLI/approval.

Mutating setup:

1. print version, workspace, network/size warning;
2. require interactive confirmation or `--yes`;
3. create workspace directory;
4. create `.venv` using exact Nix Python when absent;
5. run venv pip as `python -m pip`, never ambient pip;
6. install `west==testedWestVersion` before workspace creation;
7. when `.west` absent, run exact venv west:

   ```bash
   west init -m https://github.com/nrfconnect/sdk-nrf \
     --mr <ncsVersion> <workspace>
   ```

8. run `west update` from workspace;
9. install each metadata requirement file with venv Python/pip in declared
   order;
10. rerun readiness check.

Do not run `west zephyr-export` (global CMake registry mutation unnecessary;
environment sets `ZEPHYR_BASE`). Do not run `west sdk install`, nrfutil, sudo,
or source arbitrary shell scripts.

Existing workspace safety:

- If `.west` exists but `nrf/west.yml`/venv structure is incompatible, fail;
  never delete/reset it.
- Never automatically `git checkout` or switch existing manifest revision.
- Re-running setup may run `west update` and reinstall requirements for current
  manifest; document mutation.
- `--check` never touches network.

All subprocesses use argument arrays. Preserve output. Add timeout only to
read-only version checks, not long installs.

## Prototype environment

`nix/west-backend/environment.nix` creates a dedicated `pkgs.mkShell` using:

- exact Zephyr SDK derivation;
- Python 3.12 with venv support;
- cmake, ninja, dtc, gperf, Git, ccache, dfu-util, file, xz, make, which;
- multilib GCC on x86_64 Linux;
- existing openocd-master, `nix-nrf probes`, doctor/udev tooling where
  composition is straightforward;
- setup helper.

Do not include nrfutil or sdk-manager.

Add scoped `west` wrapper to prototype shell:

1. resolve workspace default from HOME/version;
2. require setup helper `--check` success, otherwise print
   `Run: nix-nrf-west-setup`;
3. prepend `.venv/bin` only inside west process;
4. export:
   - `ZEPHYR_BASE=$workspace/zephyr`;
   - `ZEPHYR_TOOLCHAIN_VARIANT=zephyr`;
   - `ZEPHYR_SDK_INSTALL_DIR=<Nix SDK>`;
5. keep project OpenOCD ahead of other runners;
6. exec exact `$workspace/.venv/bin/west`.

Shell hook is read-only: banner, workspace path, setup readiness, optional
`ZEPHYR_BASE` when source exists. It does not activate venv globally and does
not run setup/update/pip.

Add:

```text
devShells.west-prototype
```

This is explicitly not public backend yet.

## Tests

### Fixture tests

Add stdlib unittest for setup helper with fake Python/venv west/pip boundaries.
Cover:

1. missing workspace check;
2. ready workspace check and one printed path;
3. noninteractive approval requirement;
4. initial command order and exact argument arrays;
5. requirements installed in metadata order;
6. re-run does not call west init again;
7. incompatible existing workspace rejected without deletion;
8. failed west update/pip/readiness propagates;
9. `--check` no mutation/network commands;
10. default workspace uses isolated HOME/version.

Wire `checks.west-setup-tests` and cheap metadata schema check. Normal checks
may build Zephyr SDK package only after real proof passes; source workspace
download never runs in normal flake check.

### Real clean-home proof

`tests/west-backend/run.sh` follows clean-room harness safety patterns:

- script-created isolated HOME under `/tmp`;
- default 25 GiB free-space guard;
- cleanup only script-owned path; KEEP override;
- no use of developer `$HOME/ncs`;
- real network setup explicitly approved by user;
- no hardware/flashing.

Lifecycle 1:

```bash
nix develop .#west-prototype --ignore-env \
  --set-env-var HOME <clean-home> \
  --command nix-nrf-west-setup --yes
```

Assert workspace + venv ready and Zephyr SDK points into `/nix/store`, not
clean HOME or Nordic toolchain bundle.

Lifecycle 2, fresh shell:

```bash
nix develop .#west-prototype --ignore-env \
  --set-env-var HOME <same-home> \
  --command west build -p always \
    -b xiao_nrf54l15/nrf54l15/cpuapp \
    --sysbuild \
    -d <clean-home>/build/blinky \
    <clean-home>/ncs/v3.3.0/zephyr/samples/basic/blinky
```

Assert non-empty ELF and domains.yaml. Record setup/build times, workspace/venv
sizes, SDK store path, compiler/version output, and absence of nrfutil.

## CI policy

Do not add full real setup to normal CI. Add no scheduled workflow this phase.
Normal CI may build fixed SDK package and run helper fixture tests after local
proof. Real mutable west setup remains local evidence until public backend
integration defines manual workflow/caching.

## Documentation

Add `docs/development/west-backend-status.md` with evidence and limitations.
Update README experimental section and goals. Mark prior `sdk-nrf` prototype
handoff superseded. Keep public `sdk-nrf` rejection and nrfutil default
unchanged.

## Scope

In scope:

- Exact Nix Zephyr SDK 0.17.0 package.
- Nix host-tool prototype shell.
- Official mutable west + venv setup helper.
- Real clean-home source/venv/build proof.

Out of scope:

- Public `backend = "west"` selector (next phase).
- CLI replacement of temporary helper name (next phase).
- Full Nix Python environment.
- Immutable/fixed NCS repositories.
- nrfutil backend changes.
- Updating existing workspace revision automatically.
- flashing/hardware.
- direct zephyr-nix dependency/source.

## Verification

```bash
nix fmt
nix flake check -L
nix build -L .#west-zephyr-sdk-v3_3_0
nix develop .#west-prototype --command sh -ceu '
  test "$ZEPHYR_SDK_INSTALL_DIR" = /nix/store/*
  test "$ZEPHYR_TOOLCHAIN_VARIANT" = zephyr
  ! command -v nrfutil
  nix-nrf-west-setup --help >/dev/null
'
bash tests/west-backend/run.sh
nix flake check -L
```

No real setup starts until fixed SDK package and fixture gates pass.

## Commit and recap

Commit this plan separately. Commit passing implementation/evidence:

```text
feat(west): prove Nix-managed manual environment
```

Do not push, merge, amend, open PR, flash hardware, use developer NCS state, or
add attribution. Return asset hashes, commands, setup/build timings, sizes,
artifact evidence, no-nrfutil proof, tests, commit hash/message, blockers, and
deviations. Public backend must remain disabled in this phase.
