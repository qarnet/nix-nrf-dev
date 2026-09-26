---
id: PB-010
title: Document and verify hardware breakpoints and CPU watchpoints
status: Backlog
assignee: []
created_date: '2026-09-26 00:41'
updated_date: '2026-09-26 00:42'
labels:
  - 'area:debug'
  - 'area:openocd'
dependencies:
  - PB-007
priority: p1
type: feature
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

CPU-owned pointer/ring-state corruption is relevant to receiver failures, but generic watchpoint advice can incorrectly imply DMA visibility or unlimited hardware resources.

### Desired outcome

Users can stop on known CPU execution and read/write accesses with validated commands and clear hardware limits.

### Scope / Non-goals

Application-core hardware breakpoints, CPU read/write/access watchpoints, removal/cleanup, and stepping interrupt-mask guidance. Prefer recipes through GDB/OpenOCD rather than a second debugger. No DMA bus monitoring or timing-neutral claim.

### Technical context

Pinned src/target/cortex_m.c implements DWT comparators and maskisr modes. Receiver src/flpr_ring.h contains CPU-owned ring indices and shared-memory ordering; stopping CPU can trigger offload deadlines/recovery elsewhere.

Research and pinned upstream references: docs/development/rtt-debug-research.md. Receiver evidence: le-audio-receiver at 012b19739802e8fc53d6e8a701fb362a17a1c209, inspected read-only.

### Open questions

What comparator count, alignment/range constraints, interrupt stepping behavior, and cleanup guarantees are supported on the actual board?

This item remains Backlog until refinement resolves implementation-shaping questions and assigns size. Hardware access, flashing, recovery, and intrusive operations still require explicit approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Approved fixture tests hit the expected instruction and CPU write/read location and show usable context through the public GDB workflow.
- [ ] #2 Unsupported alignment/range and comparator exhaustion produce clear failures, and removing a breakpoint/watchpoint restores expected execution.
- [ ] #3 Docs state that DWT does not observe arbitrary peripheral DMA transactions and that halting disturbs audio/IPC timing.
- [ ] #4 Interrupt-masking recipes are validated against the pinned implementation, are explicit intrusive choices, and document restoration and spare-breakpoint constraints.
<!-- AC:END -->
