---
id: PB-021
title: Evaluate a separate opt-in provision-and-debug workflow
status: Backlog
assignee: []
created_date: '2026-09-26 00:42'
labels:
  - 'area:openocd'
  - 'area:cli'
  - 'area:security'
dependencies: []
priority: p3
type: research
ordinal: 21000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

Automatic flashing was deliberately excluded from initial capture, but a later convenience workflow may be useful. Existing flash recipes mutate target state and must not become implicit attach behavior.

### Desired outcome

A decision bounds any future combined workflow while preserving non-destructive observation commands.

### Scope / Non-goals

Assess packaging existing recipes and explicit user-controlled build/flash/debug sequencing, image/core validation, consent, and failure boundaries. No capture-time flashing, automatic recovery, nRF52 expansion, or default destructive behavior.

### Technical context

tcl/nrf54l_flash.tcl; tcl/nrf53_flash.tcl; docs/hardware.md#recovery-safety. Receiver scripts/bin/fw-flash-54l15 already owns application-specific image loading.

Research and pinned upstream references: docs/product/research/debug-tooling.md. Receiver evidence: le-audio-receiver at 012b19739802e8fc53d6e8a701fb362a17a1c209, inspected read-only.

### Open questions

Is a generic combined command preferable to documented separate commands, and what can be reused without absorbing consumer orchestration?

This item remains Backlog until refinement resolves implementation-shaping questions and assigns size. Hardware access, flashing, recovery, and intrusive operations still require explicit approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Decision compares separate commands with an explicitly requested combined workflow, including probe/image/core mismatch and partial failure cases.
- [ ] #2 Any proposed API leaves observation defaults unchanged and requires explicit authorization for flash/reset while refusing automatic unlock/recovery.
- [ ] #3 Follow-up implementation scope and approved fixture verification are specified only if the convenience workflow provides clear value.
<!-- AC:END -->
