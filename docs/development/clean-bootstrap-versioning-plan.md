# Clean Bootstrap, Versioning, and Build Verification Plan

Status: discussion draft. This document records the proposed direction; it is
not an implementation handoff yet.

## Goal

Make a project created with `nix-nrf-dev` usable on a Linux host that has Nix
but no pre-existing nRF Util state, nRF Connect SDK checkout, or Nordic
toolchain. Preserve fast shell entry, support different NCS versions in
different project directories, and prove the result by building Zephyr blinky
for the XIAO nRF54L15 in an isolated home directory.

## Current repository behavior

- `mkNrfShell` requires `ncsVersion` (e.g. `"v3.3.0"`): every caller selects
  an NCS release explicitly; there is no `"latest"` alias or default.
- `mkNrfShell` accepts `backend` (default `"nrfutil"`). `nrfutil` (Nordic
  sdk-manager) is the only implemented backend; `sdk-nrf` is reserved for the
  future Nix-native backend and fails evaluation until implemented. Omission
  and explicit `backend = "nrfutil"` are equivalent; any other value fails at
  Nix evaluation rather than silently falling back.
- nrfutil and the sdk-manager extension come from Nixpkgs:
  `pkgs.nrfutil.withExtensions [ "nrfutil-sdk-manager" ]`. Extension archives,
  versions, and hashes are maintained by Nixpkgs and pinned via `flake.lock`
  (consumers can replace the revision through
  `inputs.nix-nrf-dev.inputs.nixpkgs.follows`). The derivation unconditionally
  depends on `segger-jlink-headless`, so `config.segger-jlink.acceptLicense`
  is required — there is no sdk-manager-only composition that avoids J-Link.
- Consumer flakes can select another release per directory. The template
  passes `ncsVersion = "v3.3.0"` explicitly.
- Nordic's sdk-manager supports several SDK releases side by side under
  `$HOME/ncs/<version>` and stores toolchains separately under
  `$HOME/ncs/toolchains/<bundle-id>`.
- The `west` wrapper selects the toolchain with `--ncs-version` by default
  (newest compatible patched toolchain for the release), or with
  `--toolchain-bundle-id <bundle-id>` when an exact bundle is configured, so
  two project directories can select different installed NCS versions through
  their respective flakes and direnv environments.
- `nrf-sdk-versions` delegates to `nrfutil sdk-manager search`, so
  sdk-manager remains the runtime authority for available NCS versions; the
  nrfutil backend does not reject a version because it is absent from
  repository-owned metadata.
- `nrfutil sdk-manager install <ncs-version>` installs both SDK source and its
  matching toolchain; `nrfutil sdk-manager sdk install <ncs-version>` installs
  only the SDK source. The `west` wrapper's failure diagnostics distinguish
  missing SDK source from toolchain selection: the plain install command for
  the default selector, or `sdk install` plus
  `toolchain install --toolchain-bundle-id <bundle-id>` when an exact bundle
  is configured.
- CI checks that the wrapper exists but never runs a real `west` build.
  Existing hardware CI assumes NCS v3.3.0 already exists on the self-hosted
  runner.

## Version model

Treat these as distinct inputs:

| Input | Meaning | Default policy | Consumer override |
|---|---|---|---|
| `ncsVersion` | NCS source release, such as `v3.3.0` | None — required explicit selection (one tested release per nix-nrf-dev revision) | Yes, string (required) |
| `toolchainBundleId` | Exact patched Nordic toolchain bundle | `null`, meaning latest compatible patch for `ncsVersion` | Yes, optional string |
| nrfutil/sdk-manager versions | Packaged by Nixpkgs | Pinned via `flake.lock` | Replace the Nixpkgs revision (`inputs.nixpkgs.follows`) or pass `nrfutilPackage` to `mkNrfShell` |

`ncsVersion` alone is release-level pinning. Nordic documents that
`sdk-manager install vX.Y.Z` and `toolchain env --ncs-version vX.Y.Z` select
the newest patched toolchain associated with that SDK release. Fully
repeatable CI must also set `toolchainBundleId` and make the wrapper use
`--toolchain-bundle-id`.

nrfutil/sdk-manager versions are Nixpkgs' responsibility, not repository
metadata: Nixpkgs maintains the extension archives and hashes. An advanced
caller who needs a different nrfutil composition supplies `nrfutilPackage`
without replacing all of Nixpkgs. There is no repository-owned
`supportedNcsVersions` list for the nrfutil backend.

