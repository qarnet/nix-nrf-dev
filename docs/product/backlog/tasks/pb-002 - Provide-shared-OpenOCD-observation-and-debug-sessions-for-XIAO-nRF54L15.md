---
id: PB-002
title: Provide shared OpenOCD observation and debug sessions for XIAO nRF54L15
status: Blocked
assignee: []
created_date: '2026-09-26 00:41'
updated_date: '2026-09-27 14:40'
labels:
  - 'area:openocd'
  - 'area:debug'
  - 'area:security'
  - 'size:M'
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

Research and pinned upstream references: docs/product/research/debug-tooling.md. Receiver evidence: le-audio-receiver at 012b19739802e8fc53d6e8a701fb362a17a1c209, inspected read-only.

### Open questions

Resolved for implementation: foreground `nix-nrf session start/status`, explicit serial, private same-user ownership, JSON discovery, optional ephemeral or fixed ports, observation by default, and halt-on-GDB-attach with state left unchanged on disconnect. Clients connect to one owner rather than launch another.

Size M and research-backed run-control safeguards are recorded in the implementation plan. Physical acceptance, including running/halted preservation, still requires explicit hardware approval and is not inferred from host tests.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Approved fixture tests prove observation attach/detach preserves both running and halted targets, boot identity, and known RAM contents without deliberate run control.
- [ ] #2 Probe ambiguity, inaccessible/locked targets, port conflicts, and a second probe owner fail clearly without unlock, erase, or reset.
- [ ] #3 Only requested endpoints listen on loopback; unused GDB/Tcl/Telnet services remain disabled and unsafe raw control is not exposed by default.
- [x] #4 Cancellation and startup failure release owned processes/ports; clients do not terminate sessions they do not own.
- [ ] #5 An approved combined RTT/GDB scenario uses one probe owner and documents that debug halts affect producers; arguments-only tests are not hardware acceptance.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Implement foreground nix-nrf session start/status for explicit CMSIS-DAP v2 serial and CPUAPP, per-user probe lock and atomic session JSON. Observe disables all ports by default, work area and lockup-inducing poll; explicit Tcl is unrestricted loopback opt-in. Debug uses selected GDB port with halt-on-attach and no resume-on-detach. Readiness requires successful examination after services start. Bound startup/shutdown and never attach to or kill another owner. Test subprocess lifecycle, contention, cancellation, failure and real OpenOCD dummy Tcl traffic. Package via existing dispatcher; hardware behavior remains unverified until approved fixture runs.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Readiness choices resolve command/lifecycle questions without changing acceptance. User requested PB-002 and PB-004 together. No hardware operations authorized. Normal OpenOCD examination changes debug registers; documentation must distinguish no deliberate run control from passive attachment.

Implementation available: nix-nrf session start/status, immutable packaged OpenOCD/doctor paths, explicit serial/v2 preflight and nRF54L15 identity check, same-user lock, atomic JSON readiness and session token, opt-in loopback endpoints, disabled observation polling/work area, explicit debug attach/detach policy, bounded SIGTERM then kill cleanup. No automatic flash/reset/recovery.
Host evidence: 9 subprocess/native-OpenOCD tests pass, including real Tcl framing/quoting, ephemeral RTT-service semantics, clean shutdown hook, owner SIGKILL lock retention, contention, timeout, port conflict and restart. Full nix flake check -L and nix build .#nix-nrf --no-link passed. AC4 checked from these process-boundary tests. Host portions of AC2/AC3 pass; physical target portions remain unchecked.
BLOCKER: no approval to provision/access a test-owned XIAO or perform intrusive hardware operations. AC1 and AC5 require actual running/halted preservation and combined RTT/GDB tests. No physical board support is claimed from dummy target tests. Procedure: tests/hardware/debug/README.md; public contract: docs/debug.md.

User authorized use of the attached nRF54L15 for fixture validation. Current blocker is device availability, not approval: nix develop .#hardware-tests -c nix-nrf doctor --json reports zero candidates on hostname thomas-main, corroborated by lsusb showing no Nordic/CMSIS-DAP device. Direct read-only inventory attempt on configured Nix builder thomas-workstation@192.168.178.65 failed publickey authentication. No probe was opened and no flashing/reset/recovery occurred. Need board connected/passed through to accessible host; do not reuse daemon credentials or touch another device.

