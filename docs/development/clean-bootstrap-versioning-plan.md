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

- `mkNrfShell` already accepts `ncsVersion`, defaulting to `"v3.3.0"` in
  `nix/mk-nrf-shell.nix`.
- `mkNrfShell` also accepts `backend`, defaulting to `"nrfutil"`. `nrfutil`
  (Nordic sdk-manager) is the only implemented backend; `sdk-nrf` is reserved
  for the future Nix-native backend and fails evaluation until implemented.
  Omission and explicit `backend = "nrfutil"` are equivalent; any other value
  fails at Nix evaluation rather than silently falling back.
- Consumer flakes can select another release per directory. The template
  already passes `ncsVersion = "v3.3.0"` explicitly.
- Nordic's sdk-manager supports several SDK releases side by side under
  `$HOME/ncs/<version>` and stores toolchains separately under
  `$HOME/ncs/toolchains/<bundle-id>`.
- The current `west` wrapper selects its toolchain with `--ncs-version`, so two
  project directories can select different installed NCS versions through
  their respective flakes and direnv environments.
- `nix/nrfutil-core.nix` does not package the complete nRF Util core despite its
  name. It packages Nordic's launcher executable. On first execution, that
  launcher downloads and installs the actual core module into
  `$NRFUTIL_HOME` or `$HOME/.nrfutil`.
- The derivation is labelled `8.1.1`, while a clean first run currently installs
  and reports core `8.2.0`. The fetched launcher's unversioned URL follows
  Nordic's latest release; the fixed Nix hash prevents silent replacement but
  causes future cold builds to fail when Nordic updates that URL.
- The sdk-manager command is another independently versioned binary installed
  into nRF Util home by `nrfutil install sdk-manager`.
- `nrfutil sdk-manager install <ncs-version>` installs both SDK source and its
  matching toolchain. The command currently suggested by the `west` wrapper,
  `toolchain install --ncs-version`, installs only the toolchain and therefore
  cannot satisfy `ZEPHYR_BASE`.
- CI checks that the wrapper exists but never runs a real `west` build. Existing
  hardware CI assumes NCS v3.3.0 already exists on the self-hosted runner.

## Version model

Treat these as distinct inputs:

| Input | Meaning | Default policy | Consumer override |
|---|---|---|---|
| `ncsVersion` | NCS source release, such as `v3.3.0` | One tested release per nix-nrf-dev revision | Yes, string |
| `toolchainBundleId` | Exact patched Nordic toolchain bundle | `null`, meaning latest compatible patch for `ncsVersion` | Yes, optional string |
| `sdkManagerVersion` | nRF Util sdk-manager command | Exact tested version | Yes, from supported versions |
| `nrfutilVersion` | nRF Util launcher/core pair | Exact tested version | Yes, from supported versions or package override |

`ncsVersion` alone is release-level pinning. Nordic documents that
`sdk-manager install vX.Y.Z` and `toolchain env --ncs-version vX.Y.Z` select the
newest patched toolchain associated with that SDK release. Fully repeatable CI
must also set `toolchainBundleId` and make the wrapper use
`--toolchain-bundle-id`.

Do not accept arbitrary `nrfutilVersion` strings without a corresponding source
URL and Nix hash. Keep supported nRF Util versions in repository data, for
example `nix/versions.nix`, or allow an advanced caller to provide an
`nrfutilPackage` override. Keep one set of defaults shared by package creation,
`mkNrfShell`, template, bootstrap helper, and tests.

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

1. Detect whether the selected nRF Util core and sdk-manager command exist in
   the controlled nRF Util home.
2. Install the exact configured sdk-manager command when missing.
3. Detect whether both selected SDK source and toolchain exist.
4. Run `nrfutil sdk-manager install <ncsVersion>` when either is missing, or
   install SDK and exact toolchain separately when `toolchainBundleId` is set.
5. Load the selected toolchain environment.
6. Resolve and export `ZEPHYR_BASE` for the west process.
7. Execute real west command.

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
  sdkManagerVersion = defaults.sdkManagerVersion;
  nrfutilVersion = defaults.nrfutilVersion;
  autoBootstrap = true;
}
```

Boolean `autoBootstrap` keeps common configuration simple. If future behavior
needs more states, migrate to `bootstrapMode = "on-demand" | "manual"` before
stabilizing a 1.0 API rather than adding several booleans.

### Controlled mutable state

Global `$HOME/.nrfutil` makes projects requesting different core/plugin
versions overwrite each other. Use a version-keyed nRF Util home owned by this
library, such as:

```text
${XDG_CACHE_HOME:-$HOME/.cache}/nix-nrf-dev/nrfutil/
  <system>/<nrfutil-version>-<sdk-manager-version>/
