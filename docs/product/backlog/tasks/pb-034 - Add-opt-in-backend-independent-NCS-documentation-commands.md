---
id: PB-034
title: Add opt-in backend-independent NCS documentation commands
status: Ready
assignee: []
created_date: '2026-10-12 01:25'
updated_date: '2026-10-14 02:01'
labels:
  - 'size:L'
  - 'area:documentation'
  - 'area:cli'
  - 'area:nix'
dependencies: []
priority: p2
type: feature
ordinal: 32000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem
Generating local NCS documentation requires a separate hand-built environment and SDK workspace knowledge. Developers need project-configured documentation builds without adding documentation-only dependencies to every firmware shell.

### Desired outcome
A default-off documentation settings attrset in mkNrfShell enables shell-only nix-nrf docs build. Enabled projects build documentation from their selected existing SDK workspace with isolated pinned tools and declarative settings. Disabled projects retain CLI, dependency closure, and environment behavior. The approved specification is docs/product/research/ncs-documentation-contract.md; earlier research proposals are superseded.

### Scope / Non-goals
Initially qualify NCS v3.4.1 across native amd64 nrfutil and native amd64/ARM64 west. documentation.enable defaults false; docsets defaults [ "all" ]; jobs defaults 2; output defaults "build/ncs-docs" as a shell-entry-anchored string; allowLocalChanges defaults false. Docset selection means requested targets plus required supporting docsets, which remain in output. Include Doxygen API content, full devicetree bindings, landing/navigation and merged search. Hardware features and Kconfig diff are separate default-off settings. Hardware features require explicit sdkPackage, bounded child jobs, retained reports and Nordic metadata coverage. Kconfig diff consent includes downloaded executable Python/pickle trust. Sources alone suffice for ordinary docs; missing firmware Python/toolchain does not trigger readiness failure or repair. Support stock and application-owned imported workspace paths without checkout changes. Output uses owned fresh generations and publishes verified HTML only.
No serving, standalone facade, duplicate build-setting CLI flags, private docs, PDF, arbitrary SDK releases/forks, implicit source acquisition/update, mutable Python provisioning, global CMake registration, hardware operations, or offline/hermetic/byte-reproducible guarantee. Defer successful internal-present exclusion: refuse a locally present manifest-resolved doc-internal path before configure/rendering. Preserve the standalone prototype as research, not a second bootstrap path. Future per-release tool indexing/shared environment qualification belongs to PB-031, not a prerequisite for this initial release.

### Technical context
Repository baseline 94f7371646f56d5fb46bf32406cdef817f52b85b. Public options: nix/backends/default.nix; dispatcher: nix/commands/default.nix; source resolution: nix/backends/source.nix and bin/commands/nix-nrf-source. Full bootstrap checks also require firmware readiness, so docs need independent read-only discovery. Existing compiler package: packages.<system>.west-zephyr-sdk-v3_4_1. SDK examined at sdk-nrf v3.4.1 b20f8619ba9a5530f8c34b0a130d829947cfe55d and Zephyr ncs-v3.4.1 33fa6a7aac6a4401d16a67cb9f27a3483fa02dd6. Upstream combined graph and requirements need pinned tooling; Python requirements validate compatibility but do not resolve Nix packages/native tools or prove rendering. Hardware helper drops SDK variables, omits jobs and catches child failure. Internal inclusion has independent CMake/Python paths. Upstream manifest and relative path assumptions need controlled build-local adaptation for imported layouts. Research/prototype: docs/product/research/ncs-documentation.md, ncs-documentation-refinement.md, and ncs-documentation-prototype/. No real full-SDK build is qualified yet.

