---
id: PB-001
title: Move the nrfutil tested baseline to NCS v3.4.1
status: Done
assignee: []
created_date: '2026-09-26 00:41'
updated_date: '2026-10-06 07:31'
labels:
  - 'size:L'
  - 'area:nrfutil'
  - 'area:west'
  - 'area:toolchain'
  - 'area:testing'
dependencies: []
priority: p2
type: tech-debt
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

Active repository shells and qualification still select v3.3.0. User now requires v3.4.1 for both backends and all active CI/qualification, with explicit optional Python tooling selection. The v3.4 LTS branch is the last NCS branch supporting nRF52 including nRF52840.

### Desired outcome

Both supported Linux hosts use v3.4.1 as active baseline. West uses official Zephyr SDK 1.0.1 GNU layout, Python 3.12, west 1.5.0 and cbor2 5.9.0 constraint. Optional SDK requirement groups are explicit flake configuration; managed setup installs selected groups with approval, caller-owned environments remain check-only.

### Scope / Non-goals

Update active shell/package pins, CI and qualification fixtures, prerequisite scripts and examples; preserve historical evidence and releases. Remove v3.3.0 from active west metadata, never reuse old SDK evidence as new acceptance. Support named west Python requirement groups ncs-extra and ncs-ci; reject unknown groups and unsupported backend selection. Baseline requirements remain mandatory. Do not migrate consumer firmware pins, modify SDK registrations, redesign Python environment ownership, flash hardware, publish Git changes or bump project release. User approved fresh isolated SDK/toolchain/Python provisioning and builds/command qualification on amd64 and Pi, preserving existing environments.

### Technical context

Official sdk-nrf v3.4.1 release notes confirm five-year LTS and last nRF52 branch; release.yaml lists nrf52840 active. Tools metadata selects Zephyr SDK 1.0.1 and Python 3.12; fixed requirements select west 1.5.0 and cbor2 5.9.0. Official SDK 1.0.1 publisher checksums verified for both hosts; GNU compiler tree now gnu/<target>, CMake cmake/zephyr/gnu. v3.4.1 still declares missing suit_manifest.py; retain structural failure reporting. Files: nix/backends/west/{versions,zephyr-sdk,bootstrap,default}.nix, nix/flake/{components,dev-shells,per-system}.nix, bin/backends/west/nix-nrf-west-bootstrap, tests/application-types/.

### Open questions

None implementation-shaping. Actual Nordic bundle identity and new compiler/parser/build qualification are acceptance evidence to collect, not assumed from metadata.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Approved isolated provisioning and re-entry prove selected SDK/toolchain identity and unchanged parent-shell environment; actual west/compiler versions are recorded.
- [x] #2 Existing representative nRF5340 CPUAPP/CPUNET and nRF54L15 CPUAPP/FLPR builds pass with v3.4.1; build success is not reported as hardware execution proof.
- [x] #3 Active repository defaults, west metadata/package outputs, CI and qualification select v3.4.1 on both supported hosts. v3.3.0 is historical only, never current acceptance. Explicit consumer pins remain caller-owned.
- [x] #4 Optional west Python requirement groups are validated flake configuration; approved managed setup installs selected groups and readiness detects missing selected imports. Existing workspace environments are check-only and unknown/unsupported requests fail clearly. User/contributor docs and executable gates agree without changing historical evidence or release version.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Ground official v3.4.1/LTS and SDK 1.0.1 metadata; migrate active outputs and executable tests. 2. Add validated opt-in west Python requirement groups and non-mutating selected-tool readiness tests. 3. Provision fresh isolated v3.4.1 source/Python/Nordic tools on approved hosts, retaining logs and resource limits; test registry/parser activation and representative firmware. 4. Run both-host native gates and update evidence/limitations; no hardware operations or publication.

Resumed 2026-10-06: review latest native prerequisite/joint resolver/pip-check and structured VERSION changes; run focused public regressions. Finish fresh ARM64 baseline six-case build and four-layout registry/parser audit, preserving paused reports. Refresh imported v3.4.1 workspace builds on both hosts. Reconcile active docs versus historical evidence; run both native full gates, package outputs and generated consumer smoke. Record exact SDK/tool/Python identity and parent/source preservation. Keep missing upstream suit-manifest explicit; no full upstream constraint generator, checksum updater, hardware action or Git publication in this slice.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
User superseded earlier nrfutil-only scope: no active v3.3.0 testing; both backends target v3.4.1. Explicit approval received for isolated downloads/provisioning on amd64 and Pi. Official source verifies suit_manifest.py still missing in v3.4.1, so SDK upgrade alone does not resolve that parser failure.