```

Set this path only inside wrapped `nrfutil`, `nrf-bootstrap`, and `west`
processes so Nordic's Python and library variables remain scoped. Projects with
the same versions share small command state; projects with different versions
do not conflict.

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

### Phase 1: correct nRF Util packaging and version configuration

Files:

- `nix/nrfutil-core.nix`
- new `nix/versions.nix` or equivalent package data
- `flake.nix`
- `nix/mk-nrf-shell.nix`
- `templates/default/flake.nix`
- `README.md`

Work:

1. Separate Nordic launcher version from core-module version in naming and
   comments.
2. Fetch versioned launcher and matching core tarball with fixed hashes.
3. Use Nordic's documented `NRFUTIL_BOOTSTRAP_TARBALL_PATH` so first run does
   not select latest core from network.
4. Preserve `packages.nrfutil-core` as compatibility alias if package gets a
   more accurate name.
5. Add tested defaults and public overrides described above.
6. Make toolchain selector choose bundle ID when supplied, otherwise NCS
   version.
7. Correct missing-install diagnostics to name both
   `nrfutil install sdk-manager=<version>` and
   `nrfutil sdk-manager install <ncsVersion>`.

Verification:

```bash
nix build -L .#nrfutil-core
HOME="$(mktemp -d)" nix run .#nrfutil-core -- --version
nix flake check -L
```

Observable acceptance: isolated first run reports configured nRF Util version,
not registry's current latest, and does not read host `$HOME/.nrfutil`.

### Phase 2: bootstrap helper and sdk-manager strategy

Files expected if imperative install remains preferred:

- new `nix/nrf-bootstrap.nix`
- new `bin/nrf-bootstrap` or generated shell wrapper
- `nix/mk-nrf-shell.nix`
- `flake.nix`
- `README.md`

Implement explicit helper plus lazy west integration. Install exact
sdk-manager version through Nordic's supported command interface into
version-keyed nRF Util home. Direct sdk-manager binary packaging is rejected:
current source is not public, top-level redistribution terms are unclear, and
reproducing nRF Util's private package layout would add maintenance without
meaningful user benefit. The supported pinned command is:

```bash
nrfutil install sdk-manager=<version> --force
```

Revisit only as part of a separately approved, fully offline NCS closure. Do
not publish Nordic command binaries through Cachix without confirmed
redistribution rights.

Verification:

- Empty controlled nRF Util home.
- `nrf-bootstrap --yes` installs configured sdk-manager and selected SDK.
- Re-running helper is idempotent and downloads nothing already installed.
- `autoBootstrap = false` performs no network or mutation and reports exact
  helper command.
- Two controlled homes with different sdk-manager versions coexist.

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

1. First entry starts with no nRF Util state or `$HOME/ncs`, bootstraps selected
   sdk-manager, SDK, and toolchain.
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

Cache key must include OS, architecture, NCS version, sdk-manager version, nRF
Util version, and exact bundle ID when used. Restore to same absolute path.
Measure Nordic download versus Actions cache upload/restore before committing to
cache; unpacked toolchain alone is approximately 4.3 GiB on current Linux host,
so caching may not be a net win.

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
One tested default is a convenience only. Supporting multiple releases is a
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

- per-project NCS release selection,
- optional exact toolchain bundle selection,
- pinned nRF Util and sdk-manager versions,
- side-by-side projects using different versions,
- lazy automatic bootstrap with explicit opt-out,
- clean-home nRF54L15 blinky build,
- user-facing hardware permission diagnosis.

Out of scope for initial implementation:

- two active NCS versions in one shell,
- automatic host udev installation or `sudo`,
- flashing hardware from hosted CI,
- arbitrary unverified nRF Util version strings,
- macOS support expansion,
- Linux ARM64 toolchain installation (Nordic documents sdk-manager toolchain
  installation as unsupported there),
- full NCS/toolchain packaging in Nix store.

## Open decisions before implementation handoff

1. Keep simple `autoBootstrap` boolean or adopt explicit bootstrap-mode enum
   before API stabilization.
2. Pin exact toolchain bundle by default for tested release, or preserve
   Nordic's latest-compatible-patch behavior for normal users and pin only CI.
3. Exact supported defaults for nRF Util core and sdk-manager after verifying
   their compatibility with selected NCS default.
4. Whether Cachix redistribution terms permit direct caching of Nordic binary
   command/toolchain artifacts.
5. Whether to keep `ncsVersion` default at v3.3.0 for first implementation or
   move tested default in a separate intentional update.

## Source notes

- Nordic documents current nRF Util as central executable plus independently
  versioned core and command packages from an online registry.
- Nordic documents pinned core bootstrap through
  `NRFUTIL_BOOTSTRAP_TARBALL_PATH` and exact command installation through
  `nrfutil install sdk-manager=<version> --force` or installation sets.
- Nordic documents side-by-side SDKs under `$HOME/ncs/<version>`, toolchains
  under `$HOME/ncs/toolchains/<bundle-id>`, and exact toolchain selection through
  `--toolchain-bundle-id`.
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
