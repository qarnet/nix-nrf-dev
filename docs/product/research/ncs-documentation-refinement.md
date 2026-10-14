# PB-034 refinement findings

Research date: 2026-10-12. This note preserves refinement findings and proposals.
The [approved build contract](ncs-documentation-contract.md) supersedes earlier
recommendations below. Use the backlog CLI for current status. No implementation
or full SDK build was performed. Preserve the original research and prototype.

## Follow-up decisions and Nix configuration conventions

The product owner selected a `documentation` settings attrset with explicit
`enable`, default false. The add-on remains shell-only and exposes build only.
Serving belongs to the user; generated static HTML does not require the build
environment. Earlier recommendations for a boolean `withDocumentation` and a
serve command are superseded. Source availability, not firmware environment
readiness, is the documentation prerequisite.

The owner requested further discussion before accepting docset selection,
enrichments, jobs, output, and release support. No acceptance text has been
rewritten yet; the item needs those choices and removal of serving acceptance
before Ready.

Research into upstream Nix tooling found no universal flake-versus-CLI rule:

- [treefmt-nix](https://github.com/numtide/treefmt-nix#configuration) puts enabled
  tools, tool packages, formatter options, and project-root policy in Nix and
  exposes a configured wrapper. This is a close match for the proposed add-on.
- [git-hooks.nix](https://github.com/cachix/git-hooks.nix#flakes-support) puts
  enabled hooks and settings in Nix, then provides normal execution commands.
- [Nix build](https://nix.dev/manual/nix/latest/command-ref/new-cli/nix3-build)
  offers invocation-specific output-link flags. This is evidence that runtime
  overrides are conventional too, not a requirement for our mutable output API.
- [Nix develop](https://nix.dev/manual/nix/latest/command-ref/new-cli/nix3-develop)
  supplies a build environment in which normal tools execute. Packaging a tool
  does not make every execution a sandboxed Nix derivation build.
- [Nix cores/jobs](https://nix.dev/manual/nix/2.34/advanced-topics/cores-vs-jobs)
  distinguishes derivation scheduling from per-build parallelism and requires
  builders to honor the suggested core count. These settings do not automatically
  govern a documentation command executed later inside a development shell.

Recommend making the documentation attrset the complete configuration for
PB-034, including jobs and output. The command performs the action and exposes
help, without duplicating each setting as a CLI flag initially. Adding optional
one-off overrides later would also be conventional, but is not necessary.
No hidden environment override layer is proposed.

Use output paths as strings, anchored at shell entry, not Nix path literals.
This keeps writable output outside the store and avoids CWD-dependent changes
after the user enters a project subdirectory. Job count may depend on host
system in the consumer's Nix expression. Changing a setting requires shell
re-entry and changes the configured wrapper, not the pinned documentation tools
unless their package selection changes.

Docset selection can be expressed in Nix, defaulting to all. The unresolved
engineering issue is upstream dependency and publication behavior, not where
the setting lives. Selecting nRF still builds several supporting docsets.
Promise neither proportional build-time savings nor a self-contained subset
until navigation, cross-links, and merged search have been qualified.

Release support should be a documentation-owned compatibility profile, separate
from firmware backend metadata. A profile records pinned tool requirements,
upstream targets/options, adapters, and qualification. More versions can be added;
v3.4.1-only is a current qualification boundary, not a fundamental limitation.
Enabled unknown selections should fail clearly instead of silently using an
unmatched profile. Runtime input validation remains separate from Nix profile
selection, because pure evaluation cannot inspect mutable SDK workspaces.

## Selection and dependency-management follow-up

The product owner accepted docset selection as requested upstream build targets
plus required supporting docsets, defaulting to all. Successful exclusion of a
locally present internal docset may be deferred if integration is too involved.

Source review found two independent internal inclusion paths. CMake assigns
`ZEPHYR_DOC_INTERNAL_MODULE_DIR` after discovery, shadowing an empty cache value:
[`zephyr_module.cmake:138-142`](https://github.com/nrfconnect/sdk-zephyr/blob/ncs-v3.4.1/cmake/modules/zephyr_module.cmake#L138).
Nordic's Python registry adds the internal docset whenever its manifest path
exists, without testing project activity:
[`utils.py:31-43`](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/doc/_utils/utils.py#L31).
That registry feeds navigation and search. Group deactivation or an empty CMake
variable alone is not enough. Successful exclusion requires both paths and
independent module consumers to agree. This is a medium integration task, not a
single flag. Recommend deferring successful internal-present builds and issuing
a preflight unsupported-case error; do not silently include private content.
No separate exclusion item has been created.

Requirements-driven resolution and validation are different operations:

- [Nixpkgs Python environments](https://github.com/NixOS/nixpkgs/blob/643809054d65fdd466a63e3155b8c498cb483c04/doc/languages-frameworks/python.section.md)
  select pinned package derivations; parsing requirements does not resolve missing
  versions or create packages.
- [uv requirements import](https://docs.astral.sh/uv/concepts/projects/dependencies/#importing-dependencies-from-requirements-files)
  can resolve requirements into a project lock.
  [uv2nix](https://pyproject-nix.github.io/uv2nix/usage/getting-started.html)
  consumes the pre-resolved project and lock, rather than resolving arbitrary
  mutable SDK requirements during consumer evaluation.
- Runtime pip/uv resolution would introduce mutable provisioning and potentially
  unpinned artifacts. It is not equivalent to a pinned Nix environment.
- Requirements do not specify the entire native toolchain or upstream build
  adapters. Python dependency compatibility alone does not establish rendering
  compatibility.

Recommend one shared pinned documentation environment initially, qualified for
v3.4.1. Validate actual workspace requirements at runtime without installing
anything. Reuse the same environment for additional releases when constraints
and real builds pass. Maintain small release records mapping to environment
families; do not duplicate every package pin for every release. Add another
environment family only for conflicting requirements or integration needs.

PB-031 owns future maintainer-generated reviewed metadata and constraints;
documentation environment reuse, native tool constraints, release adapters,
and rendering qualification belong in that item. PB-032 can later automate its
candidate checks. PB-034 does not need to wait for the general generator to
implement its initial bounded release support.

Remaining choices are whether to enable hardware metadata and Kconfig diff by
default, compiler selection for enabled hardware metadata, dirty-source policy,
and initial supported-release scope. Proposed jobs/output defaults and exact
settings schema also need final agreement. Serving is out of scope. No code has
been implemented or release build qualified by this research.

## Verified baseline details

Repository HEAD is `94f7371646f56d5fb46bf32406cdef817f52b85b`.
An existing prepared workspace was found at
`/tmp/opencode/pb001-v341-west-home/ncs/v3.4.1`. This temporary path is historical
evidence, not a public prerequisite. Its Nordic and Zephyr repositories were
clean and matched these commits:

- sdk-nrf v3.4.1: `b20f8619ba9a5530f8c34b0a130d829947cfe55d`.
- sdk-zephyr ncs-v3.4.1: `33fa6a7aac6a4401d16a67cb9f27a3483fa02dd6`.

Other modules and submodules were not fully audited. No SDK acquisition,
firmware Python installation, rendering, hardware access, or ARM64 execution
occurred during this refinement.

## Source discovery is separate from firmware readiness

Current `bin/backends/nrfutil/nix-nrf-bootstrap:304-349` checks both sources and
toolchain availability. Its `--check --print-sdk-path` can print a source path
while returning failure for a missing toolchain. West bootstrap calls
`readiness()` before returning a workspace path at
`bin/backends/west/nix-nrf-west-bootstrap:572-613`; this includes firmware Python.
Neither full bootstrap check is the right prerequisite for compiler-free docs.

Recommend backend-specific read-only root discovery followed by one shared
documentation input validator:

- Existing sources: shell-anchored selected workspace, resolved through west.
- Managed west: the configured version's existing `$HOME/ncs/<version>` root.
- Managed nrfutil: installed SDK inventory, without loading a toolchain env.

The nrfutil inventory parser already exists at
`bin/backends/nrfutil/nix-nrf-bootstrap:92-156`. It currently requires a literal
`zephyr/` directory, so reusing it unchanged does not establish arbitrary layout
support. Missing source inputs must fail without acquisition or repair.

## Upstream layout assumptions need qualification

The project resolver discovers Nordic and Zephyr paths from the active manifest
and checks VERSION, but does not verify every project revision or cleanliness:
`bin/commands/nix-nrf-source:44-163`.

Upstream documentation independently loads the Nordic repository's own manifest:
[`doc/_utils/utils.py:14-63`](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/doc/_utils/utils.py#L14).
It does not merely consume the resolver's project-path map. Nordic configuration
also assumes a relative mbedTLS path at
[`doc/nrf/conf.py:23`](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/doc/nrf/conf.py#L23),
and some literal includes contain relative module paths.

Options are to qualify only compatible upstream layouts, adapt path lookup and
includes without changing selected checkouts, or reject incompatible layouts
explicitly. A blanket promise of manifest-layout independence is not yet proven.
Recommend supporting the repository's public source modes while requiring all
documentation inputs, and explicitly testing an application-owned imported
workspace with relocated projects before promising arbitrary relocation.

## Hardware metadata needs a separate contract

The tagged Nordic configuration sets the vendor filter to `['nordic']`:
[`doc/zephyr/conf.py:105-106`](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/doc/zephyr/conf.py#L105).
All-public docsets therefore do not imply all-vendor hardware metadata.

[`gen_boards_catalog.py:222-259`](https://github.com/nrfconnect/sdk-zephyr/blob/ncs-v3.4.1/doc/_scripts/gen_boards_catalog.py#L222)
invokes the selected interpreter and an absolute Twister script path, passes
`--cmake-only`, omits `--jobs`, and forwards only PATH, ZEPHYR_BASE, HOME, and
PYTHONPATH. A PATH wrapper for `twister` cannot intercept that invocation.
SDK variables must reach child CMake by another explicit method.

[`Twister runner:1889-1903`](https://github.com/nrfconnect/sdk-zephyr/blob/ncs-v3.4.1/scripts/pylib/twister/twisterlib/runner.py#L1889)
defaults to `multiprocessing.cpu_count()` without an explicit jobs argument.
Sphinx `--jobs`, outer Ninja limits, and CPU affinity alone do not establish a
child worker bound. The prototype's CMake wrapper addresses SDK discovery only.

The board helper catches child failure and logs a warning, then gathers available
results. Missing EDT records can leave empty metadata. Its temporary report
directory is discarded after gathering at lines 307-311. Merely producing HTML,
or passing Sphinx warning checks, does not prove hardware completeness.

Recommend hardware metadata off by default, explicit `--hardware-features` and
`--zephyr-sdk PATH`, Nordic scope initially, and a narrowly release-pinned
build-local adapter that adds child jobs, retains reports, and propagates failure.
Default two workers is a proposed conservative policy, not a measured capacity
requirement. Do not claim a RAM, disk, or duration budget before measurement.
Acceptance must define expected Twister-selected targets and allowed skips,
check missing/failed records, and verify populated representative Nordic tables.

## Proposed interface and policies

| Decision | Recommendation | Alternative and tradeoff |
| --- | --- | --- |
| Consumer opt-in | Boolean `withDocumentation = false` | A settings attrset offers future knobs but adds validation before a need exists. |
| Public commands | `nix-nrf docs build` and `serve` in enabled shells only | A standalone facade helps shell-free use but needs a second source/version selection contract. Defer it. |
| Build contents | Upstream `build-all`, full DTS bindings, Doxygen, landing/navigation/search | Selected docsets need custom dependency and stale-search policy; defer them. |
| Hardware | Explicit flag, selected SDK, bounded child jobs, Nordic metadata | Always-on adds compiler cost; all vendors expand toolchain and qualification scope. |
| Release support | Initially exact v3.4.1 docs profile; unsupported enabled selections fail evaluation | Best-effort versions can silently violate Python and upstream integration constraints. |
| Local changes | Strict release baseline by default; explicit `--allow-local-changes` for dirty content | Version-only checks are weak; blanket dirty refusal prevents useful doc editing. Custom committed forks remain separate support. |
| Manifest changes | Reject changed revision/project selection initially | Arbitrary edited manifests require a separate completeness/path contract. |
| Output | Default build root under shell-entry project directory, outside SDK Git checkouts; explicit `--output` | SDK-local output dirties inputs; global cache hides output ownership. |
| Repeated builds | Owned output root, fresh generations, publish completed HTML only after verification; reject unrelated roots and concurrent writers | In-place reuse is faster but risks stale merged search and mixing configurations. No automatic recursive deletion of user directories. |
| Serve | Serve completed output only, localhost, port 8000, configurable port, foreground; no auto-build/browser/watch | Live rebuilding adds expensive repeated SDK builds and another lifecycle. |
| Kconfig diff | Separate explicit trust-bearing option, default off | Default-on executes downloaded Python/pickle without a pinned checksum. |

These spellings and defaults need product approval. Output generation and
source fingerprints identify actual inputs and tool/options used, including
dirty inputs. Pre/post checks can detect changes during a build, but are not
immutable source snapshots. No hermetic, fully offline, or byte-reproducible
claim is proposed.

Upstream public sets and dependency graph:
[`doc/CMakeLists.txt:283-439`](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/doc/CMakeLists.txt#L283).
The graph conditionally includes private docs when an internal module exists;
the public-only contract must exclude or explicitly refuse that case rather
than trusting default manifest group filtering.

## Verification required after decisions

Normal CI should prove disabled closure/CLI equivalence, enabled dispatch,
read-only discovery with missing firmware Python/toolchains, source and output
refusals, poisoned ambient environment isolation, dependency constraints,
representative rendering, real localhost HTTP and termination, and adapter
failure behavior. Tests run through public command/subprocess boundaries.

Opt-in prepared-SDK qualification must build all public sets and verify API
content, full bindings, local cross-doc links, navigation, and merged search.
Hardware qualification must additionally inspect child worker count, compiler
discovery, retained Twister results, expected target coverage, and actual table
rows. Run native amd64 nrfutil, amd64 west, and ARM64 west. Nix evaluation alone
does not prove native ARM64 rendering. Repeat into selected output and compare
source/firmware-environment state before and after.

The original prototype ledger remains the only completed rendering/tooling
evidence. No new full-SDK acceptance claim is made here.
