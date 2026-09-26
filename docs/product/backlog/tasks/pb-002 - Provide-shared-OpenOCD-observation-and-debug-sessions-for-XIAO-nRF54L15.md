---
id: PB-002
title: Provide shared OpenOCD observation and debug sessions for XIAO nRF54L15
status: Backlog
assignee: []
created_date: '2026-09-26 00:41'
labels:
  - 'area:openocd'
  - 'area:debug'
  - 'area:security'
dependencies: []
priority: p1
type: feature
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

Independent probe processes contend for CMSIS-DAP, while flash helpers reset and write the target. Receiver audio and FLPR recovery make hidden run-control changes especially harmful.

### Desired outcome

One explicitly selected OpenOCD process owns the probe and offers safe observation or explicit intrusive debugging to reusable clients.

### Scope / Non-goals

Use the pinned OpenOCD, explicit serial/core/speed and configurable local ports. Observation preserves running or halted state, disables GDB and unused services, and disables unreserved work-area allocation. Debug mode defines attach/detach run control. Include ownership, diagnostics, cancellation, and cleanup. No automatic recovery, erase, flashing, remote exposure, or inferred FLPR run control.

### Technical context

nix/hardware/openocd.nix; nix/commands/default.nix; bin/commands/nix-nrf-probes; tests/hardware/preflight_xiao.py; tcl/nrf54l_flash.tcl. Pinned target reserves 16 KiB at 0x20000000 without backup; default gdb-attach halts. Receiver src/flpr_runtime.c restarts FLPR independently of CPUAPP.

Research and pinned upstream references: docs/development/rtt-debug-research.md. Receiver evidence: le-audio-receiver at 012b19739802e8fc53d6e8a701fb362a17a1c209, inspected read-only.

### Open questions

Finalize public command shape, session discovery/ownership, port allocation, disconnect policy, and how consumers connect without launching another owner.

This item remains Backlog until refinement resolves implementation-shaping questions and assigns size. Hardware access, flashing, recovery, and intrusive operations still require explicit approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Approved fixture tests prove observation attach/detach preserves both running and halted targets, boot identity, and known RAM contents without deliberate run control.
- [ ] #2 Probe ambiguity, inaccessible/locked targets, port conflicts, and a second probe owner fail clearly without unlock, erase, or reset.
- [ ] #3 Only requested endpoints listen on loopback; unused GDB/Tcl/Telnet services remain disabled and unsafe raw control is not exposed by default.
- [ ] #4 Cancellation and startup failure release owned processes/ports; clients do not terminate sessions they do not own.
- [ ] #5 An approved combined RTT/GDB scenario uses one probe owner and documents that debug halts affect producers; arguments-only tests are not hardware acceptance.
<!-- AC:END -->
