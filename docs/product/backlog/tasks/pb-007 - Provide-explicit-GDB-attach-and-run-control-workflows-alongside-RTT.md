---
id: PB-007
title: Provide explicit GDB attach and run-control workflows alongside RTT
status: Backlog
assignee: []
created_date: '2026-09-26 00:41'
updated_date: '2026-09-26 00:42'
labels:
  - 'area:debug'
  - 'area:openocd'
dependencies:
  - PB-002
  - PB-003
  - PB-004
priority: p1
type: feature
ordinal: 7000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

Users need matching-ELF debugging without running flash scripts. Default OpenOCD GDB attachment halts the target, which can change audio/offload behavior.

### Desired outcome

An explicit debug workflow connects matching GDB to the shared server with documented attach/detach semantics and symbol-only loading.

### Scope / Non-goals

Application-core GDB attach, ELF selection, explicit halt/run-control policy, stepping, and concurrent RTT use. Distinguish loading symbols from loading firmware. Keep raw monitor commands available rather than wrapping every command. No implicit flashing/reset, automatic unlock, promised non-stop GDB, or assumed FLPR run control.

### Technical context

nix/backends/nrfutil/shell.nix; tcl/nrf54l_flash.tcl; pinned OpenOCD src/target/startup.tcl default gdb-attach handler. Receiver scripts/bin/fw-flash-54l15 resets and loads both images, so it is not an attach helper.

Research and pinned upstream references: docs/development/rtt-debug-research.md. Receiver evidence: le-audio-receiver at 012b19739802e8fc53d6e8a701fb362a17a1c209, inspected read-only.

### Open questions

Which attach modes are supported, how is halted state handled on disconnect, and what matching-image checks are feasible without introducing target writes?

This item remains Backlog until refinement resolves implementation-shaping questions and assigns size. Hardware access, flashing, recovery, and intrusive operations still require explicit approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A pre-provisioned fixture can be debugged using matching ELF symbols without image load, reset, erase, or unlock.
- [ ] #2 Approved tests demonstrate declared halt-on-attach, stepping, and disconnect behavior; observation mode cannot accidentally enable this intrusive workflow.
- [ ] #3 GDB and RTT run through one server and report the effect of a halt on firmware output rather than promising uninterrupted production.
- [ ] #4 Missing/mismatched ELF, connection refusal, and tool failure produce useful diagnostics; symbol-only operations and explicit destructive commands are clearly separated.
<!-- AC:END -->
