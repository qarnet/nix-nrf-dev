---
id: PB-022
title: Publish receiver-facing RTT and debug integration guidance
status: Backlog
assignee: []
created_date: '2026-09-26 00:42'
updated_date: '2026-09-26 00:42'
labels:
  - 'area:documentation'
  - 'area:debug'
  - 'area:flpr'
dependencies:
  - PB-006
  - PB-007
  - PB-008
  - PB-005
priority: p1
type: docs
ordinal: 22000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

Receiver pins an older SDK/tooling revision, owns serial HIL and production recorder policy, and needs usable new host tools without hidden firmware migration or competing probe/serial owners.

### Desired outcome

A consumer guide demonstrates the supported host workflows and clearly states firmware prerequisites, evidence limits, and ownership boundaries.

### Scope / Non-goals

Document version-pinned adoption, board/ELF selection, UART handoff, observe versus debug modes, binary recorder export, and FLPR findings. Retain fixed-size-record/freeze-first-fault guidance as consumer advice, not a production framework. No edits to receiver firmware, automatic SDK upgrade, or claim that host raw capture detects arbitrary producer losses.

### Technical context

README.md; docs/hardware.md; docs/backends.md; saved research. Receiver flake.nix:24-30 pins NCS v3.3.0, scripts/bin/fw-flash-54l15:107 uses legacy nrf-probes, and scripts/hil/serial_io.py owns serial lifecycle. Current public discovery is nix-nrf probes.

Research and pinned upstream references: docs/product/research/debug-tooling.md. Receiver evidence: le-audio-receiver at 012b19739802e8fc53d6e8a701fb362a17a1c209, inspected read-only.

### Open questions

Which final commands and supported FLPR paths emerge from feature work, and what minimum consumer configuration fits its RAM/timing budget?

This item remains Backlog until refinement resolves implementation-shaping questions and assigns size. Hardware access, flashing, recovery, and intrusive operations still require explicit approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Guide uses verified public commands and matching image/probe selection, while retaining explicit consumer SDK pins and documenting legacy command migration.
- [ ] #2 A reproducible small-fixture walkthrough demonstrates capture, shared debug access, and frozen RAM export; application production acceptance is not inferred from it.
- [ ] #3 Recorder guidance distinguishes bounded RAM recording from export, recoverable from fatal faults, sequence gaps from trailing loss, and RTT consumption from durable file storage.
- [ ] #4 Firmware schema/fault/retention policy stays consumer-owned; guide explains CPU/DMA consistency, thread/ISR commit markers, and power-loss limits without prescribing production code.
- [ ] #5 FLPR findings and serial ownership are integrated with explicit supported/unknown claims; no receiver worktree modification is required to publish the guide.
<!-- AC:END -->
