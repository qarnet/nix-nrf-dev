---
id: PB-001
title: Move the nrfutil tested baseline to NCS v3.4.1
status: Backlog
assignee: []
created_date: '2026-09-26 00:41'
labels:
  - 'area:nrfutil'
  - 'area:toolchain'
dependencies: []
priority: p2
type: tech-debt
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

Repository nrfutil shells and baseline validation still select v3.3.0. The user requested v3.4.1 for this backend only; receiver itself still explicitly pins v3.3.0.

### Desired outcome

Contributors can provision and validate the nrfutil baseline at v3.4.1 without changing west support or consumer version selections.

### Scope / Non-goals

Update active nrfutil shell pins, clean-room/hardware prerequisites, examples, and relevant tests. Leave west metadata, its v3.3.0 tests and package name, historical release entries, arbitrary-version fixtures, and the nix-nrf-dev release version unchanged. Do not migrate receiver firmware or install SDK bundles without approval.

### Technical context

nix/flake/dev-shells.nix; nix/backends/nrfutil/shell.nix; nix/backends/west/versions.nix; tests/clean-room/run.sh; tests/hardware/run.sh. Official v3.4.1 tools metadata and requirements-fixed disagree on west version; the recorded bundle checksum is research, not an installed-bundle assertion.

Research and pinned upstream references: docs/development/rtt-debug-research.md. Receiver evidence: le-audio-receiver at 012b19739802e8fc53d6e8a701fb362a17a1c209, inspected read-only.

### Open questions

Which sdk-manager bundle is selected for v3.4.1, what executables does it actually supply, and do all existing representative images build unchanged?

This item remains Backlog until refinement resolves implementation-shaping questions and assigns size. Hardware access, flashing, recovery, and intrusive operations still require explicit approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Default nrfutil and clean-env shells report v3.4.1; explicit consumer pins remain honored and west retains its current baseline.
- [ ] #2 Approved isolated provisioning and re-entry prove selected SDK/toolchain identity and unchanged parent-shell environment; actual west/compiler versions are recorded.
- [ ] #3 Existing representative nRF5340 CPUAPP/CPUNET and nRF54L15 CPUAPP/FLPR builds pass with v3.4.1; build success is not reported as hardware execution proof.
- [ ] #4 Active nrfutil docs and baseline gates agree, while west metadata and historical records remain unchanged; no automatic flashing or unrelated release bump is introduced.
<!-- AC:END -->