### Open questions
No unresolved product choice blocks implementation. Full rendering, selected-subset navigation/search, imported-layout adaptation, hardware metadata coverage/resource bounds, and native ARM64 execution remain technical implementation and qualification work. Missing evidence must not be reported as acceptance. Sources/compiler acquisition requires separate approval when needed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 With documentation omitted or enable false, public-shell tests prove unchanged CLI behavior and no documentation-only additions to consumer runtime closure; shell entry never provisions documentation sources/environments.
- [ ] #2 Enabled settings validate the approved attrset schema and reject invalid selections/types/unknown keys; public command is shell-only nix-nrf docs build with no serve or standalone facade, duplicate setting flags, or hidden environment overrides.
- [ ] #3 Public build uses configured v3.4.1 and manifest-resolved sources in stock and application-owned imported workspaces on native amd64 nrfutil and amd64/ARM64 west; ordinary docs work without firmware Python/toolchain readiness, while unprofiled releases, missing/mismatched inputs and internal-present sources fail explicitly without acquisition, repair, source substitution or backend fallback.
- [ ] #4 Real public-command default build produces all public upstream HTML sets with Doxygen API content, full devicetree bindings, landing/navigation, representative working local cross-doc links and merged search; a selected dependency-bearing subset retains required supporting docsets and has navigation/search matching actual outputs.
- [ ] #5 Flake-enabled hardware features use explicitly selected SDK in child Twister/CMake discovery, bound actual child workers by jobs, retain diagnostics, account for expected Nordic targets and legitimate skips, and produce representative populated tables; missing prerequisites, child failure or missing required metadata fail rather than claim complete output.
- [ ] #6 Build leaves SDK revisions/content, firmware Python and global CMake registration unchanged; tests cover strict/explicit local-edit policy, forbidden manifest changes, shell-entry-anchored output strings, repeated changed selections, unrelated/concurrent output refusal, and failed-build nonpublication with no stale merged search.
- [ ] #7 Pinned documentation tool environment satisfies actual applicable tagged Python requirements and native prerequisites, rejects incompatible requirements without installing packages, and neither consumes nor leaks ambient Nordic/venv Python state; dependency validation and representative rendering run in normal CI.
- [ ] #8 Kconfig diff remains default-off flake opt-in with explicit executable downloaded Python/pickle trust; ordinary remote inventory requirements and lack of offline/hermetic/byte-reproducible guarantees are documented accurately.
- [ ] #9 Approved contract, user configuration/build guide, architecture ownership and relevant repository gates stay aligned; prepared-SDK qualification is opt-in, records real native host/backend outcomes, and never adds mutable SDK bootstrap or hardware access to normal CI.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Read-only refinement research recorded in docs/product/research/ncs-documentation-refinement.md. Verified prepared sdk-nrf v3.4.1 and matched Zephyr commit; no full docs build or SDK acquisition performed. New findings: Nordic-only upstream hardware filter; no helper-level Twister jobs knob; child failure may leave incomplete successful HTML; active-manifest resolution alone does not remove upstream relative-path assumptions. Proposed interface, source/version/local-edit, output, serving, compiler, and qualification policies await product decisions. Status remains Backlog; scope and acceptance text unchanged.

Product owner decisions: use documentation settings attrset with enable default false; shell-only build command; no serve command or standalone facade; existing sources suffice without firmware readiness. Flake-versus-CLI research and superseding decisions recorded in docs/product/research/ncs-documentation-refinement.md. Recommend jobs/output and build policy in attrset, without duplicate CLI overrides initially. Docset selection, enrichments, release policy, and final schema remain under discussion. Acceptance text unchanged pending refinement; serving criterion must be removed before Ready.

Product owner accepted docset selection as requested build targets plus required supporting docsets. Internal exclusion investigated: no single flag; CMake discovery and Python existence-based registry are independent. Recommend defer successful internal-present builds with explicit preflight refusal, not silent private output. Requirements-driven dynamic pinned tooling is not available from mutable txt alone; shared pinned environments plus runtime compatibility validation avoid duplicating every pin per release. Broader reviewed docs release metadata and qualification added to PB-031 at owner request, without making it a dependency of initial PB-034 support. Findings in docs/product/research/ncs-documentation-refinement.md; no new implementation or full-SDK evidence.

Product owner approved recommendations and requested recording, commit and push on a dedicated branch. Approved contract written in docs/product/research/ncs-documentation-contract.md. Replaced stale boolean/serve proposals and acceptance with documentation attrset, build-only shell interface, declarative jobs/output/selection, explicit enrichments, strict initial v3.4.1 support, local-edit policy and internal-present refusal. Prior research/prototype retained as historical evidence. PB-031 owns later per-release tool indexing and shared-environment qualification. No implementation or full-SDK acceptance claimed.

Refinement publication validation passed: backlog/formatting/pre-commit Nix checks; scripts/release.py check; tests/unit/test_release.py (22 tests); root all-systems no-build flake evaluation; preserved prototype native flake checks and both-system no-build evaluation. Prototype Nix syntax normalized for repository formatter/statix without dependency or embedded-command changes; lock SHA-256 remains 5470602ba565de069725756e4fbbd58843f64ebd9645ba9950cac903f412c964. Added certifi identifier spelling exception. These checks validate research/prototype publication, not integrated feature acceptance or full SDK rendering. All implementation acceptance boxes remain unchecked.
<!-- SECTION:NOTES:END -->