Historical pause: user requested a stop before providing additional information; the session checkpoint has since been retired. At that pause, active v3.4.1/SDK 1.0.1 migration and optional west requirement groups were implemented; amd64 six-profile/two-backend firmware qualification passed 12 cases, four-layout parser audit completed 312 cases with only upstream missing suit-manifest repeated (8 failures). Fresh Pi provisioning passed after explicit PyPI pygit2 prerequisite and joint requirement resolution. Pi build run stopped during final FLPR case: five cases passed, incomplete report retained, experiment returncode -15. VERSION-format/pip-consistency/native-prerequisite edits still needed final focused/full gates, Pi parser audit and refreshed imported-workspace qualification. No verification job was left running. Subsequent resumption and completed acceptance are recorded below.

User authorized resumption of PB-001 after metadata/research aside. PB-029 through PB-033 remain Backlog; their future lock/updater work is not included in this migration completion. Earlier isolated provisioning approval remains scoped to fresh test-owned environments, existing SDKs and user environments preserved.

Fresh v3.4.1 acceptance complete. sdk-nrf b20f8619ba9a5530f8c34b0a130d829947cfe55d / sdk-zephyr 33fa6a7aac6a4401d16a67cb9f27a3483fa02dd6. amd64 baseline 12/12 cases (/tmp/opencode/pb001-v341-baseline-builds-v2/result.json); ARM64 6/6 (Pi pb001-v341-baseline-resumed/result.json, 950.25s). Imported application manifests/module linkage pass four amd64 builds (/tmp/opencode/pb001-v341-imported-amd64-v3/result.json, 164.76s) and two ARM64 builds (Pi pb001-v341-imported-native/result.json, 822.47s), original inputs unchanged. Stock parser audits complete 312/156 cases; only dangling suit-manifest fails (8/4), preservation true; no SBOM proxy or hidden skip. Public scoped identity checks and generated consumer evaluation/entry pass both hosts. Nordic bundle8285d8ad56 reports Python3.12.4/west1.5.0/GCC14.3.0; Nix SDK1.0.1 GCC14.3.0 and prepared west Python3.12.13/west1.5.0 observed separately. All six package outputs build per host, all-systems no-build/shared evaluation passes, full native gates pass amd64 and Pi (pb001-v341-final-native-gates-v3.json return0,90.25s cached successful native derivations). Native source24/bootstrap40/doctor30/catalog4 regressions pass. Initial failed/superseded runs retained; final pass does not erase them.

Additional readiness gap fixed: pip check cannot detect absent requested roots. Selected baseline/group requirement roots and version constraints now checked with real installed distribution metadata; orientation-only module test requirements are not implicitly enabled. Public regression uses real pyusb import/pip check, missing wget distribution, read-only workspace check/--yes refusal, and explicitly installed offline test wheel recovery. Root paths resolve from active manifest identities including relocated mcuboot. Literal EXTRAVERSION field allowlisted for typos; generated upstream catalog excluded only from spelling checks, secret scanning retained with exact public SDK-selector false-positive exemptions. No package lock generator or checksum updater, consumer firmware pin change, SDK source patch, hardware operation, release bump or Git publication.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Migrated active development/CI/qualification baseline to NCS v3.4.1 on both Linux hosts; west now uses official fixed-hash Zephyr SDK1.0.1 GNU layout, Python3.12 and initial west1.5.0. Added validated opt-in ncs-extra/ncs-ci requirement groups, explicit native pygit2 prerequisite recipe, joint dependency resolution, selected-root/version and pip-consistency readiness while preserving caller-owned check-only Python. Structured Nordic VERSION fields supported. All four criteria demonstrated with fresh SDK identity, parent/source preservation, representative ARM/RISC-V firmware builds, imported-module linkage, native repository/package gates and generated consumer smoke. Upstream suit-manifest registration remains structurally broken in stock3.4.1 and is explicitly recorded as failed parser cases, not a migration acceptance requirement or silent skip. Current caller docs and historical evidence boundaries reconciled. All changes uncommitted; no hardware execution or hosted GitHub run/publication claimed.
<!-- SECTION:FINAL_SUMMARY:END -->
