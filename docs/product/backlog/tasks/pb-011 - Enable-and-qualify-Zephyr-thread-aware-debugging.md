---
id: PB-011
title: Enable and qualify Zephyr thread-aware debugging
status: Backlog
assignee: []
created_date: '2026-09-26 00:41'
updated_date: '2026-09-26 00:42'
labels:
  - 'area:debug'
  - 'area:toolchain'
dependencies:
  - PB-007
priority: p1
type: feature
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

Receiver has dedicated pairing and offload recovery workqueues, tight stack budgets, and blocking lifecycle paths. Core-only backtraces do not explain which thread is blocked.

### Desired outcome

An optional profile exposes real Zephyr threads and useful per-thread backtraces for a matching firmware build.

### Scope / Non-goals

OpenOCD Zephyr awareness, verified firmware metadata requirements, matching ELF, supported saved contexts, and troubleshooting. Do not enable production firmware settings here or assume all FPU/security contexts decode correctly.

### Technical context

Pinned src/rtos/zephyr.c expects _kernel and _kernel_thread_info_* symbols. Receiver boards/nrf54l15dk_nrf54l15_cpuapp.conf:104-114 documents stack pressure; src/audio_offload.c:80-103 defines recovery queue and submit mutex. Verify SDK Kconfig rather than copying stale symbols.

Research and pinned upstream references: docs/development/rtt-debug-research.md. Receiver evidence: le-audio-receiver at 012b19739802e8fc53d6e8a701fb362a17a1c209, inspected read-only.

### Open questions

Which selected-SDK metadata options are required, what RAM impact results, and which suspended/FPU/security contexts can be decoded reliably?

This item remains Backlog until refinement resolves implementation-shaping questions and assigns size. Hardware access, flashing, recovery, and intrusive operations still require explicit approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Approved multi-thread fixture tests list distinct running/blocked threads and recover expected frames from more than the current thread.
- [ ] #2 Missing metadata and mismatched ELF produce actionable diagnostics rather than misleading thread names or frames.
- [ ] #3 Profile docs give verified SDK requirements, RAM costs, and tested context limits; unsupported contexts are explicitly qualified.
- [ ] #4 Thread awareness remains optional and shares the existing GDB/OpenOCD session without implicit firmware changes.
<!-- AC:END -->