Physical validation update: attached XIAO EF0E3B64 is accessible via CMSIS-DAP v2, VID:PID 2886:0066, probe FW 2.0.0; fingerprint identifies nRF54L15 part 0x00054b15 variant AAC0. No udev change needed. After fixture flash verified successfully, observation startup fails before CPU examination with Error connecting DP: cannot read IDR. Probe enumeration remains healthy. A 100 kHz SWD retry has the same failure. Nordic MCP documentation distinguishes this from ordinary AP protection, where CTRL-AP remains accessible; no protection diagnosis or recovery/erase attempt made. Evidence: /tmp/opencode/pb004-hil-20260926-043514/observe-first-owner.log. Need non-erasing reset/power diagnosis before acceptance can continue.

Remote-reset investigation recorded in docs/development/pb002-pb004-hardware.md. Exact-serial usbreset SN:EF0E3B64 succeeds unprivileged, but does not restore SWD. Probe-only DAP_ResetTarget returns Status=0 Execute=0; no device-specific reset sequence. SWJ pin pulse and connect-under-reset did not recover access; nRESET response bit never asserted, so physical reset support remains unproven. Stock multidrop and adapter quirk modes also fail. Installed pyOCD 0.42.0 with auto_unlock=false, resume_on_disconnect=false and attach mode independently reports No ACK. No automatic reset/recovery added to observation. True per-port power switching remains unverified and needs suitable hardware/permissions.

User-supplied Seeed KiCad/PDF confirms PA04/A3 drives Q2 NMOS gate and nRF54_RESET: gate high asserts, low releases. Hardware reset wiring exists. New report docs/development/xiao-probe-reset-research.md records exact design hashes and independently disassembled published stock firmware. Its DAP_SWJ_Pins nRESET branch writes zero GPIO mask, startup leaves reset pin unmapped, DAP_ResetTarget is a two-zero-byte stub, and HostStatus has no PA04 alias. This is a community dump, not an actual EF0E3B64 backup; version/USB identity match is corroboration only. Dump has beyond-EOF references and must not be flashed as a complete image. Need full installed SAMD11 backup/reset-capable firmware qualification or separate reset control; no existing working PA04 USB packet established. Factory_reset scripts explicitly mass-erase and were not run.

Reviewed user-supplied Seeed repos. uf2-samdx1 master 0615d4a47806cf3f00da84e08811f2a927640316 has explicit BOARD=XIAO_samd11 PLAT=nRF54L15, boot USB 2886:8066, SAMD11BOOT, appbase 0x1600. This is a board-specific USB-update candidate, not installed-loader proof. Investigate loader presence/entry before requiring external probe. Arduino_DAPLink is generic Arduino/TinyUSB probe framework without an exact onboard mapping; CMSISAtmel is chip-support headers/startup, not probe firmware. Factory reset remains nrf54l erase/flash, not SAMD11 update. Compatibility checks include bootloader/app bounds, actual BOOTPROT, linker origin and reset inversion; nothing flashed or installed during review. Details and pinned sources: docs/development/xiao-probe-reset-research.md.

Deeper Seeed forum research found XIAO-specific source: forum topic294019 post38 links baorepo/free-dap. Initial XIAO NRF54 support commit6412081 uses nRESET A,-1; current master63721c5 explicitly defines HAL_NO_GPIO_nRESET for L15 and makes reset writes no-ops. This corroborates earlier disassembly with source, but does not identify installed bytes. v1.01 supplies a combined SAMD11 bootloader+app binary and app UF2; independently inspected vectors at0/0x1600 and matching overlapping payload. Stock release does not enable PA04 reset. Existing pinned OpenOCD includes jlink and at91samd drivers. Host currently sees no external J-Link, so wiring/model verification and full actual readback remain next physical prerequisites. Detailed forum evidence and protection traps added to docs/development/xiao-probe-reset-research.md.

2026-09-27 RST2 check: kernel USB log shows repeated re-enumerations during user reset attempts, always normal 2886:0066 EF0E3B64; no observed 2886:8066 UF2 mode. Current USB device number61 versus prior20. Reset timing and bootloader absence are not conclusively proven by this. Fresh exact-serial discovery still has no target DPIDR. No writes/erase performed. Recommend actual full SAMD11 readback via external probe instead of more uninstrumented reset attempts; details in docs/development/pb002-pb004-hardware.md.

Workstream handoff 2026-09-27: user paused bench work to prepare physical setup. SAMD11 reset research and detailed hardware evidence now live in ~/repos/xiao-samd11-debug-probe, cloned from baorepo/free-dap at63721c581f1e908c9ae847772fc301b0fb9da819. Start HANDOFF.md and docs/reset-pin-fix.md there. Schematics, comparison firmware, Nordic fixture/build context and logs were preserved with SHA-256 manifest. Original doc paths remain short forwarding records. PB-002 host implementation and physical acceptance remain owned here and Blocked. No hardware operation or firmware source patch performed during transfer.
<!-- SECTION:NOTES:END -->
