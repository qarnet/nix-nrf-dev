# Zephyr application types and SDK source selection

Research date: 2026-10-03. This report proposes a direction, not a public API or
a claim that all application types are already qualified. No shell, bootstrap,
initializer, dependency pin, or firmware behavior was changed. No SDK setup,
CMake registry export, hardware access, or firmware build was performed.

Subsequent implementation is tracked as PB-023. See
[current support and qualification](application-source-status.md) and the
[user guide](../application-types.md). Implementation findings below describe
the inspected revision, not the later feature branch.

## Conclusions

Supporting repository, workspace, and freestanding applications is feasible.
The important missing abstraction is **source ownership and selection**, not
three different compiler environments.

- `ZEPHYR_BASE` is not restricted to freestanding applications by Zephyr. It
  explicitly selects a source tree and can override location-based selection
  for repository and workspace applications too.
- Avoid injecting an unrelated managed `ZEPHYR_BASE` into project-owned
  workspaces. This is a useful shell policy, not a Zephyr rule that forbids the
  variable in those applications. West itself can set it in its child process.
- `west zephyr-export` is one discovery mechanism, not a mandatory step for
  every topology. It registers **Zephyr source/build-system packages**, not the
  **Zephyr SDK compiler package**.
- Existing build harnesses already target repository samples. The current
  implementation is better described as **managed-SDK-centric**, not strictly
  freestanding-only. Arbitrary project-owned workspace support is not qualified.
- zephyr-nix illustrates separating tools from mutable source workspaces. It
  does not implement an application-type selector or prove our NCS workflows.

## Evidence and version scope

| Source | Inspected revision |
| --- | --- |
| nix-nrf-dev | `5a7f9022dcecb1af3cf22180b5582db58fc8fadc` |
| Installed NCS v3.3.0 `nrf` | `ba167d9f3db4abbdc9b67887ca3ea66c64f2d956` |
| Installed NCS v3.3.0 `zephyr` | `fd9204a02d52630660ce8d729945a4dd743feabf` |
| nix-community/zephyr-nix | `5ef0903c5fcdbbce55af2732fad1011e90b6ff47` |
| User-linked upstream latest documentation | page identifies Zephyr revision `12b2c89c0f0dfdda807a6aff3670c2380ac2dd3b` |

Installed SDK paths below are relative to `/home/thomas/ncs/v3.3.0`. NCS v3.3.0's
Zephyr VERSION is 4.3.99; the upstream latest page is not our installed-version
contract. Nordic MCP documentation corroborates the application taxonomy and
workspace guidance, but latest documentation and VS Code-specific restrictions
are not substituted for local CLI behavior.

## Application topology

Zephyr defines types by application location, not by compiler installation or
whether a developer uses CMake directly.

| Type | Upstream Zephyr definition | NCS meaning |
| --- | --- | --- |
| Repository | Inside the `zephyr` repository | Inside an SDK repository, including `nrf` and downstream forks |
| Workspace | Inside a west workspace, outside `zephyr` | Inside the workspace, outside SDK repositories; a project manifest can import and pin NCS |
| Freestanding | Outside the west workspace | Outside the SDK workspace; sources selected separately |

For example, `nrf/samples/...` is an NCS repository application, but it is a
workspace application relative to the narrower Zephyr CMake path classification.
Do not implement source selection based on Nordic's label alone.

A workspace application may be the manifest repository (T2 layout), but an
application being inside a workspace does not itself require that it own the
manifest. Several applications can share one workspace. Nordic's recommended
project-owned workspace workflow uses an application manifest importing NCS.
VS Code UI restrictions are not general west limitations.

Building existing repository applications should be supported. Creating new
production applications inside an sdk-manager-managed checkout should not be
our recommended initializer workflow: Nordic warns that this can damage an SDK
installation. A deliberately maintained source fork is a different ownership
case from modifying a shared managed installation.

