---
id: PB-014
title: Document optional semihosting for controlled debug and test I/O
status: Backlog
assignee: []
created_date: '2026-09-26 00:41'
updated_date: '2026-09-26 00:42'
labels:
  - 'area:debug'
  - 'area:documentation'
dependencies:
  - PB-007
priority: p2
type: docs
ordinal: 14000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

OpenOCD supports semihosting, but users may mistake it for a non-intrusive RTT substitute.

### Desired outcome

An opt-in, tested recipe makes semihosting available for suitable fixtures with its execution and host-access costs explicit.

### Scope / Non-goals

Matching debugger/firmware prerequisites, enable/disable workflow, behavior without a debugger, and allowed host operations. No default enablement, audio-sensitive logging, or unrestricted host file operations.

### Technical context

Pinned src/target/arm_semihosting.c handles Cortex-M BKPT 0xAB after a debug halt. docs/development/rtt-debug-research.md records this as optional debug/test I/O, not continuous capture.

Research and pinned upstream references: docs/development/rtt-debug-research.md. Receiver evidence: le-audio-receiver at 012b19739802e8fc53d6e8a701fb362a17a1c209, inspected read-only.

### Open questions

Which subset of operations is useful and safe, and what target behavior occurs when a semihosting trap has no attached handler?

This item remains Backlog until refinement resolves implementation-shaping questions and assigns size. Hardware access, flashing, recovery, and intrusive operations still require explicit approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An approved minimal fixture produces expected host output through the explicit GDB/OpenOCD workflow and can disable semihosting afterward.
- [ ] #2 Docs explain debugger trap/latency behavior and test the debugger-absent case without claiming uninterrupted execution.
- [ ] #3 Host file/system access risks and allowed operations are explicit; semihosting remains disabled in default observation sessions.
<!-- AC:END -->
