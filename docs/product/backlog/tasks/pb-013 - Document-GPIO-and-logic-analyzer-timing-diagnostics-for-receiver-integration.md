---
id: PB-013
title: Document GPIO and logic-analyzer timing diagnostics for receiver integration
status: Backlog
assignee: []
created_date: '2026-09-26 00:41'
labels:
  - 'area:debug'
  - 'area:documentation'
dependencies: []
priority: p1
type: docs
ordinal: 13000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

Receiver timing failures and resume pops need external timing evidence. Historical FRAMESTART assumptions and occupied XIAO pins make generic instrumentation advice unsafe.

### Desired outcome

Consumers have a repeatable method to correlate GPIO markers, I2S timing, and software evidence without treating instrumentation as timing-neutral.

### Scope / Non-goals

Generic guidance and a small test-owned demonstration if needed: board pin review, event semantics, trace correlation, and overhead measurement. Production marker placement, DMA recorder changes, analog diagnosis, and automatic analyzer control remain out of scope.

### Technical context

Receiver src/audio_timing_nrf54.c:8-25 distinguishes DMA-buffer FRAMESTART cadence from LRCK; boards/nrf54l15dk_nrf54l15_cpuapp.overlay:130-140 already uses D3/P1.7 for MCK; PLANNED_FEATURES.md:90-108 describes long-idle resume pop with unconfirmed cause.

Research and pinned upstream references: docs/development/rtt-debug-research.md. Receiver evidence: le-audio-receiver at 012b19739802e8fc53d6e8a701fb362a17a1c209, inspected read-only.

### Open questions

Which spare pins and analyzer/sample-rate setup are available, and which timing boundaries distinguish software delay from digital/analog output effects?

This item remains Backlog until refinement resolves implementation-shaping questions and assigns size. Hardware access, flashing, recovery, and intrusive operations still require explicit approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Guide verifies pin ownership and event semantics against the consumer revision instead of prescribing an occupied XIAO pin or equating FRAMESTART with sample cadence.
- [ ] #2 A documented approved fixture measurement correlates a known event with captured edges, or clearly records missing equipment without claiming validation.
- [ ] #3 Overhead and timing disturbance are measured or bounded with an explicit comparison method; production changes are left to the consumer.
- [ ] #4 Guide explains how to correlate analyzer captures with RTT/UART/session evidence and separates I2S submission proof from analog sound quality.
<!-- AC:END -->
