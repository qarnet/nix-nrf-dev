# PB-034 approved documentation build contract

The product owner approved this direction during PB-034 refinement. This is a
specification for future implementation, not a guide to commands available today.
The backlog item owns lifecycle and acceptance evidence. This contract supersedes
earlier interface and policy proposals in the preserved research notes.

## Consumer configuration

Add a `documentation` attrset to `mkNrfShell`. Omission is equivalent to
`documentation.enable = false`. All build settings live in this attrset. The
initial CLI exposes `nix-nrf docs build` and help, without duplicate settings
flags or ambient environment overrides. No standalone facade or serve command.

```nix
documentation = {
  enable = true;
  docsets = [ "all" ];
  jobs = 2;
  output = "build/ncs-docs";
  allowLocalChanges = false;
  hardwareFeatures = {
    enable = false;
    sdkPackage = null;
  };
  kconfigDiff.enable = false;
};
```

The example shows defaults except for enabling the feature:

| Field | Contract |
| --- | --- |
| `enable` | Boolean, default false. Disabled consumer CLI, runtime closure, and environment behavior remain unchanged. |
| `docsets` | Nonempty list of unique names. Default `[ "all" ]`; `all` must be the only entry. Explicit names are `nrf`, `zephyr`, `mcuboot`, `nrfxlib`, `tfm`, `matter`, `kconfig`, `nrfx`, and `wifi`. |
| `jobs` | Positive integer, default 2. Bounds Sphinx workers and child Twister workers. Outer docsets build serially. This is not a RAM or elapsed-time guarantee. |
| `output` | Nonempty path string, default `build/ncs-docs`. Relative paths anchor at shell-entry CWD. Reject Nix path literals, store destinations, and destinations inside selected SDK Git checkouts. |
| `allowLocalChanges` | Boolean, default false. Permits dirty documentation/code inputs on the supported release baseline, with recorded provenance. Does not permit version mismatches, changed manifest project/revision selection, missing inputs, or arbitrary committed forks. |
| `hardwareFeatures.enable` | Boolean, default false. Adds Nordic hardware feature metadata, not physical hardware qualification. |
| `hardwareFeatures.sdkPackage` | Default null. Enabled hardware metadata requires an explicitly supplied native-host-compatible Zephyr SDK derivation. Validate discovery and compiler prerequisites at build time. No ambient compiler selection or fallback. |
| `kconfigDiff.enable` | Boolean, default false. Explicit consent to the previous-release download and executable Python/pickle trust described below. |

Reject unknown keys, invalid types, unknown/duplicate/empty docset selections,
and missing enabled-hardware SDK selection during evaluation. Actual mutable
source/output validation happens at build time. Shell entry must not build docs,
provision sources, or install mutable Python environments.

Hardware-enabled consumers can explicitly select the existing SDK:

```nix
documentation.hardwareFeatures = {
  enable = true;
  sdkPackage = nix-nrf-dev.packages.${system}.west-zephyr-sdk-v3_4_1;
};
```

## Selection and output

Selection means requested upstream build targets plus required supporting
docsets. Supporting docsets may appear in output, navigation, and search.
Do not delete them to imitate a minimal publication subset or promise
proportional build-time savings. Default all uses the combined public graph,
including Doxygen API content, full devicetree binding reference, landing
content, navigation, and merged search.

Selected subsets must retain working representative local cross-doc links and
search for their actual outputs. Generate navigation/search for available sets,
not links to unbuilt sets. Configure/module-processing prerequisites may exceed
the requested HTML sets.

The output root is tool-owned and project-local by default. Use fresh build
generations and expose completed HTML at `<output>/html` only after verification.
Reject unrelated occupied roots and concurrent writers. Repeated builds must
not mix releases/settings or retain stale docsets/search. Do not recursively
delete user directories. Failed builds must not publish incomplete generations
as successful output. Record source identities/local changes, tools, selection,
and settings alongside each generation.

Serving is the user's choice. Static HTML does not need the build environment.
A user with Python available can run:

```bash
python3 -m http.server 8000 --bind 127.0.0.1 --directory build/ncs-docs/html
```

## Sources, releases, and backends

