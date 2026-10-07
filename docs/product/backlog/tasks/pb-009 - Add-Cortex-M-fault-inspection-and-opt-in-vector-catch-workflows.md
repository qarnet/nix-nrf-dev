---
id: PB-009
title: Add Cortex-M fault inspection and opt-in vector-catch workflows
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
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

Receiver assertions, stack checks, and offload failures need actionable register/backtrace evidence. Automatic restart or late logging can obscure first-fault context.

### Desired outcome

Users can inspect an application-core fault with matching symbols and explicitly enable fault catch when intrusive debugging is acceptable.

### Scope / Non-goals

Register/fault-status inspection, backtrace and symbolication recipes, opt-in vector catch, and cleanup/state policy. Distinguish CPU exceptions from FLPR timeout or starvation. No production fault hook, DMA recorder, or claim that core registers are always readable while running.

### Technical context

Pinned src/target/cortex_m.c accepts int_err rather than stale manual irq_err and includes a DEMCR cleanup caveat. Receiver prj.conf enables assertions and stack sentinel. Scoped tools and memory export provide related evidence paths.

Research and pinned upstream references: docs/product/research/debug-tooling.md. Receiver evidence: le-audio-receiver at 012b19739802e8fc53d6e8a701fb362a17a1c209, inspected read-only.

### Open questions

Which fault registers and catch modes are safe for the supported security state, and how are prior catch settings restored when a session fails?

This item remains Backlog until refinement resolves implementation-shaping questions and assigns size. Hardware access, flashing, recovery, and intrusive operations still require explicit approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An approved deterministic fixture fault yields expected exception/register context and a useful matching-ELF backtrace or explicitly explains unavailable frames.
- [ ] #2 Vector catch is opt-in, uses commands verified against the pinned binary, and leaves documented target/debug settings on normal exit and failure.
- [ ] #3 Fault inspection performs no automatic reset, recovery, or firmware write; unreadable registers/security states fail clearly.
- [ ] #4 Docs separate first-fault capture from later handler state and explain CPUAPP versus FLPR failure evidence without implementing consumer hooks.
<!-- AC:END -->
