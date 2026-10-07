---
id: PB-004
title: Add small RTT and debug verification firmware with an opt-in hardware harness
status: Blocked
assignee: []
created_date: '2026-09-26 00:41'
updated_date: '2026-09-27 14:40'
labels:
  - 'area:testing'
  - 'area:rtt'
  - 'area:debug'
  - 'size:M'
dependencies: []
priority: p1
type: feature
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

Existing hardware tests prove image placement but not RTT bytes, attach state preservation, debug inspection, or FLPR execution. Reusing production audio firmware would couple generic tooling acceptance to application behavior.

### Desired outcome

Small test-owned firmware provides deterministic observable data and target state for public tooling tests.

### Scope / Non-goals

Provide known text and binary records, sequence/session identity, observable loss/completeness metadata, a frozen RAM pattern, and distinct threads. Keep fault/watchpoint scenarios explicitly intrusive. Separate approved provisioning from observation tests. Production DMA recorder/schema and audio implementation are non-goals; FLPR scenarios follow research findings.

### Technical context

tests/hardware/README.md; tests/hardware/run.sh; tests/hardware/preflight_xiao.py; docs/product/research/debug-tooling.md. Existing harness flashes but does not validate FLPR heartbeat or IPC.

Research and pinned upstream references: docs/product/research/debug-tooling.md. Receiver evidence: le-audio-receiver at 012b19739802e8fc53d6e8a701fb362a17a1c209, inspected read-only.

### Open questions

Resolved for implementation: NCS v3.3.0 `xiao_nrf54l15/nrf54l15/cpuapp`, direct RTT text/binary channels, fixed DATA/SUMMARY wire records, and explicit GDB-written intrusive selectors. Build/provision stays separate from observation. A validated warm-reset counter provides bounded identity evidence, not guaranteed identity across power loss.

Size M is recorded in the implementation plan. Physical verification of record emission, run-state preservation, and intrusive scenarios remains subject to explicit hardware approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Fixture emits reproducible text/binary records including non-text bytes, session identity, and known overflow/completion evidence without formatted logging in a sensitive producer path.
- [ ] #2 Known frozen RAM contents, distinct blocked/running threads, and explicit intrusive fault/watchpoint scenarios support repeatable assertions.
- [x] #3 Build/provision and observe/debug stages are separate; normal CI neither flashes nor accesses hardware, and hardware provisioning requires approval.
- [ ] #4 Harness records probe, board, toolchain, image identity, commands, raw evidence, and outcomes; unknown or unavailable hardware results are not marked passed.
- [x] #5 Tests remain small fixtures under tests, not a reusable production flight-recorder framework; each tooling feature retains its own acceptance tests.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Build small NCS v3.3.0 xiao_nrf54l15/nrf54l15/cpuapp fixture with two direct RTT up-channels, whole-record nonblocking binary writes, sequence/drop summaries, bounded warm-reset identity, frozen pattern, named threads and explicit GDB-written intrusive selectors. Provide separate build/provision documentation and approval-gated host verification consuming an existing session plus matching ELF. Harness records identity, raw evidence, commands and incomplete/failure results; no auto-flash or auto-recovery. Test wire parser offline and build using installed SDK/toolchain without bootstrap. Hardware acceptance requires separate approval.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Size M. Scenario selection is explicit debug-memory action rather than RTT console. Firmware is test-owned and does not implement consumer DMA recording or FLPR run control. Boot counter retention limits and reset ambiguity must be stated, not presented as globally unique identity.