Initially support NCS v3.4.1 only. Enabled unprofiled releases fail evaluation
with the supported list. Disabled docs do not restrict firmware release support.
Use the shell's `ncsVersion`, without runtime override.

Documentation compatibility records are independent of firmware backend
metadata. Initially use one pinned shared environment qualified for v3.4.1.
Validate actual applicable workspace requirements without installing packages.
Additional releases can reuse that environment after requirements and rendering
qualification. Conflicting requirements need another environment family, not
duplication of every pin per release.

PB-031 owns future reviewed per-release tool indexing, requirement/native-tool
provenance, environment-family mapping, adapters, and qualification. PB-032 owns
later manual candidate-update automation. Neither blocks initial bounded PB-034.
Requirements parsing is not resolution, artifact locking, or rendering proof.

Read-only source discovery must not depend on firmware Python/toolchain readiness:

- Existing workspace uses its shell-anchored root and manifest-resolved paths.
- Managed west discovers its existing version-local workspace.
- Managed nrfutil reads installed SDK inventory without loading toolchain env.

Missing sources fail with preparation guidance. Never acquire/update sources,
repair Python, register global CMake packages, or copy selected SDK trees into
the store. Ordinary docs need no firmware compiler; enabled hardware metadata
needs the explicitly selected SDK.

Support native amd64 nrfutil and native amd64/ARM64 west under existing policy,
with no backend fallback. Qualify stock and application-owned imported workspace
layouts. Adapt upstream path assumptions in controlled build-local tooling,
without checkout changes. Unsupported layouts and modified manifest selection
fail clearly rather than using another workspace. Local-edit permission cannot
weaken release/input checks.

## Enrichments and public-only boundary

Hardware tables derive board features from configured devicetree nodes,
bindings, compatibles, and runner metadata. Twister runs hello-world CMake
configuration; it does not flash or test a board. Initial scope follows the
Nordic vendor filter. Full binding reference remains enabled independently.

A narrowly release-pinned build-local adapter must pass child worker limits,
restore compiler discovery, retain reports, and propagate Twister failure.
Account for expected selected targets and documented legitimate skips; fail
missing/failed required metadata. Check representative populated Nordic tables.
The prototype CMake wrapper alone does not prove worker bounds or completeness.

Kconfig diff compares symbols with a previous release. Upstream snapshot loader
imports Python and unpickles downloaded data without an inspected checksum pin.
Opt-in is a trust decision. Document consent beside the setting and in build
diagnostics. Ordinary builds can fetch remote intersphinx inventories even with
diff disabled. No fully offline, hermetic, or byte-reproducible guarantee.

Successful exclusion of a locally present `doc-internal` project is deferred.
Refuse its manifest-resolved path before configure/rendering; never silently
publish private HTML, navigation, or search. Future support can become a separate
item if needed. It requires both CMake and Python inclusion paths, plus
independent module consumers, to agree. No new exclusion item is needed now.

## Verification and limits

Normal CI proves public command/shell behavior, disabled closure equivalence,
configuration validation, discovery without firmware readiness, source/version/
internal-input refusals, output lifecycle, ambient-environment isolation,
dependency validation, representative rendering, and adapter failure handling.
Tests use public boundaries, not only generated launch arguments.

Opt-in prepared-SDK qualification builds all public sets and a dependency-bearing
subset. Check API content, full bindings, landing/navigation, local cross-doc
links, and merged search. Hardware qualification also checks actual worker bounds,
compiler discovery, coverage reports, and table rows. Repeat builds and compare
checkout, firmware Python, and global CMake state before/after. Run native amd64
nrfutil, amd64 west, and ARM64 west; cross-system evaluation is not rendering
evidence.

Writing this contract establishes no acceptance evidence. Full SDK rendering,
hardware generation, relocated-layout adaptation, and ARM64 execution remain
implementation/qualification work. SDK acquisition needs separate approval.
No hardware operations are needed.

Out of scope: serving, standalone facade, private docs, PDF, arbitrary SDK
releases/forks, automatic dependency provisioning, a second bootstrap path,
physical hardware qualification, and offline/reproducible publication.
