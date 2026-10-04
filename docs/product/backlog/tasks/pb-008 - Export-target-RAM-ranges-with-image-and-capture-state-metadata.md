---
id: PB-008
title: Export target RAM ranges with image and capture-state metadata
status: Backlog
assignee: []
created_date: '2026-09-26 00:41'
updated_date: '2026-09-26 00:42'
labels:
  - 'area:debug'
  - 'area:flpr'
  - 'area:cli'
dependencies:
  - PB-002
  - PB-004
priority: p1
type: feature
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

Fatal faults or stalled workers may prevent firmware from draining a recorder. Receiver shared PCM rings and FLPR execution memory also need inspectable evidence outside UART output.

### Desired outcome

Users can export explicit accessible RAM ranges as exact binary files with enough metadata to interpret them against matching images.

### Scope / Non-goals

Address/length validation, target/core and ELF/build metadata, explicit output policy, partial-read failures, and shared-session use. Live reads are non-atomic; CPU halt alone does not stop DMA. No arbitrary peripheral scans, automatic core stop/restart, hard-coded receiver maps, or application recorder decoder.

### Technical context

docs/development/rtt-debug-research.md#memory-snapshots-and-fault-inspection; OpenOCD dump_image/read_memory. Receiver overlay reserves IPC 0x20028000..0x20030000 and PCM rings at 0x2002C000/0x2002E000; src/flpr_runtime.c asserts execution SRAM 0x20030000..0x20040000. Addresses are consumer evidence, not generic defaults.

Research and pinned upstream references: docs/development/rtt-debug-research.md. Receiver evidence: le-audio-receiver at 012b19739802e8fc53d6e8a701fb362a17a1c209, inspected read-only.

### Open questions

Which metadata format and output atomicity policy should be public, and how should inaccessible/partial ranges be represented without misleading users?

This item remains Backlog until refinement resolves implementation-shaping questions and assigns size. Hardware access, flashing, recovery, and intrusive operations still require explicit approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A known frozen fixture range exports byte-for-byte through the public command, with address, length, target state, and supplied image identity.
- [ ] #2 Invalid/overflowing ranges, inaccessible RAM, disconnects, and output-write failures cannot produce an apparently complete success result.
- [ ] #3 Observation export does not halt/reset/resume or use arbitrary scratch RAM; live captures explicitly lack a consistency guarantee.
- [ ] #4 Documented frozen-buffer workflow works independently of a surviving firmware export worker; security/alias limitations remain explicit and no receiver-specific decoder is added.
<!-- AC:END -->