Changing a project directory's `ncsVersion` and reloading direnv selects another
side-by-side installation. One active direnv should expose one SDK version;
mixing two SDK environments in one shell is out of scope and likely unsafe
because both toolchains set `PATH`, `PYTHONHOME`, `PYTHONPATH`, and dynamic
library variables.

## Bootstrap user experience

### Recommended default: lazy automatic bootstrap

Do not download several gigabytes from `shellHook`. `nix develop` and direnv
entry must remain fast, work offline when the SDK is already installed, and not
start a long mutation merely because a user opened a directory.

Instead, make first SDK-dependent `west` invocation perform bootstrap when
`autoBootstrap = true`, which is the default:

1. Detect whether both the selected SDK source and its toolchain exist.
2. Run `nrfutil sdk-manager install <ncsVersion>` when either is missing, or
   install SDK source (`sdk-manager sdk install <ncsVersion>`) and the exact
   toolchain (`toolchain install --toolchain-bundle-id <bundle-id>`) when
   `toolchainBundleId` is set.
3. Load the selected toolchain environment.
4. Resolve and export `ZEPHYR_BASE` for the west process.
5. Execute real west command.

This removes a mandatory setup command while avoiding a long download during
shell entry. Before downloading, print selected versions, destination, expected
large-download warning, and opt-out name. On an interactive terminal, require
one confirmation before the first large download. Without a terminal, fail
unless an explicit `--yes` flag or CI environment variable allows bootstrap, so
automation cannot hang or mutate state unexpectedly.

Expose an explicit `nrf-bootstrap` command for users who want to provision
before running west. With `autoBootstrap = false`, west must fail with one exact
remediation command rather than mutating state.

Proposed public shape, subject to implementation review:

```nix
mkNrfShell {
  backend = "nrfutil"; # only implemented backend; sdk-nrf is the future backend
  ncsVersion = "v3.3.0";
  toolchainBundleId = null;
  autoBootstrap = true;
}
```

Boolean `autoBootstrap` keeps common configuration simple. If future behavior
needs more states, migrate to `bootstrapMode = "on-demand" | "manual"` before
stabilizing a 1.0 API rather than adding several booleans.

### Mutable state

nrfutil and sdk-manager binaries are packaged in the Nix store; this phase
installs no command binaries at runtime and does not isolate `NRFUTIL_HOME`.
The mutable SDK source and toolchain live under Nordic's default roots
(`$HOME/ncs`), and nrfutil/sdk-manager may still write their own config,
index/cache, and log state under their normal home (`$HOME/.nrfutil` or
`$NRFUTIL_HOME` when set) — nothing redirects or controls that state.

Keep Nordic's default shared SDK root (`$HOME/ncs`) initially. It already
supports multiple SDK releases and shared toolchain bundles. A later optional
`ncsInstallDir` can support CI or unusual disk layouts, but path discovery must
then use sdk-manager's JSON output rather than assuming `$HOME/ncs`.

### ZEPHYR_BASE lifecycle

When selected SDK is already installed, shell hook exports `ZEPHYR_BASE` as it
does now. When lazy bootstrap installs SDK during first west call, wrapper must
set `ZEPHYR_BASE` inside west's process before executing real west. Parent shell
cannot receive environment changes from a child process; bootstrap output
should suggest `direnv reload` or shell re-entry if user wants the variable in
subsequent non-west commands.

Resolve SDK directory through `nrfutil sdk-manager list --json` or another
documented machine-readable sdk-manager interface. Keep `$HOME/ncs/<version>`
only as explicit fallback. Current derivation from
`ZEPHYR_SDK_INSTALL_DIR` and fixed parent-directory counts is fragile.

## Phased work

### Phase 1 (done): Nixpkgs nrfutil/sdk-manager migration

Files:

- `flake.nix`
- `nix/mk-nrf-shell.nix`
- `nix/nrf-sdk-versions.nix`
- `templates/default/flake.nix`
- `README.md`
- `.github/workflows/ci.yml`

Work:

1. Switch the Nixpkgs input to `nixos-unstable` (pinned in `flake.lock`).
2. Compose `pkgs.nrfutil.withExtensions [ "nrfutil-sdk-manager" ]`, expose it
   as `packages.nrfutil`, and require SEGGER license acceptance
   (`config.segger-jlink.acceptLicense = true`) in the Nixpkgs import.
3. Make `ncsVersion` a required argument; add optional `toolchainBundleId`
   and the public `nrfutilPackage` override.
