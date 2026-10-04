---
id: PB-024
title: Qualify application-owned imported SDK workspaces with local source reuse
status: Done
assignee: []
created_date: '2026-10-03 23:09'
updated_date: '2026-10-04 02:32'
labels:
  - 'size:M'
  - 'area:testing'
  - 'area:toolchain'
  - 'area:documentation'
dependencies:
  - PB-023
priority: p2
type: tech-debt
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

PB-023 real firmware qualification reused one SDK-owned manifest. Distinct SDK paths and application-owned imports have host-fixture coverage, but not a full real NCS build from an independent application-owned workspace.

### Desired outcome

A focused local-only qualification proves real manifest import, relocated SDK paths, manifest-owned extra-module discovery, and source isolation through both public toolchain backends.

### Scope / Non-goals

Reuse already installed NCS v3.3.0 Git objects through independent local shared clones and independent working files; never use source-external symlinks, hard-linked working files, source Git worktrees, west update, downloads, source patching, or hardware. Generate a test-owned application manifest importing Nordic first and overriding Zephyr with the exact pinned Nordic allowlist. Relocate unmodified stock sources to sdk/nrf and sdk/rtos; preserve Nordic module basename because stock metadata derives its name from that basename. Add a manifest-owned extra module, four single/sysbuild builds across nrfutil and west, source/module/compiler/ELF checks, meaningful negative tests, source/config/ref/index non-mutation checks, and recorded size/time limits. Missing local objects, dirty inputs, unsupported local assets or budget excess fail explicitly. Keep original 16-case matrix; no new release, SDK version, board, compiler, Python installation or Git publication implied.

### Technical context

PB-023; tests/application-types/run.py; bin/commands/nix-nrf-source; tests/firmware/source-fixture; docs/development/application-source-status.md. Installed SDK is 5.9 GiB on ext4, so no reflink assumption. West imports need destination manifest-rev refs, including Nordic now being an imported project. NCS v3.3.0 nrf/zephyr/module.yml lacks explicit name; renaming nrf to nordic changes stock module identity.

### Open questions

None for this bounded qualification. Local source/resource availability is verified at runtime; failures remain recorded rather than triggering acquisition.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Independent fixture resolves an application-owned manifest importing the same installed SDK revisions, with relocated sdk/nrf and sdk/rtos paths and manifest-owned extra module; no update, download, original Git metadata write or source patch occurs.
- [x] #2 Four public builds pass with both backends in single-image and sysbuild modes; every sampled Zephyr/Nordic/module path belongs to the new workspace, correct compiler/Python environment is selected, extra-module symbol links, and ELF hashes are retained.
- [x] #3 Negative checks reject conflicting original source environments and missing importer refs without repairing or fetching; fixture setup refuses existing destinations, dirty inputs, source external links or missing objects and obeys size/free-space limits.
- [x] #4 Original SDK tracked state, refs, HEAD, index/config fingerprints and workspace config remain unchanged; clone sharing and temporary-resource lifetime limitations, costs, commands, raw evidence and tested boundaries are documented.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add bounded local-only fixture preparation with native west/Git parsing, captured revisions/refs and independent working files. 2. Add ordinary CI tests of preparation/refusals with real disposable Git inputs. 3. Add opt-in four-build imported-workspace harness with module-symbol/source-path/Python/compiler checks, negative conflicts/importer checks and original-input non-mutation verification. 4. Run installed-source qualification and full gates, retain evidence and update user/contributor test documentation; do not commit or publish without approval.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
User approved focused tests with local reuse. SDK source shape, west import precedence/prefixes, destination manifest-rev requirements, and stock Nordic module-identity limitation verified against NCS v3.3.0 and west 1.5.0. PB-023 dependency complete. No publication or dependency-download approval included.

Implemented local-only fixture helper, four-build public qualification harness, manifest-owned firmware/module fixture, and seven real disposable Git/west tests. Missing local revisions and free-space shortage now have refusal coverage. Fixed final preservation failure exit propagation. Final real run exited 0: four builds and four negative checks passed; original_inputs_unchanged=true. Evidence: /tmp/opencode/imported-workspace-qualification-final/result.json. Independently recomputed four ELF SHA-256 hashes. Setup 12.2 s, total 146.6 s, tracked estimate 1,489,276,214 bytes; allocated workspace about 1.9 GiB plus 113 MiB builds. Explicit matter/cmock exclusions and shared-object lifetime/basename/resource limits documented. Full repository gates pending.

Repository verification passed: nix flake check --all-systems --no-build -L after writable product evaluation, nix flake check -L (all checks, including formatting/hooks and seven fixture tests), all six CI package outputs, clean-env-test, 22 release tests, 16 initializer tests, git diff --check. Unrelated user-owned opencode.json preserved. Python bytecode generated by direct release testing retained outside repository at /tmp/opencode/nix-nrf-release-pycache.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Qualified independent application-owned imported NCS v3.3.0 sources through both public backends: four single-image/sysbuild builds and four conflict/missing-import-ref rejection checks passed on x86_64-linux and xiao_nrf54l15/nrf54l15/cpuapp. Added bounded local shared-clone preparation with independent working files/Git metadata, a manifest-owned firmware/module fixture, and seven SDK-free real Git/west lifecycle/refusal tests. Final source-preservation failures now return nonzero. Original source tracked state, refs, HEAD, index/config fingerprints and workspace configuration remained unchanged; source/module/compiler/Python selections, linked symbols and independently recomputed ELF hashes verified. Evidence and limits documented in docs/development/application-source-status.md and tests/application-types/README.md; raw report/logs/builds retained at /tmp/opencode/imported-workspace-qualification-final/result.json. Setup 12.2 s, total 146.6 s; tracked estimate 1.39 GiB, allocated workspace about 1.9 GiB plus 113 MiB builds. Full flake/evaluation/formatting/hooks gates, six package outputs, clean environment, release (22) and initializer (16) suites passed. Shared clones require retained original object stores; matter/cmock and unavailable submodule features excluded. No SDK acquisition, dependency install, source patch, hardware operation, new release or Git publication performed.
<!-- SECTION:FINAL_SUMMARY:END -->