Evidence: `zephyr/doc/develop/application/index.rst:106-121`,
`nrf/doc/nrf/app_dev/create_application.rst:29-145`, and the
[upstream application guide](https://docs.zephyrproject.org/latest/develop/application/index.html#application-types).

## Three distinct discovery problems

### 1. West finds a workspace and extension commands

West searches from its working directory for `.west`; `ZEPHYR_BASE` provides a
fallback when the current directory is outside a workspace. Passing an
application path to `west build` is not equivalent to changing west's workspace.

`zephyr.base` config selects the base west supplies while running. The default
`zephyr.base-prefer=env` gives an inherited environment priority over that
configuration; `configfile` can change this. Therefore a wrapper's environment
injection can conflict with the workspace's intended base under normal defaults.
An explicit config override can change the outcome; the failure is not universal
for every possible west configuration.

Evidence: `zephyr/doc/develop/west/basics.rst:59-64` and
`zephyr/doc/develop/west/config.rst:252-263`.

### 2. CMake discovers Zephyr source/build-system packages

There are two stages:

1. CMake must locate `ZephyrConfig.cmake`, through explicit `Zephyr_DIR`, a
   prefix/root, application-provided `HINTS`, registry entries, or other normal
   CMake search paths.
2. Once reached, Zephyr's package code chooses the source tree. A defined CMake
   `ZEPHYR_BASE` wins; otherwise an environment base wins; otherwise application
   location, package candidates, and preferences determine selection.

This common application declaration makes an environment base a discovery hint:

```cmake
find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
```

Plain `find_package(Zephyr)` needs another way to locate the initial package.
Merely passing `-DZEPHYR_BASE=...` does not provide that generic CMake discovery
path. Conversely, a package reached through a registry or explicit prefix may
then redirect to the application's local Zephyr tree. Location matching inside
Zephyr's package is filesystem-based, not a lookup of the west manifest.

For explicit direct-CMake selection, the following pair distinguishes package
discovery from source selection:

```text
-DZephyr_DIR=<zephyr>/share/zephyr-package/cmake
-DZEPHYR_BASE=<zephyr>
```

An explicit prefix is another no-export option. None of these methods creates
west workspace metadata or acquires modules. Existing CMake caches retain the
previous source selection; changing an environment variable does not reliably
retarget a build directory. Use a fresh build directory or deliberately make
the old one pristine when changing source trees.

The installed package guide says export is required in its registry-based
workflow. That is not a universal requirement: explicit package paths work,
as both source inspection and the isolated probes below demonstrate. Also,
`HINTS` is not higher priority than every CMake cache/root search input.

Evidence: `zephyr/share/zephyr-package/cmake/ZephyrConfig.cmake:28-32,85-159`,
`zephyr_package_search.cmake:28-38,51-125`, and
`zephyr/doc/build/zephyr_cmake_package.rst:20-22,79-163`.

### 3. CMake discovers the compiler SDK

`find_package(Zephyr-sdk ...)`, `ZEPHYR_SDK_INSTALL_DIR`, and
`ZEPHYR_TOOLCHAIN_VARIANT` concern the compiler/host-tool bundle. They do not
select an NCS source checkout. A suitable compiler may be shared between several
source workspaces, subject to SDK compatibility and Python requirement checks.

Our west backend already sets compiler variables through its Nix SDK setup hook.
zephyr-nix's SDK hook sets `ZEPHYR_SDK_INSTALL_DIR`, without setting `ZEPHYR_BASE`.
Preserve that separation rather than treating removal of `ZEPHYR_BASE` as removal
of the compiler environment.

Evidence: `zephyr/cmake/modules/FindZephyr-sdk.cmake:18-26,43-83`,
`nix/backends/west/zephyr-sdk.nix:132-140`, and zephyr-nix `sdk.nix`.

## Export and sysbuild caveats

The exact command is **`west zephyr-export`**, not `west export`.
`ZephyrExport.do_run()` derives the exported package from the loaded extension's
own source location and exports Zephyr and ZephyrUnittest. On Linux it writes
persistent references under `~/.cmake/packages/`. It does not install a compiler,
choose an SDK for a particular application, or export a separate Sysbuild package
in the inspected implementation. Do not automatically mutate the global registry
on shell entry. An explicit export workflow can remain available.

NCS v3.3.0 enables sysbuild by default in its west build extension, not only for
repository applications. Direct CMake does not implicitly select sysbuild.
`Build._run_cmake()` chooses `share/sysbuild` relative to the loaded extension and
passes the application through `APP_DIR`. The outer sysbuild entry sets a local
`Sysbuild_DIR`. Therefore extension origin and source selection must agree;
the single-image application's location rules are not sufficient to reason
about the outer sysbuild project. Verify both single-image and sysbuild paths.

Module discovery adds another consequence: Zephyr's CMake west/module handling
runs relative to the selected `ZEPHYR_BASE`. A wrong base can select wrong modules,
not merely wrong headers.

Evidence: `zephyr/scripts/west_commands/export.py:41-56`,
`zephyr/share/zephyr-package/cmake/zephyr_export.cmake:11-18`,
`zephyr/scripts/west_commands/build.py:24-25,630-692`,
`zephyr/share/sysbuild/CMakeLists.txt:8-31`, and
`zephyr/cmake/modules/west.cmake:83-89`.

## Current nix-nrf-dev coverage and gaps

| Area | Verified implementation | Consequence |
| --- | --- | --- |
| Public shell API | `nix/backends/default.nix:98-130` accepts backend/release/bundle options, no source-workspace selector | Backend selects provisioning/tools and implicitly managed sources |
| nrfutil wrapper | `nix/backends/nrfutil/shell.nix:80-111` requires managed SDK plus toolchain readiness, then exports that SDK's base | A project-owned checkout cannot independently supply sources without managed SDK readiness |
| nrfutil shell hook | Same file `:159-174` derives base only if inherited base is empty | A nested shell can retain a stale base while the west child injects another |
| west wrapper | `nix/backends/west/shell.nix:78-119` fixes source and venv at `$HOME/ncs/<version>` | A different project workspace is not a first-class selection |
| west shell hook | Same file `:156-180` exports the managed base when ready | It is not topology-sensitive |
| west bootstrap CLI | `bin/backends/west/nix-nrf-west-bootstrap:78-90,264-329,415-449` accepts `--workspace`, checks conventional `nrf`/`zephyr` layout, and preserves existing manifests | Root override exists at CLI level, but wrappers do not propagate it; this is not complete shell support |
| Existing real-build harnesses | `tests/clean-room/run.sh:585-589` and `tests/west-backend/run.sh:247-251` build repository blinky via sysbuild | Repository build paths already exist; this research did not rerun those expensive gates |
| Freestanding fixture | `tests/firmware/debug-fixture/` and PB-004 build evidence | Independent application path is already exercised against managed NCS |

The west bootstrap's structural checks do not themselves establish that source
revisions match `ncsVersion`. Existing-manifest preservation is useful, but a
custom manifest, relocated projects, extra modules, forks, and corresponding
Python dependencies need an explicit support contract.

Removing the parent-shell export alone is not a fix: both west wrappers still
inject the managed base in the child. Work also reaches bootstrap readiness,
doctor diagnostics, initializer scope, and tests that assume the managed base.
Keep Nordic's loader/Python/Git environment scoped to child processes.

## zephyr-nix findings

Inspected the small upstream tree at the pinned revision above:

- [README.md](https://github.com/nix-community/zephyr-nix/blob/5ef0903c5fcdbbce55af2732fad1011e90b6ff47/README.md)
  composes an SDK, Python environment, host tools, CMake, and Ninja in `mkShell`.
  It does not set application location or `ZEPHYR_BASE` in that example.
- [sdk.nix](https://github.com/nix-community/zephyr-nix/blob/5ef0903c5fcdbbce55af2732fad1011e90b6ff47/sdk.nix)
  packages compiler bundles and adds a `ZEPHYR_SDK_INSTALL_DIR` setup hook.
- [python.nix](https://github.com/nix-community/zephyr-nix/blob/5ef0903c5fcdbbce55af2732fad1011e90b6ff47/python.nix)
  reads `zephyr-src/scripts/requirements.txt`, adds west and optional packages,
  and warns about invalid Python version constraints. It does not automatically
  resolve all Nordic or project-specific requirements.
- [flake.nix](https://github.com/nix-community/zephyr-nix/blob/5ef0903c5fcdbbce55af2732fad1011e90b6ff47/flake.nix)
  provides packages, an overlay, and `lib.mkZephyr { pkgs; zephyr-src; }`.
  The source input determines requirements; it is not an automatic source checkout
  selector for application builds. The default source input is upstream v4.3.0.
- [default.nix](https://github.com/nix-community/zephyr-nix/blob/5ef0903c5fcdbbce55af2732fad1011e90b6ff47/default.nix)
  selects versioned SDKs and host tools. Its OpenOCD pin is not our Nordic-qualified
  OpenOCD, so adopting its entire tool set would not preserve our hardware contract.
- Its CI builds packages and compares classic/flake derivations. That is not an
  application-topology build matrix. README points to west2nix for Nix builds of
  west projects; that separate project's implementation was not investigated here.

Recommendation: borrow **toolchain/source separation** and composability. Do not
add zephyr-nix as a dependency merely to support application locations. It does
not provide the missing project-workspace policy, NCS requirements qualification,
or our scoped Nordic toolchain behavior.

## Isolated discovery experiment

Executed CMake 4.1.6 against copied, unmodified NCS v3.3.0 package scripts and
the real `version` component in two synthetic source layouts. The probes used
`find_package(Zephyr REQUIRED COMPONENTS version)`, no compiler languages, an
isolated HOME, and disabled user/system package registries. They did not create
west workspaces or build firmware.

All **11** expected outcomes passed:

| Probe | Result |
| --- | --- |
| Application inside source A's Zephyr; initial package prefix B | Selected A |
| Workspace application beside source A; initial package prefix B | Selected A |
| Application under source A's `nrf`; initial package prefix B | Selected A |
| Freestanding application; explicit prefix B | Selected B |
| Repository application in A; environment base B | Selected B |
| Workspace application in A; environment base B | Selected B |
| Explicit `Zephyr_DIR` plus `ZEPHYR_BASE`, no registry | Selected intended source |
| Only CMake `-DZEPHYR_BASE`, no discovery path | Failed to find package |
| Workspace location alone, no discovery path | Failed to find package |
| First configure selects A | Cached A |
| Reconfigure same build with environment B | Still selected cached A |

Session-only experiment script: `/tmp/opencode/application-discovery-probe.py`.
Detailed commands/output: `/tmp/opencode/application-discovery-z0z1idks/results.json`.
Temporary paths are not durable repository artifacts. The outcomes above are
recorded here; the script is not a new supported command or acceptance suite.

These are package-discovery proofs only. They do not qualify either nix-nrf-dev
wrapper, module composition, custom workspace creation, compiler compatibility,
or sysbuild across all topologies.

## Recommended direction for later feature design

Treat these as independent axes:

1. **Toolchain provider:** existing nrfutil or west/Nix backend.
2. **Source ownership:** managed SDK checkout or an explicitly selected existing
   project workspace. A freestanding application can also use a custom existing
   workspace as its source provider.
3. **Application topology:** repository, workspace, or freestanding, with examples
   and acceptance tests for each rather than necessarily three runtime branches.

Prefer a source/workspace selection contract over three disconnected application
backends. Repository and workspace applications normally share the same source
selection logic. A topology option could validate placement or guide initialization,
but cannot by itself identify the right workspace.

For project-owned sources, let the project manifest/checkouts own revisions,
forks, and extra modules. Let Nix or sdk-manager own the selected compatible
toolchain. Do not implicitly install another managed source tree, rewrite an
existing manifest, or run `west update` as part of entering the shell or checking
toolchain readiness. Resolve the actual Zephyr project path rather than assuming
every workspace uses a literal `zephyr/` directory.

For freestanding managed-source builds, retain explicit source selection and
document environment-based discovery. For workspace/repository builds, avoid a
foreign parent-shell base; either let west supply the correct workspace base or
pass a validated matching base only in the scoped build process. Plain direct
CMake needs an explicit package path/prefix, preset, or deliberate registry export.

Reject or clearly diagnose conflicting inherited bases, source/toolchain release
mismatches, wrong extension origins, and stale build caches. Diagnostics should
show toolchain provider, workspace/manifest, resolved Zephyr path, and source
identity separately. A fork at an arbitrary SHA cannot be validated by treating
an NCS VERSION file as a complete dependency lock.

### Choices still requiring feature refinement

- Exact public source/workspace option names and default behavior. Keeping current
  managed behavior initially avoids a surprise break for existing consumers.
- Whether an unset parent `ZEPHYR_BASE` becomes the workspace-mode contract, or a
  matching inherited value is accepted. Conflicting values must not silently win.
- Compatibility validation for manifest release pins, forks, dirty trees, and
  explicit toolchain bundle selections. Do not silently select a toolchain from
  an untrusted or ambiguous manifest string.
- Scope of direct CMake support with nrfutil: plain outer-shell CMake does not
  load Nordic's scoped environment today. A scoped execution interface or clear
  west-first support boundary is needed, not a global environment leak.
- Whether initialization only writes Nix/direnv configuration into an existing
  workspace, or additionally offers explicit project-manifest scaffolding.
  Manifest acquisition/update is a separate approved operation.

### Smallest meaningful acceptance matrix

Prove the intended source and modules at the **public shell/build boundary**, not
only wrapper argv or copied defaults:

- For each backend, fresh single-image and sysbuild builds of a Zephyr repository
  sample, an NCS `nrf` repository sample, a workspace application, and a freestanding
  application. Record selected source, module paths, compiler, and artifacts.
- Use two distinct source workspaces plus a conflicting inherited `ZEPHYR_BASE`;
  demonstrate intended selection or explicit refusal. Include calls from outside
  the workspace and a reused build cache.
- A project manifest importing NCS plus an extra module/custom board must build
  from those checkouts without needing a separate managed SDK source installation.
  Preserve manifest content and source revisions across shell entry/readiness.
- A nonstandard Zephyr project path, a fork, missing modules, incomplete workspace,
  and incompatible toolchain must yield defined outcomes instead of fallback.
- Direct CMake tests, if included in scope, cover plain `find_package(Zephyr)` with
  explicit package discovery and the standard environment-hinted declaration.
- Shell entry and normal builds do not write the global CMake registry. Explicit
  export, if supported, is tested under isolated HOME and selects the intended tree.
- Parent-shell loader/Python/Git isolation and child argument/exit propagation
  remain intact. Source provisioning, toolchain provisioning, and application
  builds remain distinct operations with clear ownership and approval boundaries.

Use hardware-free discovery probes for fast regression coverage, then approved
real builds with already installed tools/source fixtures. No flashing is needed
to establish application-type support. Broad platform expansion, a NCS baseline
upgrade, pure Nix firmware derivations, and receiver migration are out of scope.