4. Select the toolchain with `--ncs-version` (or `--toolchain-bundle-id` when
   set) with Nix shell escaping, and fix failure diagnostics to distinguish
   SDK source from toolchain selection.
5. Add `nrf-sdk-versions` delegating to `nrfutil sdk-manager search`, exposed
   as `packages.nrf-sdk-versions` and instantiated from the selected
   `nrfutilPackage` inside `mkNrfShell`.
6. Delete the custom launcher package and update CI.

Verification:

```bash
nix fmt
nix flake check -L
nix build -L .#nrfutil .#nrf-sdk-versions
nix run .#nrfutil -- --version
nix run .#nrf-sdk-versions -- --help
nix develop --command sh -ceu 'command -v nrfutil; command -v nrf-sdk-versions; command -v openocd; command -v nrf-probes'
```

Observable acceptance: public nrfutil backend comes from pinned/followable
Nixpkgs with sdk-manager in the Nix store; missing `ncsVersion` fails
evaluation; arbitrary explicit NCS strings reach sdk-manager; omitted bundle
ID uses latest compatible patched toolchain, explicit bundle ID stays exact;
`nrf-sdk-versions` delegates to sdk-manager; SEGGER/J-Link consequence is
explicit.

### Phase 2: bootstrap helper and lazy west integration

Files expected:

- new `nix/nrf-bootstrap.nix`
- new `bin/nrf-bootstrap` or generated shell wrapper
- `nix/mk-nrf-shell.nix`
- `flake.nix`
- `README.md`

Implement explicit helper plus lazy west integration. sdk-manager is already
packaged in the Nix store (Phase 1), so bootstrap only provisions SDK source
and toolchain through Nordic's supported interface:

```bash
nrfutil sdk-manager install <ncsVersion>
```

Verification:

- No SDK/toolchain installed for the selected release.
- `nrf-bootstrap --yes` installs the selected SDK and matching toolchain.
- Re-running helper is idempotent and downloads nothing already installed.
- `autoBootstrap = false` performs no network or mutation and reports exact
  helper command.

### Phase 3: clean-home NCS build test

Files:

- new `tests/clean-room/run.sh`
- `.github/workflows/ci.yml` or new dedicated workflow
- `CONTRIBUTING.md`

Use Nix's environment isolation rather than inheriting developer state:

```bash
nix develop .#clean-env-test \
  --ignore-env \
  --set-env-var HOME <stable-clean-home> \
  --command ...
```

Test two lifecycle entries:

1. First entry starts with no nRF Util state or `$HOME/ncs`, bootstraps
   selected sdk-manager, SDK, and toolchain.
2. Second entry proves shell derives `ZEPHYR_BASE`, proves path belongs to clean
   home, and builds blinky:

```bash
west build -p \
  -b xiao_nrf54l15/nrf54l15/cpuapp \
  --sysbuild \
  "$ZEPHYR_BASE/samples/basic/blinky"
```

Local NCS v3.3.0 evidence:

- board identifier:
  `zephyr/boards/seeed/xiao_nrf54l15/xiao_nrf54l15_nrf54l15_cpuapp.yaml`
- board metadata declares `sysbuild: true`
- sample path: `zephyr/samples/basic/blinky`

Explicit `--sysbuild` keeps acceptance intent visible even though NCS v3.3.0
enables sysbuild by default.

CI split:

- PR job: restore version-keyed SDK/toolchain cache when practical, then always
  run blinky build.
- scheduled/manual cold job: bypass cache, prove full bootstrap from empty
  home, then run same build.
- normal `nix flake check`: never trigger multi-gigabyte network install.

Cache key must include OS, architecture, NCS version, and exact bundle ID when
used. Restore to same absolute path. Measure Nordic download versus Actions
cache upload/restore before committing to cache; unpacked toolchain alone is
approximately 4.3 GiB on current Linux host, so caching may not be a net win.

### Phase 4: hardware access guidance and diagnostics

Avoid building a permanent in-repo VID/PID catalog as first solution.

Add or extend `nrf-doctor` to:

- enumerate visible CMSIS-DAP/J-Link/USB probe candidates,
- report whether relevant hidraw/USB nodes are readable by current user,
- show current groups and likely udev failure,
- print NixOS and non-NixOS remediation paths,
- distinguish missing hardware from permission denial,
- never invoke `sudo` or mutate host configuration automatically.

Prefer upstream udev rules supplied by OpenOCD, probe vendors, or nixpkgs. A
small NixOS module or `packages.udev-rules` output may compose those upstream
rules, but custom rules should be limited to hardware this repository actually
tests. Documentation remains necessary because dev shells cannot activate host
udev policy.

