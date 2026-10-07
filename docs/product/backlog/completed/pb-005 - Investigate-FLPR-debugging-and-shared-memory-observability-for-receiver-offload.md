---
id: PB-005
title: >-
  Investigate FLPR debugging and shared-memory observability for receiver
  offload
status: Done
assignee: []
created_date: '2026-09-26 00:41'
updated_date: '2026-09-26 01:07'
labels:
  - 'area:flpr'
  - 'area:debug'
  - 'area:openocd'
  - 'size:M'
dependencies: []
documentation:
  - docs/product/research/debug-tooling.md
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

Research and pinned upstream references: docs/product/research/debug-tooling.md. Receiver evidence: le-audio-receiver at 012b19739802e8fc53d6e8a701fb362a17a1c209, inspected read-only.

### Open questions

Can CMSIS-DAP reach a usable RISC-V debug module? Which address/ELF maps apply? Can one core halt without recovery destroying evidence? Can FLPR produce independently readable RTT channels under OpenOCD's single-target limitation?

These questions define the research outputs rather than unresolved product behavior. Size M covers SDK, host-stack, and receiver source investigation. Hardware access, flashing, recovery, and intrusive operations still require explicit approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Capability matrix cites exact silicon/tool revisions for memory reads, registers, halt/resume, stepping, breakpoints, RTT, and access protection; unknown and unsupported are distinct.
- [x] #2 Receiver use cases cover ASRC deadline/fallback, shared PCM rings, IPC handshake epochs, automatic restart, and image identity; effects of CPUAPP or FLPR halt are analyzed.
- [x] #3 A minimal approved hardware experiment demonstrates each claimed usable path, or records the exact validation blocker without claiming hardware support.
- [x] #4 Recommendation compares direct run control with memory snapshots/counters/IPC export and identifies any justified OpenOCD pin or second-stack change.
- [x] #5 Findings define follow-up implementation scope and public-boundary tests; FLPR is not deferred merely because the current config lacks a RISC-V target.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Establish source revisions and receiver evidence lifetimes: FLPR ASRC, shared SRAM, restart and handshake epochs.
2. Verify silicon/SDK debug interfaces and pinned/current CMSIS-DAP host-stack support; separate memory access from run control.
3. Write capability matrix, recommended first usable tooling slice, and a bounded hardware experiment requiring explicit approval.
4. Validate citations and backlog with doctor, repository backlog check, pre-commit and diff checks. Do not run probe commands, flash, or claim hardware validation.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Readiness assessment: size M for source-backed research across SDK, host tools, and receiver. Existing open questions are the research deliverable, not unresolved product behavior. Scope and acceptance unchanged; no dependencies. Hardware use is not authorized; acceptance permits an explicit validation blocker rather than a hardware-support claim.

Source investigation complete. SDK v3.3.0 defines a memory-mapped VPR RISC-V debug interface; official OpenOCD pinned and current revisions lack its DMI bridge. AUX mem_ap halt/step only change software state. probe-rs and Raspberry Pi OpenOCD contain real MEM-AP DMI precedents, but Nordic address translation/target integration and board validation remain gaps.
Receiver recovery_work_fn can reset rings and restart/reload FLPR after a halt-induced timeout. Read-only research recommends PB-002 sessions followed by PB-008 RAM export and PB-006 RTT through CPUAPP AP0, without assuming FLPR run control.
Hardware blocker: no probe/target operation authorized; silicon identity, security state, loaded images and probe firmware are unmeasured. Report defines a fixture-only approved validation sequence, and claims no tested board support.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Completed source-backed FLPR research; concise findings and pinned sources are retained in docs/product/research/debug-tooling.md. No public tool, SDK pin, receiver firmware, or hardware state changed.
AC1: revision-pinned capability matrix and SDK register/security evidence distinguish defined silicon mechanisms, stock transport gaps, and untested board behavior.
AC2: inspected receiver recovery_work_fn, FLPR SRAM reload, rings, deadline and epochs; documented evidence destruction and independent-core halt risks.
AC3: fulfilled the explicit blocker alternative, not hardware proof. No probe operations authorized; actual board/probe firmware, loaded images and security state unmeasured. Report specifies reviewed-status readback, heartbeat, RTT, halt/register/step and breakpoint experiments on a test fixture.
AC4: retain current OpenOCD for AP0 RAM/RTT; no upstream pin bump solves FLPR DMI. probe-rs and Raspberry Pi fork provide bridge precedents but require Nordic mapping/integration and hardware qualification.
AC5: recommend PB-002 plus PB-004, then PB-008 and PB-006; define bounded translated-DMI follow-up rather than deferring FLPR or claiming stock support.
Validation: nix build .#checks.x86_64-linux.backlog .#checks.x86_64-linux.pre-commit .#checks.x86_64-linux.formatting --no-link -L passed; git diff --check passed. SDK inspection pinned to receiver NCS v3.3.0. Hardware acceptance remains with future feature/experiment work. Research completion is not a supported-debugger claim.
<!-- SECTION:FINAL_SUMMARY:END -->
