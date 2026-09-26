---
id: PB-019
title: Evaluate BLE telemetry as a later consumer observability option
status: Backlog
assignee: []
created_date: '2026-09-26 00:42'
labels:
  - 'area:debug'
  - 'area:documentation'
dependencies: []
priority: p3
type: research
ordinal: 19000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

Wireless telemetry could help untethered diagnosis but shares radio/runtime resources with LE Audio and cannot replace fatal-fault access.

### Desired outcome

A decision states whether any generic host support is useful beyond existing UART statistics, before adding another telemetry transport.

### Scope / Non-goals

Compare use cases, bandwidth/latency impact, security, host clients, and coexistence with audio. Firmware services/protocol design and production integration remain consumer-owned. No BLE implementation is committed by this research item.

### Technical context

Receiver src/bt_shell.c:115-162 already exposes ISO quality and negotiated CIS data over UART; docs/development/rtt-debug-research.md lists BLE as later, healthy-firmware-only observability.

Research and pinned upstream references: docs/development/rtt-debug-research.md. Receiver evidence: le-audio-receiver at 012b19739802e8fc53d6e8a701fb362a17a1c209, inspected read-only.

### Open questions

What unmet wireless use case exists, what telemetry budget is acceptable during LE Audio, and would existing clients suffice?

This item remains Backlog until refinement resolves implementation-shaping questions and assigns size. Hardware access, flashing, recovery, and intrusive operations still require explicit approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Decision compares BLE with existing UART/RTT evidence paths and identifies a concrete unmet use case or recommends no new tooling.
- [ ] #2 Radio/runtime overhead, data access/security, disconnect behavior, and inability to capture fatal failures are explicit.
- [ ] #3 Any proposed experiment is bounded and requires approval for radio/hardware operations; production firmware changes are not included.
<!-- AC:END -->