Verification uses fake sysfs/device fixtures for diagnostic classification plus
manual hardware-runner confirmation. User-observable acceptance: failed probe
access yields actionable host-specific guidance rather than generic
"unable to open device" output.

### Deferred Phase 5: Nix-native NCS build backend (`sdk-nrf`)

Research only after phases 1-3 establish behavior. Do not repackage Nordic's
opaque sdk-manager toolchain bundle as primary approach. Current nrfutil and
sdk-manager are closed source, bundle layout is undocumented, and binary
redistribution through Cachix needs legal review. This makes direct bundle
repackaging a poor maintenance strategy, though not a technical proof of
impossibility.

The `sdk-nrf` backend must use version metadata keyed by NCS release: each
entry derives the west manifest, Nordic Zephyr revision, Zephyr SDK release
and targets, Python requirements, and host-tool versions from that release.
The metadata may mark tested releases, but caller selection stays an
explicit, required `ncsVersion` with no default, matching the current nrfutil
backend API. Supporting multiple releases is a
core acceptance criterion; the backend must not encode v3.3.0 as the sole
architecture. v3.3.0 remains the first proof target because installed source
and hardware test evidence exist, not because the backend is permanently tied
to it.

A clean-room build environment assembled from public components is plausible:

1. Materialize repositories pinned by the selected `sdk-nrf` west manifest.
2. Package exact upstream Zephyr SDK release and only compiler targets listed
   by NCS's `nrf/scripts/tools-versions-<platform>.yml`.
3. Supply host tools from nixpkgs where compatible.
4. Build Python environment from Zephyr and NCS requirement files, using fixed
   wheels/sources from public PyPI and Nordic's publicly readable package
   index.
5. Set `ZEPHYR_BASE`, `ZEPHYR_SDK_INSTALL_DIR`, module paths, and west workspace
   metadata from Nix outputs.
6. Reuse this repository's OpenOCD and probe layer for flashing.

This backend would not need nrfutil for normal builds. nrfutil remains useful
for the supported `nrfutil` automatic installation backend and optional Nordic
device operations. Do not combine Nix-native backend work with initial
clean-bootstrap implementation.

### zephyr-nix findings for deferred hermetic work

`nix-community/zephyr-nix` is useful prior art, not a drop-in NCS environment.
It separates five concerns that this repository should also keep separate:

1. versioned Zephyr SDK archive metadata,
2. selected cross-compiler targets,
3. host tools,
4. Python requirements derived from Zephyr source,
5. west workspace materialization, delegated to `west2nix`.

Patterns worth borrowing:

- Store each supported SDK release and all upstream archive hashes in a small
  generated JSON file. `update-sdk` converts upstream `sha256.sum` into this
  metadata instead of hand-maintaining every target hash. It does not update an
  installed SDK and is irrelevant to nrfutil-managed installs; an equivalent
  helper matters only for Nix-native Zephyr SDK packaging.
- Build SDK from minimal archive plus selected target archives. NCS v3.3.0's
  `nrf/scripts/tools-versions-linux.yml` specifies Zephyr SDK 0.17.0 with only
  `arm-zephyr-eabi` and `riscv64-zephyr-elf`; this is a strong fit for
  zephyr-nix's `sdk.override { targets = [ ... ]; }` model and avoids pulling
  every Zephyr architecture.
- Export `ZEPHYR_SDK_INSTALL_DIR` through a Nix setup hook rather than mutable
  shell discovery.
- Offer nixpkgs-built host tools separately from vendor binary host tools.
  zephyr-nix explicitly warns that some SDK host binaries have libc
  incompatibilities; its `hosttools-nix` composition avoids those binaries.
- Derive Python dependencies from source requirements and keep compatibility
  overrides explicit. For NCS this must include both Nordic's Zephyr-fork
  requirements and `nrf/scripts/requirements*.txt`, not only upstream Zephyr.
- Expose versioned packages and make package outputs checks so every supported
  SDK variant builds in CI.
- Freeze west manifests with revisions and Nix hashes before building. The
  related `west2nix` tool fetches each project as a fixed Nix input and creates
  a writable workspace during the build.

Limits that prevent direct adoption today:

- zephyr-nix defaults to upstream Zephyr, while NCS requires Nordic's Zephyr
  fork plus every repository pinned by `nrf/west.yml`.
