# Optional NCS documentation commands: research and implementation handoff

Related item: **PB-034 — Add opt-in backend-independent NCS documentation commands**.

This is historical prototype research, not documentation of an implemented
`nix-nrf docs` feature or an accepted ADR. Read `docs/product/README.md` before
changing the item. The [approved build contract](ncs-documentation-contract.md)
supersedes proposed interfaces and policies below. Use the backlog CLI for
current status; the prototype remains unintegrated and not full-SDK-qualified.

## Goal and confirmed product direction

The user wants to generate local SDK documentation alongside development of an
nRF project. The integration must be **optional, backend-independent, and enabled
by an explicit consumer flake feature flag**. Omission/false must preserve the
current consumer behavior and avoid introducing documentation-only dependencies.

Initially qualify NCS **v3.4.1**. Generate all public upstream HTML documentation,
with **nRF, Zephyr, and MCUboot as hard requirements**. This is SDK documentation,
not an automatic generator for arbitrary application-owned documentation.

Suggested interface, not yet a committed contract:

```nix
nix-nrf-dev.lib.${system}.mkNrfShell {
  ncsVersion = "v3.4.1";
  backend = "west"; # Documentation is not tied to this backend.
  withDocumentation = true; # Proposed new option; not implemented.
}
```

```bash
nix-nrf docs build
nix-nrf docs build --hardware-features
nix-nrf docs serve
```

These commands do **not** exist on this branch. The standalone prototype uses
different command names and explicit workspace arguments.

## Provenance and preserved artifacts

- `nix-nrf-dev` baseline: `94f7371646f56d5fb46bf32406cdef817f52b85b`.
- Examined `sdk-nrf`: tag `v3.4.1`, commit
  `b20f8619ba9a5530f8c34b0a130d829947cfe55d`.
- Matching Zephyr source reference: `nrfconnect/sdk-zephyr`, `ncs-v3.4.1`.
- SDK-local source was examined at `/tmp/sdk-nrf`; that temporary location is
  historical evidence, **not a dependency of the saved prototype**.
- Installed NCS v3.3.0 was not used as the authority for v3.4.1 behavior.

Saved prototype:

```text
docs/product/research/ncs-documentation-prototype/flake.nix
docs/product/research/ncs-documentation-prototype/flake.lock
```

The flake preserves the standalone tools, apps, checks, exact wheel hashes, and
source selection developed during research. Its output derivation identities
match the original prototype; the regenerated lock file is byte-identical to the
original (SHA-256 `5470602ba565de069725756e4fbbd58843f64ebd9645ba9950cac903f412c964`).
The saved Nix expression was subsequently normalized with the repository's
formatter and equivalent `inherit` syntax before publication. Dependency pins
and embedded commands are unchanged. Native prototype checks and both-system
evaluation were rechecked successfully.
It is intentionally not imported by the root flake or wired into consumer shells.

Its `nix-nrf-dev` input points to the **baseline GitHub commit**, not this branch.
That made the standalone prototype portable. Integration must remove this
self-project input and reuse local builders; otherwise it would silently keep
using old project code and duplicate contributor inputs in the lock graph.

## SDK documentation build findings

### A west workspace is required

The root SDK repository does not acquire its dependencies through root Git
submodules. `west.yml` selects Zephyr and imports its manifest, alongside MCUboot,
nrfxlib, Matter, TF-M, Nordic HAL, Wi-Fi, crypto modules, and other projects.
Some selected projects have their own submodules, which `west update` handles.

Documentation utilities instantiate `west.manifest.Manifest` and resolve source
directories through its project paths. Rendering also needs code/sample/library
sources outside `nrf/doc` and module metadata for Kconfig/devicetree processing.
Cloning only three documentation repositories is not a qualified substitute for
the matching SDK workspace.

Evidence at the SDK tag:

