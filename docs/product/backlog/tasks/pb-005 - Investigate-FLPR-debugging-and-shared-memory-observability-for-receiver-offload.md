---
id: PB-005
title: >-
  Investigate FLPR debugging and shared-memory observability for receiver
  offload
status: Backlog
assignee: []
created_date: '2026-09-26 00:41'
labels:
  - 'area:flpr'
  - 'area:debug'
  - 'area:openocd'
dependencies: []
priority: p1
type: research
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

Receiver offloads ASRC to FLPR with an 8 ms deadline and CPUAPP recovery. Current OpenOCD AUX memory access and successful flashing do not establish FLPR registers, stepping, breakpoints, or usable RTT capture.

### Desired outcome

An evidence-backed capability decision identifies useful FLPR observation and debugging paths before any deferral or implementation claim.

### Scope / Non-goals

Inspect silicon debug architecture, access/security/aliases, pinned and newer OpenOCD support, and alternative CMSIS-DAP stacks only for demonstrated gaps. Distinguish memory access, execution proof, RTT producer visibility, and run control. Evaluate shared RAM/IPC/epoch export if direct debugging is unavailable. No assumption that HAL DMCONTROL access proves host stepping; no production recorder implementation.

### Technical context

nix/hardware/openocd.nix and pinned target/nordic/nrf54l.cfg expose Cortex-M AP0 and mem_ap AP1. Receiver src/audio_offload.c:5-37,61-95; src/flpr_runtime.c:5-41,89-108; src/flpr_ring.h; boards/nrf54l15dk_nrf54l15_cpuapp.overlay. CPUAPP may reload execution SRAM and restart FLPR after a timeout.

Research and pinned upstream references: docs/development/rtt-debug-research.md. Receiver evidence: le-audio-receiver at 012b19739802e8fc53d6e8a701fb362a17a1c209, inspected read-only.

### Open questions

Can CMSIS-DAP reach a usable RISC-V debug module? Which address/ELF maps apply? Can one core halt without recovery destroying evidence? Can FLPR produce independently readable RTT channels under OpenOCD's single-target limitation?

This item remains Backlog until refinement resolves implementation-shaping questions and assigns size. Hardware access, flashing, recovery, and intrusive operations still require explicit approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Capability matrix cites exact silicon/tool revisions for memory reads, registers, halt/resume, stepping, breakpoints, RTT, and access protection; unknown and unsupported are distinct.
- [ ] #2 Receiver use cases cover ASRC deadline/fallback, shared PCM rings, IPC handshake epochs, automatic restart, and image identity; effects of CPUAPP or FLPR halt are analyzed.
- [ ] #3 A minimal approved hardware experiment demonstrates each claimed usable path, or records the exact validation blocker without claiming hardware support.
- [ ] #4 Recommendation compares direct run control with memory snapshots/counters/IPC export and identifies any justified OpenOCD pin or second-stack change.
- [ ] #5 Findings define follow-up implementation scope and public-boundary tests; FLPR is not deferred merely because the current config lacks a RISC-V target.
<!-- AC:END -->