- Its Python environment reads Zephyr requirements only. NCS v3.3.0 also pins
  Python 3.12-era packages such as `nrf-regtool` and `zcbor`, some through
  Nordic's package index.
- `west2nix` uses copied repositories and synthetic Git metadata to satisfy
  west. NCS manifest imports, groups, Nordic west commands, and sysbuild need a
  real compatibility prototype before relying on that approach.
- It packages upstream Zephyr SDK, not Nordic's complete toolchain bundle, nRF
  Util, J-Link, hardware permissions, or this repository's OpenOCD behavior.
- Repository has no detected license file at time of review. Borrow design
  ideas, not source code, unless licensing is clarified.

Additional prior art: `MatthewCroughan/nrf-nix` fetched an NCS v2.1.0 west
workspace as a fixed-output derivation, supplied upstream Zephyr SDK and a Nix
Python environment, and built applications without sdk-manager. It is stale and
hard-codes old tool versions, but demonstrates that closed-source nrfutil is not
a fundamental build blocker.

Best deferred experiment: combine NCS's frozen west manifest with
zephyr-nix-style Zephyr SDK 0.17.0 target packaging and a separate NCS Python
environment, then build XIAO nRF54L15 blinky. Keep Nordic sdk-manager path as
supported default until experiment proves equivalent build and hardware
behavior.

Keep both backends (`nrfutil`, `sdk-nrf`) in this repository during prototype
work so OpenOCD, `nrf-probes`, version policy, tests, and templates stay
shared. Consider a separate `sdk-nrf` library only after Nix-native
workspace/toolchain code has a stable API and independent users; splitting
earlier would duplicate policy and make parity testing harder.

## Scope

In scope:

- per-project NCS release selection (required `ncsVersion`),
- optional exact toolchain bundle selection (`toolchainBundleId`),
- side-by-side projects using different versions,
- lazy automatic bootstrap with explicit opt-out,
- clean-home nRF54L15 blinky build,
- user-facing hardware permission diagnosis.

Out of scope for initial implementation:

- two active NCS versions in one shell,
- automatic host udev installation or `sudo`,
- flashing hardware from hosted CI,
- repository-owned nrfutil/sdk-manager version metadata or a static
  supported-NCS-version list (Nixpkgs and sdk-manager own those),
- macOS support expansion,
- Linux ARM64 toolchain installation (Nordic documents sdk-manager toolchain
  installation as unsupported there),
- full NCS/toolchain packaging in Nix store.

## Open decisions before implementation handoff

1. Keep simple `autoBootstrap` boolean or adopt explicit bootstrap-mode enum
   before API stabilization.
2. Pin exact toolchain bundle by default for tested release, or preserve
   Nordic's latest-compatible-patch behavior for normal users and pin only CI.
3. Whether Cachix redistribution terms permit direct caching of Nordic binary
   toolchain artifacts (nrfutil/sdk-manager themselves are store-packaged by
   Nixpkgs; the SDK/toolchain bundle is a separate question).
4. Whether to keep tested example releases at v3.3.0 or move in a separate
   intentional update.

## Source notes

- Nordic documents sdk-manager as the runtime authority for available NCS
  versions, with side-by-side SDKs under `$HOME/ncs/<version>`, toolchains
  under `$HOME/ncs/toolchains/<bundle-id>`, and exact toolchain selection
  through `--toolchain-bundle-id`.
- Nordic documents `--ncs-version` as selecting the newest patched compatible
  toolchain and `sdk-manager install vX.Y.Z` as installing SDK source plus the
  matching toolchain.
- Nixpkgs packages nRF Util and its extensions (`nrfutil`, sdk-manager, ...)
  under `pkgs/by-name/nr/nrfutil`; extension archives, versions, and hashes are
  maintained by Nixpkgs. The derivation unconditionally depends on
  `segger-jlink-headless`.
- Current nRF Util source is not public. Public
  `NordicSemiconductor/pc-nrfutil` is deprecated Python nRF Util v6 and is not
  source for current v7/v8 utility or sdk-manager command.
- Nordic's NCS installation source states that its toolchain is Zephyr SDK plus
  required host tools, Python dependencies, and GN. It is a tested convenience
  bundle, not a different firmware source tree or unique compiler technology.
- `sdk-nrf/west.yml` is the authoritative public repository graph for each NCS
  release. NCS v3.3.0's platform tool-version file selects Zephyr SDK 0.17.0,
  Arm and RISC-V compiler targets, Python 3.12.4, west 1.4.0, and matching host
  tools.
