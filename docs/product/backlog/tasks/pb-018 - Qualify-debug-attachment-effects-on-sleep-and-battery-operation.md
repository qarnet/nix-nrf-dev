---
id: PB-018
title: Qualify debug attachment effects on sleep and battery operation
status: Backlog
assignee: []
created_date: '2026-09-26 00:42'
labels:
  - 'area:debug'
  - 'area:testing'
dependencies: []
priority: p2
type: research
ordinal: 18000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

RTT/debug attachment can change internal clocks and sleep behavior, so attached results cannot establish standalone battery behavior. Receiver resume-pop cause is not confirmed to be power management.

### Desired outcome

Support guidance states which sleep states remain observable and how to compare attached and detached operation without misleading power claims.

### Scope / Non-goals

Assess access during sleep, disconnect/reconnect, USB bridge effects, and retained RAM with an approved controlled setup. No automatic power-mode changes, presumed receiver PM fix, or promise of power-neutral RTT.

### Technical context

docs/development/rtt-debug-research.md records debug-mode power effects and Seeed battery/UART caveats. Receiver PLANNED_FEATURES.md:95-108 leaves the resume-pop explanation open.

Research and pinned upstream references: docs/development/rtt-debug-research.md. Receiver evidence: le-audio-receiver at 012b19739802e8fc53d6e8a701fb362a17a1c209, inspected read-only.

### Open questions

Which board revision, sleep modes, instrumentation, and battery/USB configurations can be tested reproducibly?

This item remains Backlog until refinement resolves implementation-shaping questions and assigns size. Hardware access, flashing, recovery, and intrusive operations still require explicit approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Matrix identifies tested and untested attached/detached sleep/access cases with board, probe firmware, and SDK versions.
- [ ] #2 Approved comparisons record observed wake/run-state and power effects; unavailable measurement equipment is a stated limitation.
- [ ] #3 Capture/session documentation warns about debug-induced behavior and inaccessible sleeping targets without resetting them automatically.
- [ ] #4 Findings do not attribute receiver audio faults to power management without independent evidence.
<!-- AC:END -->