- [`west.yml:66–114`](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/west.yml#L66):
  matched Zephyr reference and imported-project allowlist.
- [`west.yml:129–174`](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/west.yml#L129):
  MCUboot, crypto, nrfxlib, TF-M, and Matter selections/submodules.
- [`doc/_utils/utils.py:12–63`](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/doc/_utils/utils.py#L12):
  manifest loading, supported docsets, and project-directory resolution.

### Use the combined upstream build graph

At this tag, `nrf/doc/CMakeLists.txt` defines public sets `nrf`, `zephyr`,
`mcuboot`, `nrfxlib`, `tfm`, `matter`, `kconfig`, plus Doxygen-only `nrfx` and
`wifi`. `build-all` copies the landing page/version list and merges search indexes.
`nrf-all` pulls other sets in dependency order; isolated `nrf` assumes required
inventories already exist. Do not replace this with three independent Sphinx calls.

`doc-internal` is disabled by the manifest's default group filter; internal
documentation is conditional and outside the public scope. Not every directory
under `doc/` is a documentation set. Do not transplant targets from newer `main`:
the initial pre-checkout inspection differed from the actual v3.4.1 graph.

Evidence:

- [`doc/CMakeLists.txt:283–439`](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/doc/CMakeLists.txt#L283).
- [`doc/nrf/dev_model_and_contributions/documentation/build.rst`](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/doc/nrf/dev_model_and_contributions/documentation/build.rst).
- [Release CI configuration, lines 102–115](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/.github/workflows/docbuild.yml#L102).

### Python/tool constraints need a release profile

Use Python 3.12, matching release CI. Tagged `doc/requirements.txt` constrains
Sphinx to `>=8.1,<8.2`, snowballstemmer to `<3`, and Nordic theme to `<2.1`.
The initial host Nixpkgs had Sphinx 9.1 and snowballstemmer 3.x and lacked the
Nordic theme/m2r2 attributes. A requirements importer does not resolve arbitrary
PyPI versions or supply missing packages.

The prototype pins Python 3.12, Sphinx 8.1.3, docutils 0.21.2,
snowballstemmer 2.2.0, Nordic theme 2.0.5, and m2r2 0.3.4 with its private
mistune 0.8.4 dependency. It uses the project baseline Nixpkgs commit
`643809054d65fdd466a63e3155b8c498cb483c04` and explicit hashed wheels where needed.
All 27 direct tagged documentation requirements were checked successfully.

Global Python/Sphinx scope overrides proved problematic: unrelated Nixpkgs
documentation/test closures started rebuilding against old Sphinx, leading to
incompatible dependencies and large test trees. The final prototype constructs a
local documentation package set over normal Python packages and uses released
extension wheels with explicit runtime dependencies. It similarly avoids Azure
tracing/test extras that pulled an unrelated failing SciPy test closure.
Do not interpret this as permission to disable project acceptance tests.

Additional imports come from Zephyr base scripts/autodoc and NCS helpers, not just
`doc/requirements.txt`. In particular, include `requests`, `jsonschema`, and
`junitparser` for the Twister hardware path. Zephyr's vendored `kconfiglib` and
devicetree Python sources are loaded from the matched workspace. Do not replace
them indiscriminately with unrelated PyPI packages.

Native tools include CMake, Ninja, Git, Doxygen (upstream minimum 1.12), Graphviz,
Mscgen 0.20, and PlantUML with its Java runtime. The prototype's realized Doxygen
and doxmlparser are both 1.17.0; **full-SDK rendering with those versions has not
been qualified**. Check warning/API compatibility during real acceptance rather
than assuming the upstream minimum validates every newer release.

Evidence:

- [`doc/requirements.txt`](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/doc/requirements.txt).
- [`doc/CMakeLists.txt:15–53`](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/doc/CMakeLists.txt#L15).
- [Zephyr base requirements](https://github.com/nrfconnect/sdk-zephyr/blob/ncs-v3.4.1/scripts/requirements-base.txt).
- [`scripts/requirements-build-test.txt`](https://github.com/nrfconnect/sdk-zephyr/blob/ncs-v3.4.1/scripts/requirements-build-test.txt)
  declares `junitparser>=3.0.0`.

### Hardware tables are not compiler-free

An important corrected assumption: the top-level documentation CMake project
declares `LANGUAGES NONE`, but **`HW_FEATURES=ON` invokes Twister firmware CMake
configuration**. It is not just rendering YAML and does not skip toolchain
discovery because `--cmake-only` is used.

`doc/_scripts/gen_boards_catalog.py:229–247` runs the selected Python's Twister
against `samples/hello_world/`, retaining `edt.pickle` and runner metadata.
Twister verifies host tools and then configures target toolchain/compiler/linker
definitions. DTS processing needs a C preprocessor. External `dtc` is optional
for extra warnings; `gperf` is optional on this CMake-only path.

The helper's `minimal_env` at lines 249–254 forwards only `PATH`, `ZEPHYR_BASE`,
`HOME`, and `PYTHONPATH`. It discards `ZEPHYR_SDK_INSTALL_DIR`,
`ZEPHYR_TOOLCHAIN_VARIANT`, and `CMAKE_PREFIX_PATH`. Exporting SDK variables in
the outer shell alone therefore does not fix child discovery.

The prototype's `build-full` uses the existing
`packages.<system>.west-zephyr-sdk-v3_4_1` output. It writes a build-local `cmake`
wrapper, prepends it to PATH, restores the selected SDK variables, and executes
the exact Nix CMake. This avoids changing SDK sources or the global CMake registry.
**The wrapper strategy is source-grounded but not proven by real hardware-table
generation.** Preserve that distinction during integration.

The helper can warn that features are incomplete after Twister fails. File
existence is not acceptance: assert populated tables for representative Nordic
targets. Prototype `--jobs` caps Sphinx workers and serializes outer targets;
it does **not** prove a bound on child Twister parallelism.

Tagged evidence:

- [Board catalog helper](https://github.com/nrfconnect/sdk-zephyr/blob/ncs-v3.4.1/doc/_scripts/gen_boards_catalog.py#L229).
- [Twister environment/toolchain discovery](https://github.com/nrfconnect/sdk-zephyr/blob/ncs-v3.4.1/scripts/pylib/twister/twisterlib/environment.py#L1109).
- [Toolchain verification script](https://github.com/nrfconnect/sdk-zephyr/blob/ncs-v3.4.1/cmake/verify-toolchain.cmake).
- [DTS CMake processing](https://github.com/nrfconnect/sdk-zephyr/blob/ncs-v3.4.1/cmake/modules/dts.cmake).

### Network and trust remain explicit

TF-M fetches remote intersphinx inventories during normal HTML rendering. This
happens even when Kconfig diff is off. The prototype build app runs outside the
Nix derivation sandbox; it is not a hermetic `packages.docs` build. Do not solve
this by globally disabling the Nix sandbox.

Kconfig diff downloads the previous release's snapshot. The loader imports
bundled Python and unpickles data; this is executable trusted input. The inspected
fetch path has no checksum pin and no explicit requests timeout. Keep it opt-in
with an accurate warning. A future offline/sandboxed mode needs pinned inventories
and snapshot inputs plus a deliberately reviewed loader policy.

Evidence:

- [`doc/tfm/conf.py:80–86`](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/doc/tfm/conf.py#L80).
- [`doc/_extensions/kconfigdiff/kconfig_utils.py:371–404`](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/doc/_extensions/kconfigdiff/kconfig_utils.py#L371).
- [`doc/_extensions/kconfigdiff/pickler.py`](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/doc/_extensions/kconfigdiff/pickler.py).

## Integration seams in nix-nrf-dev

Read current `AGENTS.md`, `CONTRIBUTING.md`, and
`docs/development/architecture.md`. Verified existing paths:

| Component | Role in integration |
| --- | --- |
| `nix/backends/default.nix` | Public `mkNrfShell` options, validation, explicit backend dispatch. Proposed flag belongs at the shared consumer boundary. |
| `nix/commands/default.nix` | Fixed command dispatcher and exact store-path delegation. Add a conditionally supplied documentation command, not ambient plugin discovery. |
| `nix/backends/source.nix`, `bin/commands/nix-nrf-source` | Read-only manifest-based existing-workspace resolution. Reuse it instead of hardcoded `nrf/` and `zephyr/`. |
| `nix/flake/components.nix` | Shared component construction and release/SDK builder wiring. |
| `nix/backends/west/versions.nix`, `zephyr-sdk.nix` | Existing v3.4.1 SDK package metadata and builder; documentation is not required to select the west firmware backend to reuse that package. |
| `nix/backends/nrfutil/shell.nix`, `nix/backends/west/shell.nix` | Wire a shared docs command into each enabled facade without leaking docs Python into the parent or firmware subprocess. |
| `nix/flake/checks/`, `tests/unit/` | Deterministic command/closure/environment tests; actual SDK qualification remains opt-in. |

Suggested future ownership, **not created in this handoff**:
`nix/docs/` for release profiles/tool environments, `nix/commands/docs.nix` for
packaging, and `bin/commands/nix-nrf-docs` for public CLI behavior.

The flag must be evaluated before constructing/referencing documentation commands
in disabled consumer runtime closures. Do not merely hide help text while keeping
Java, Doxygen, or Sphinx packages in every shell. Compare the disabled closure to
the previous baseline; some native tools already belong to firmware workflows.

Existing-source mode selects sources independently of firmware backend. It must
not acquire/update repositories, repair a venv, or copy an SDK into the Nix store.
Managed-source discovery also needs a read-only path: using firmware readiness as
a docs prerequisite could wrongly require unrelated firmware Python packages.
Resolve this explicitly before implementation.

## Prototype usage and limitations

Run from `docs/product/research/ncs-documentation-prototype/`:

```bash
nix flake check path:.
nix flake check path:. --all-systems --no-build
nix run path:.#build-docs -- --help
nix run path:.#build-full -- --help
```

The following commands are **not part of completed validation**. Preparation
downloads SDK repositories/submodules, and actual builds can be resource-heavy.
They require explicit approval under the repository's bootstrap rules:

```bash
nix run path:.#prepare -- /absolute/path/to/new-ncs-v3.4.1-workspace
nix run path:.#build-full -- /absolute/path/to/new-ncs-v3.4.1-workspace
nix run path:.#serve-docs -- /absolute/path/to/new-ncs-v3.4.1-workspace/doc-build-v3.4.1/html
```

The standalone prototype deliberately expects stock workspace paths and exact
`sdk-nrf` HEAD. It does not prove that every module checkout matches the manifest,
does not refuse all local modifications, and checks only a few required HTML
entry files after build. Do not preserve these shortcuts as integrated acceptance.
Decide local-edit/version policy and strengthen output verification.

Do not adopt its `prepare` app as a second project bootstrap mechanism without a
separate product decision. The requested feature should work with sources already
selected by the consumer's development environment.

## Evidence ledger

Passed during prototype work and rechecked from the saved prototype:

- Native x86_64 Linux `nix flake check path:.`: packaged scripts, dependency
  metadata validation, representative Nordic-theme Markdown rendering, invalid
  CLI inputs, refusal of an existing prepare directory, and actual localhost
  HTTP serving/termination.
- Both supported system outputs evaluated with `--all-systems --no-build` in
  the original prototype. ARM64 execution was **not** tested.
- Every one of the 27 tagged `doc/requirements.txt` entries satisfied by the
  realized Python environment; extra Twister `junitparser` import tested.
- `build-full` package built; `--help` and no-argument refusal exercised.
- Original two-file portability tested outside the SDK repository.

**Not performed:** SDK preparation, complete `build-all`, linked/searchable SDK
HTML verification, full hardware tables/Twister SDK forwarding, Kconfig diff,
documentation behavior under either integrated firmware backend, or ARM64 builds.
Root `nix-nrf-dev` feature implementation and its full test gate are not done.
No flashing, probes, or other hardware control is needed for this feature.

## Refinement and implementation sequence

1. Refine PB-034: settle flag and CLI shape, default hardware-table mode,
   standalone facade exposure, local-edit/version policy, unsupported-release
   behavior, read-only managed-source discovery, and Twister resource policy.
   Do not mark Ready just because this research is detailed.
2. Establish disabled-flag public behavior and baseline closure before adding
   packages. Extract a v3.4.1 docs profile from the prototype without globally
   overriding the firmware Python package set.
3. Add shared, conditionally wired dispatch and scoped tooling/source discovery;
   exercise enable/disable and isolation through public shell/CLI boundaries.
4. Qualify actual all-public HTML output with prepared matching SDK sources and
   representative cross-doc links/search. Keep inventory/network failures visible.
5. Qualify explicit hardware tables with real Twister metadata, SDK forwarding,
   and worker limits. Verify error paths rather than silently accepting warnings.
6. Update current public guides/architecture and run the relevant executable
   gates from `CONTRIBUTING.md`. Record host/backend and real-SDK limits in PB-034.

The smallest release acceptance is a **real `nix-nrf docs build` invocation**
through the opted-in public consumer interface, producing the required complete
HTML sets while leaving source inputs and firmware environment intact. Tool
imports, shell constructor wiring, mocked helper calls, or empty HTML placeholders
are not substitutes.
