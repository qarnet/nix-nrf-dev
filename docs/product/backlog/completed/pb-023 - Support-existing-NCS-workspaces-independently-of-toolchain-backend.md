---
id: PB-023
title: Support existing NCS workspaces independently of toolchain backend
status: Done
assignee: []
created_date: '2026-10-03 03:13'
updated_date: '2026-10-03 13:28'
labels:
  - 'size:L'
  - 'area:toolchain'
  - 'area:nrfutil'
  - 'area:west'
  - 'area:testing'
  - 'area:documentation'
dependencies: []
documentation:
  - docs/development/application-types-research.md
priority: p2
type: feature
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

Both shell backends inject a managed SDK source path, so project-owned manifests and repository/workspace/freestanding application layouts cannot independently choose SDK sources.

### Desired outcome

Either toolchain backend can build against an explicitly selected existing NCS workspace without installing duplicate SDK sources, changing its manifest, or leaking Nordic environment variables into the parent shell. User guidance explains choosing tools separately from sources.

### Scope / Non-goals

Add source = { mode = "managed"; } (default) or source = { mode = "workspace"; workspace = "."; }. Relative strings are anchored on shell entry; Nix path values are rejected to avoid copying SDK trees into the store. Resolve Zephyr from the west manifest, including relocated project paths; reject conflicting inherited bases, workspace configuration, foreign CWD workspaces, source-version mismatch, and detectable stale build caches. Keep ncsVersion as explicit compatibility/toolchain baseline; same-version forks are allowed with reported source identity. Workspace source mode never acquires or updates sources. nrfutil bootstraps only missing toolchains in this mode. The west backend consumes an already prepared workspace .venv, or an explicit pythonEnvironment string resolved relative to the workspace, without implicit pip installation. Keep managed behavior compatible. Include source diagnostics, user docs, host regression checks and opt-in real-build qualification. No source installers, manifest scaffolding, global CMake export, baseline/platform upgrades, direct-CMake toolchain execution API, or hardware operations.

### Technical context