Implementation available: test-owned xiao_nrf54l15 CPUAPP firmware with direct text/binary RTT, shared C serializer, whole-record skip/drop accounting and retried summaries, frozen RAM, two named threads plus blocked main, explicit watch/panic action word, and documented bounded warm-reset identity. Matching-ELF approval-gated harness retains raw channels, commands, identity/build provenance and before/after snapshots; no flash or run-control commands in capture.
Build evidence: installed NCS v3.3.0 with autoBootstrap=false; west build --no-sysbuild -b xiao_nrf54l15/nrf54l15/cpuapp -d /tmp/opencode/pb004-build /home/thomas/repos/nix-nrf-dev/tests/firmware/debug-fixture passed. Image uses 35556 B flash and 12820 B RAM. ELF parser verified all required symbols and retained in noinit SHT_NOBITS; source/config tag 0x5cb9966d. Resolved config has PRINTK/NCS_BOOT_BANNER disabled, fresh RTT initialization and thread metadata enabled.
Host evidence: 7 tests cover C-encoded binary parsing/loss/completeness, duplicates/reset detection, actual TCP Tcl/RTT capture and owned cleanup, approval refusal, and cross-probe baseline rejection. Full nix flake check -L passed. AC3 and AC5 checked for source ownership and separated opt-in stages.
BLOCKER: fixture has not been flashed or run on hardware. AC1/AC2/AC4 physical emission, debug inspection and evidence run remain unverified. Need explicit approval and test-owned XIAO before provisioning/reset/halt tests. .noinit is not a power-loss identity guarantee; do not weaken that limitation.

User approved use of attached nRF54L15. Hardware validation remains blocked because execution host thomas-main enumerates no supported probe in doctor --json or lsusb. Configured build workstation could not be inventoried through normal user SSH due to publickey authentication failure. No firmware was provisioned; build artifact remains available under /tmp/opencode/pb004-build. Resume after the intended board is visible on an accessible host.

Physical provisioning update: rebuilt matching fixture without SDK bootstrap, then explicitly flashed serial EF0E3B64 through pinned OpenOCD nrf54l_flash recipe. load/verify succeeded and reset run completed. Subsequent SWD DP ID reads fail at both 1000 and 100 kHz while onboard CMSIS-DAP USB remains accessible. Flash verification proves byte placement only; firmware execution/RTT emission has not passed. Hardware runner failed before readiness, evidence directory /tmp/opencode/pb004-hil-20260926-043514. No mass erase or recovery performed; do not check physical acceptance from flash verification.

After user physical reconnect, target SWD remains inaccessible although CMSIS-DAP enumeration and raw probe commands work. Logical USB reset succeeds but not target recovery. The separate xiao-samd11-debug-probe project owns detailed physical diagnostics; this item's notes retain the acceptance boundary. Physical acceptance still blocked; do not infer execution from flash verification. No further firmware writes, mass erase, probe firmware update, or NixOS changes performed.

Reset investigation now distinguishes physical wiring from firmware exposure. Seeed PA04/Q2 hardware path is confirmed. A matching published probe image has disabled reset-pin mapping; firmware fix needs direction initialization and inverted logical nRESET handling, not a one-byte mask change alone. Exact installed probe image still unknown. Receiver nRF5340 history used UICR protection correction and CTRL-AP reset through working SWD, not a transferable missing-DPIDR fix. Serial-mcp SWD precedent was unresolved; its UART DTR/RTS fixes do not prove this bridge resets nRF54. No erase or probe firmware change made.

Forum evidence distinguishes missing USB/COM bridge recovery from Nordic DP NoACK. Community rescue backup reads only0x25e0, omitting6688 main-flash bytes and user row; flash_prot sets BOOTPROT to full16384, unsuitable to copy blindly for future UF2 updates. User has J-Link and spares; plan non-erasing direct Nordic attachment plus full SAMD11/untouched-spare backup before firmware changes. No J-Link is currently enumerated on thomas-main. No downloaded recovery scripts or firmware images were executed/flashed during this research.

Workstream handoff 2026-09-27: probe investigation moved to ~/repos/xiao-samd11-debug-probe/HANDOFF.md while user prepares physical access. Exact provoking Nordic ELF/HEX, source snapshot, resolved config, DTS/map and failure log copied into that workspace with checked hashes. Canonical fixture and harness remain in this repo; no new physical acceptance passed. Continue after separate probe workspace resolves target access.
<!-- SECTION:NOTES:END -->