Research: docs/development/application-types-research.md, NCS v3.3.0 source and 11 CMake discovery probes. Implementation boundaries: nix/backends/default.nix; nix/backends/nrfutil/shell.nix and bootstrap.nix; nix/backends/west/shell.nix and bootstrap.nix; bin/backends/* bootstrap scripts; nix/commands/default.nix and doctor.nix. West Manifest.from_topdir resolves imported project paths without update; west -z selects base without persisting zephyr.base.

### Open questions

Product direction is approved. Public workspace support is bounded to existing complete NCS workspaces and caller-prepared Python dependencies. Actual real-build qualification depends on already installed compatible environments; unavailable qualification must remain unchecked and recorded, not inferred from subprocess tests.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Omitted/managed source settings preserve existing public shell and bootstrap behavior; invalid source options fail at evaluation with actionable diagnostics.
- [x] #2 Both public backend shells select the configured workspace and manifest Zephyr path for repository, workspace, and freestanding applications, including relocated Zephyr and same-version source forks; conflicting environments, workspace/CWD choices and detectable stale caches fail instead of mixing sources.
- [x] #3 Workspace-mode readiness and bootstrap never acquire/update sources, rewrite manifests/configuration, or export CMake packages; nrfutil can use a toolchain without a managed SDK source installation, and west uses a pre-provisioned Python environment with clear missing-dependency errors.
- [x] #4 Source diagnostics identify mode, workspace, manifest, Zephyr and Nordic paths/revisions separately from toolchain selection; cancellation, quoting, child exit status and parent environment isolation remain correct.
- [x] #5 User documentation provides concise examples for managed and existing sources with either backend, all three application topologies, Python preparation, fresh build directories, and precise non-goals.
- [x] #6 Public-boundary host tests cover success/failure and lifecycle cases; an opt-in real-build matrix records intended source/module/compiler selection and artifacts for both backends with single-image and sysbuild across all application types, or records exact missing-environment blockers without claiming qualification.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add strict source options and a read-only west-manifest resolver with runtime anchoring and source diagnostics. 2. Route workspace mode through toolchain-only nrfutil bootstrap and existing-environment west readiness; preserve managed behavior. 3. Wire scoped west source selection, conflict/cache checks and doctor metadata. 4. Add public shell/subprocess tests with distinct workspaces and real CMake package selection, plus an opt-in no-download firmware build matrix. 5. Write plain user guide and examples, run flake/package/environment gates, and record checked versus unperformed acceptance. No commits or hardware operations.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Readiness established from approved independent-axis design and pinned research. Size L: cross-backend readiness, source resolution, diagnostics, tests and user docs. No implementation dependency on blocked RTT/debug items; workspace Python preparation remains explicit and caller-owned.

Implemented strict managed/workspace source options, runtime anchoring, real west-manifest/import resolution, NCS VERSION checks, conflict/CWD/cache guards, child package discovery for plain or hinted find_package, toolchain-only nrfutil bootstrap, check-only prepared-Python west bootstrap, and separate source/toolchain-selection diagnostics. User guide: docs/application-types.md. Source/qualification evidence: docs/development/application-source-status.md. Managed behavior retains its existing gates.

Verification passed: nix flake check --all-systems --no-build -L; nix flake check -L; nix build .#nix-nrf --no-link; git diff --check; clean-env-test public shell regression. source-workspace-tests has 13 passing tests, using real west/CMake, distinct source workspaces, disposable Git manifest imports, both package declarations, failures, cancellation, environment isolation and no source mutation.

User explicitly approved isolated Python dependency downloads and a temporary workspace-root fixture. Both public backends passed 8 real build cases each on installed NCS v3.3.0 / xiao_nrf54l15/nrf54l15/cpuapp: Zephyr repository, Nordic repository, workspace and freestanding, each single-image and sysbuild. Intended source/module/compiler paths, extra-module linked symbols and ELF bytes independently verified. Reports: /tmp/opencode/application-matrix-nrfutil-verified/result.json and /tmp/opencode/application-matrix-west-verified/result.json. SDK repository tracked files unchanged. No source updates, SDK/toolchain installation, CMake export, flashing, or hardware execution.

Python preparation caught invalid extras in constraints and Nordic mirror 404s. Test venv used SDK base/build profiles with an extras-free copy of fixed pins, PyPI fallback and isolated Python variables. No SDK requirement file edited. Temporary app retained at /home/thomas/ncs/v3.3.0/nix-nrf-source-fixture-qualification; venv at /tmp/opencode/source-qualification-venv. Build qualification does not establish all boards/releases/forks or hardware execution.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Independent source ownership now works with either existing toolchain backend. Default managed behavior remains compatible; existing workspaces are inspected without acquisition or update, and all three application layouts use the selected SDK through scoped west execution. Plain user guidance, source diagnostics and reusable host/real-build checks accompany the implementation.

AC1: evaluation refusal checks and existing managed bootstrap/shell gates pass. AC2: both backends route all layouts correctly through real west/CMake; relocated/imported/modified source fixtures and conflict/cache failures are covered. AC3: source inventory/update/export attempts are refused or absent at public process boundaries; existing Python environment is never implicitly repaired. AC4: diagnostic identity, ownership, quoted paths, cancellation, exit propagation and parent/child environment isolation pass. AC5: docs/application-types.md gives concise configuration, ownership, Python, build and troubleshooting examples. AC6: all 16 real firmware cases pass with verified source/compiler/module evidence, extra-module symbols and ELF hashes, in addition to 13 host tests and full repository gates.

Qualified baseline: NCS v3.3.0, x86_64-linux, xiao_nrf54l15/nrf54l15/cpuapp. No hardware operation, SDK baseline upgrade, initializer manifest scaffold, global package export or direct-CMake execution API added. Work remains uncommitted on feat/application-source-workspaces; publication requires separate authorization.
<!-- SECTION:FINAL_SUMMARY:END -->
