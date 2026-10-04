# FLPR debug capabilities over CMSIS-DAP

PB-005 research result, 2026-09-26. Source inspection only: no probe connection,
target register transaction, firmware build, installation, flash, reset, or
recovery was performed. No board capability below is hardware-validated.

## Decision

Do not defer FLPR debugging as a silicon impossibility. nRF54L15 SDK headers
describe a memory-mapped RISC-V debug module with halt/resume, abstract register
access, debug PC, and single-step controls. The missing stock OpenOCD component
is a transport connecting that module to its RISC-V debugger engine.

For the quickest useful receiver tooling, implement **PB-002 shared observation
sessions**, followed by **PB-008 explicit RAM exports and PB-006 RTT capture**
with the PB-004 fixtures. These can use CPUAPP's AP0 memory path to observe
accessible FLPR-owned RAM without requiring FLPR run control. RTT additionally
requires firmware to supply a compatible control block and producer protocol.
The current receiver's round-trip-time counters are not an RTT transport.

Keep direct FLPR run control as a bounded engineering follow-up, not a promised
configuration switch. No official OpenOCD pin bump or extra production tool
stack is justified yet. Existing alternative DMI bridges are useful references,
but need Nordic address translation, target integration, and hardware proof.

## Source revisions and limits

| Source | Inspected revision |
| --- | --- |
| nix-nrf-dev | `795a60089fd98f44464c135af1495597e76cdedf` |
| le-audio-receiver | `012b19739802e8fc53d6e8a701fb362a17a1c209` |
| NCS v3.3.0 nrf | `ba167d9f3db4abbdc9b67887ca3ea66c64f2d956` |
| NCS v3.3.0 zephyr | `fd9204a02d52630660ce8d729945a4dd743feabf` |
| NCS v3.3.0 modules/hal/nordic | `1acb428a205bad58f3dfd4e38f2d1663bb784ba1` |
| Pinned OpenOCD | `da3920b0a52dc2d394afb222c688dac7e57acc1b` |
| Official OpenOCD upstream | `46d9b606b284888fd74632c792ef1a510b987e0a` |
| probe-rs | `50e750702126a73e22e1808dd6845af6b8625a6b` |
| pyOCD | `d1974ffdd16369148ba678478fa85886282d09b1` |
| Raspberry Pi OpenOCD rpi-common | `acff23ffd100479d6481a1155123774b79a990b9` |

SDK inspection explicitly used `/home/thomas/ncs/v3.3.0`, matching the receiver,
not the newer installed directory. No claim is made about an actual board's
silicon revision, protection state, or loaded firmware. AP routing is supported
by a Nordic DevZone clarification of preliminary documentation, not an inspected
final product-specification revision. Receiver graph coverage was stale and
missed recovery callers; live source reads supplied the evidence instead.

## Capability matrix

| Capability | Evidence | Classification |
| --- | --- | --- |
| CPUAPP/AP0 reads of shared SRAM | SDK memory map, receiver layout, OpenOCD Cortex-M memory path | Source-backed candidate; board/security state untested |
| AUX/AP1 access to VPR DEBUGIF | Nordic APB00 routing clarification and target CSW setup | Source-backed candidate; not a general SRAM aperture |
| FLPR halt/resume | MDK DMCONTROL HALTREQ/RESUMEREQ and DMSTATUS fields | Register interface defined; stock Nordic debugger target unwired |
| FLPR PC/GPR/CSR reads | ABSTRACTCMD register-access type, DATA registers, DPC CSR | Interface defined; supported command/register subset needs proof |
| FLPR single-step | DCSR STEP and single-step cause | Interface defined; no tested host workflow |
| FLPR software breakpoints | DCSR EBREAKM | Mechanism defined; patching/cache/restore behavior untested |
| FLPR hardware breakpoints/watchpoints | Trigger CSRs exist in headers | Usable count/features unknown; do not infer from declarations |
| AUX `halt` / `step` in stock OpenOCD | mem_ap target state changes and dummy registers | Not FLPR run control |
| FLPR RTT read through CPUAPP target | RTT backend follows pointers using its selected memory target | Source-supported design, requires compatible accessible firmware buffers |
| Two independent RTT control blocks at once | One global RTT instance in OpenOCD | Not supported by this stock session implementation |
| Debug-module system-bus memory access | SBCS reset declaration advertises zero address size | Not established; prefer AP0 for ordinary SRAM reads |
| Locked-device recovery | May erase nonvolatile memory | Excluded; fail without recovery |

## Silicon and SDK evidence

SDK paths below are relative to `modules/hal/nordic` at the revision above.
`MDK` abbreviates `nrfx/bsp/stable/mdk`.

- `MDK/nrf54l15_types.h:42260-42293` defines DEBUGIF DATA, DMCONTROL,
  DMSTATUS, ABSTRACTCS, ABSTRACTCMD, ABSTRACTAUTO, and program-buffer registers.
- `42383-42397` defines resume/halt requests. `42400-42412` declares DMSTATUS
  reset and version 0.13. Declared reset values are not measured live values.
- `42632-42691` describes abstract-command status and register-access command
  type. Its reset value indicates one program-buffer word and two data words.
  The `PROGBUF[16]` C array does not prove sixteen implemented program words.
- `42778-42815` describes SBCS; the declared zero address-size field is not
  evidence of working system-bus access. An enumerated command type likewise
  does not establish that the hardware implements it.
- `43731-43784` defines DCSR step/cause/EBREAKM and DPC CSR `0x7B1`. DPC is a
  CSR identifier, not a CPUAPP memory address that can be read directly.
- `nrfx/hal/nrf_vpr.h:196-208` provides DMACTIVE/NDMRESET helpers. That narrow
  HAL interface does not negate wider MDK debug fields. DMACTIVE reset,
  NDMRESET, CPURUN, and INITPC are not interchangeable with debugger halt,
  single-step, or current PC.

### Register address derivation

`MDK/nrf54l15_global.h:102-103` gives VPR bases `0x4004C000` and `0x5004C000`.
`nrf54l15_types.h:42980` places DEBUGIF at offset `0x400`.

| Register | Non-secure alias | Secure alias |
| --- | --- | --- |
| DATA0 | `0x4004C410` | `0x5004C410` |
| DMCONTROL | `0x4004C440` | `0x5004C440` |
| DMSTATUS | `0x4004C444` | `0x5004C444` |
| ABSTRACTCS | `0x4004C458` | `0x5004C458` |
| ABSTRACTCMD | `0x4004C45C` | `0x5004C45C` |
| ABSTRACTAUTO | `0x4004C460` | `0x5004C460` |

These are SDK-derived candidates, not permission to access hardware. Secure and
non-secure aliases are not necessarily both accessible. Reads of DATA/PROGBUF
can trigger commands when ABSTRACTAUTO enables auto-execution; even a debug
register sweep is not automatically passive.

### Access ports and protection

[Nordic's clarification](https://devzone.nordicsemi.com/f/nordic-q-a/118258/nrf54l-aux-ap-access-port-description-and-usage)
states that VPR debug registers are memory-mapped on APB00 and reachable via
AP0 or AP1, while AUX AP1 reaches only APB00 on AMBIX0. This is not evidence of
a zero-based DMI window or direct AP1 access to all SRAM.

The pinned OpenOCD and SDK XIAO configs set AUX CSW data-access bit with
`apcsw 0x01000000 0x01000000`. UICR state alone is insufficient: CPUAPP firmware
must open the relevant TAMPC debug signal after reset. SDK evidence includes
`MDK/system_nrf54l_approtect.h:64-101,159-166`, including
`NRF_TAMPC->PROTECT.AP[0].DBGEN.CTRL`, and
`nrf/doc/nrf/security/ap_protect.rst:671-679`.

The VPR launcher also applies security attribution:
`zephyr/drivers/misc/nordic_vpr_launcher/nordic_vpr_launcher.c:59-72`.
A failed non-secure read can indicate attribution/protection, not missing
hardware. Never respond by automatically changing UICR, recovering, or erasing.

## Host implementation gaps

### Official OpenOCD

Both inspected official configurations create Cortex-M on AP0 and `mem_ap` on
AP1. The current file changes the DAP argument from `-chain-position` to `-tap`,
not the FLPR debugger capability.

`mem_ap_halt`, `mem_ap_resume`, and `mem_ap_step` change the software target
state, not the VPR execution state. Registers are dummy ARM emulation. A
successful command or halted status on `nrf54l.aux` cannot validate FLPR halt.

The official RISC-V driver still examines JTAG DTMCS. Merely adding a RISC-V
target with `-dap` cannot supply the missing bridge. Even an upstream target
configuration using those arguments is weaker evidence than the driver path.

Sources:

- [Pinned target](https://github.com/openocd-org/openocd/blob/da3920b0a52dc2d394afb222c688dac7e57acc1b/tcl/target/nordic/nrf54l.cfg#L38-L67)
- [Current target](https://github.com/openocd-org/openocd/blob/46d9b606b284888fd74632c792ef1a510b987e0a/tcl/target/nordic/nrf54l.cfg#L38-L67)
- [Dummy mem_ap run control](https://github.com/openocd-org/openocd/blob/da3920b0a52dc2d394afb222c688dac7e57acc1b/src/target/mem_ap.c#L86-L123)
- [Dummy mem_ap registers](https://github.com/openocd-org/openocd/blob/da3920b0a52dc2d394afb222c688dac7e57acc1b/src/target/mem_ap.c#L169-L202)
- [Current RISC-V examine path](https://github.com/openocd-org/openocd/blob/46d9b606b284888fd74632c792ef1a510b987e0a/src/target/riscv/riscv.c#L2495-L2540)

### Alternative transports worth investigating

probe-rs implements `MemApDtm` with actual Arm memory transactions, originally
for RP235x. Its mapping is `DMI register * 4`, with no configurable VPR DEBUGIF
base. Nordic's documented peripheral mapping requires a base translation unless
an additional alias is proven. The Nordic target declares only Arm `main`, and
target validation rejects mixed Arm/RISC-V architectures. A FLPR-only target
is a smaller candidate than a combined debugger. Stock attachment also performs
breakpoint cleanup through halted access, so it is not an observation default.

The Raspberry Pi OpenOCD fork has a DAP-backed alternative DMI implementation.
It is a porting reference, not a verified nRF54L solution. Its debug-base handling
includes debug-module chain discovery; an arbitrary `-dbgbase` argument is not
a proven workaround for Nordic's memory map.

pyOCD has Nordic memory-access infrastructure but no inspected FLPR RISC-V
engine/bridge advantage. Its generic MEM-AP target has dummy CPU operations.
Do not introduce it merely because its target list contains nRF54L15.

Sources:

- [probe-rs memory bridge](https://github.com/probe-rs/probe-rs/blob/50e750702126a73e22e1808dd6845af6b8625a6b/probe-rs/src/architecture/riscv/dtm/mem_ap_dtm.rs)
- [probe-rs Nordic target](https://github.com/probe-rs/probe-rs/blob/50e750702126a73e22e1808dd6845af6b8625a6b/probe-rs/targets/nRF54L_Series.yaml#L22-L44)
- [Mixed-architecture validation](https://github.com/probe-rs/probe-rs/blob/50e750702126a73e22e1808dd6845af6b8625a6b/probe-rs-target/src/chip_family.rs#L300-L345)
- [probe-rs session behavior](https://github.com/probe-rs/probe-rs/blob/50e750702126a73e22e1808dd6845af6b8625a6b/probe-rs/src/session.rs)
- [Raspberry Pi fork DMI transactions](https://github.com/raspberrypi/openocd/blob/acff23ffd100479d6481a1155123774b79a990b9/src/target/riscv/riscv-013.c#L645-L670)
- [Fork debug-base discovery](https://github.com/raspberrypi/openocd/blob/acff23ffd100479d6481a1155123774b79a990b9/src/target/riscv/riscv-013.c#L854-L880)
- [pyOCD generic MEM-AP operations](https://github.com/pyocd/pyOCD/blob/d1974ffdd16369148ba678478fa85886282d09b1/pyocd/coresight/generic_mem_ap.py#L88-L137)

## FLPR RTT does not require FLPR run control

OpenOCD RTT setup captures its currently selected memory target. Select
`nrf54l.cpu` before setup to use AP0; changing the current target later does not
replace the stored RTT source.

The producer may run on FLPR if every descriptor, buffer, name, and stored
pointer is valid through that AP0 address space. OpenOCD does not translate
FLPR aliases. Host consumption writes read offsets, so both reads and permitted
bookkeeping writes must work. Firmware must define channel producer ownership,
initialization, concurrency, and restart behavior.

The singleton RTT instance permits one selected control block with several
channels. For CPUAPP and FLPR together, options include one deliberately shared
block with separate producer channels or CPUAPP export of FLPR records. Two
independent blocks are not simultaneously served by this stock instance. Do not
start a second OpenOCD process against the same probe to evade that limit.

Sources:

- [RTT target binding](https://github.com/openocd-org/openocd/blob/da3920b0a52dc2d394afb222c688dac7e57acc1b/src/rtt/tcl.c#L18-L47)
- [RTT global instance](https://github.com/openocd-org/openocd/blob/46d9b606b284888fd74632c792ef1a510b987e0a/src/rtt/rtt.c#L22-L46)
- [Pointer decoding](https://github.com/openocd-org/openocd/blob/da3920b0a52dc2d394afb222c688dac7e57acc1b/src/target/rtt.c#L58-L89)
- [Consumption and index write](https://github.com/openocd-org/openocd/blob/da3920b0a52dc2d394afb222c688dac7e57acc1b/src/target/rtt.c#L360-L420)

## Receiver evidence lifetime

Receiver source paths below refer to the pinned receiver revision above.

- `src/audio_offload.c:61-64` uses an 8 ms response deadline. Halt-induced
  timeouts are application events, not harmless debugger pauses.
- `src/audio_offload.c:553-703`, `recovery_work_fn`, first attempts a coordinated
  ring reset, then calls `flpr_runtime_restart(1500)`, reinitializes the remote
  ring state, and establishes a new epoch. Graph caller output missed this path;
  direct source is authoritative.
- `src/flpr_runtime.c:19-41` describes stop, reset, execution-SRAM copy, CRC,
  relaunch, and new-epoch acknowledgment. Its restart function does not itself
  reject an active stream. CPUAPP recovery can overwrite the state being read.
- `src/flpr_runtime.c:104-106` asserts execution SRAM at
  `0x20030000..0x20040000`; the receiver overlay assigns IPC SRAM and PCM rings.
  These are consumer addresses, not generic tool defaults.

Halting only FLPR can leave CPUAPP alive to reset rings and reload FLPR memory.
Halting only CPUAPP does not establish that FLPR or peripheral DMA stopped.
Both cases invalidate an unqualified coherent-snapshot promise. Do not silently
stop both cores as a workaround. Production evidence retention needs a
consumer-owned freeze/recovery policy and image/epoch tracking.

SDK `nrf/doc/nrf/app_dev/device_guides/nrf54l/vpr_flpr.rst:110-112` also warns
that running FLPR can increase RAM_01 access latency. Polling overhead and
debug attachment effects need measurement, not a timing-neutral assumption.

## Hardware validation blocker and bounded experiment

Hardware operations have not been authorized for this research. The loaded
firmware, silicon revision, probe firmware, protection state, and alias access
are unmeasured. This blocks a working-board claim, not the source-backed
capability decision. The following is a proposed experiment, not commands run.

**Use a test-owned fixture first. Halting FLPR on the receiver can miss audio
deadlines and cause CPUAPP recovery to destroy evidence. Provisioning and run
control each require explicit approval. Never erase, unlock, recover, or reset
automatically in response to an access failure.**

1. Record image/build identities, probe identity, silicon revision, AP IDs,
   security attributes, and allowed protection-state observations. Read only
   reviewed status registers such as DMSTATUS, DMCONTROL, ABSTRACTCS, and
   ABSTRACTAUTO. Do not sweep DATA/PROGBUF auto-execution registers.
2. Through AP0, read fixture-known shared RAM plus separate CPUAPP and FLPR
   progress counters and boot epochs. Changing FLPR counters prove execution;
   a static image dump does not. Compare exported bytes with the fixture.
3. Test FLPR-produced RTT independently. Validate pointer reachability, exact
   bytes, slow-reader loss reporting, disconnect/reconnect, and stale control
   blocks across FLPR restart. Record CPUAPP and FLPR epochs separately.
4. On a fixture with recovery disabled by design, issue a reviewed FLPR halt
   request. Require real DMSTATUS halt plus stopped FLPR progress while CPUAPP
   continues. Resume must restore progress without changing the boot epoch.
5. Verify abstract-command encoding against RISC-V debug v0.13 before sending
   it. Read DPC, DCSR, and known GPR state, requiring BUSY clear and CMDERR zero.
   Distinguish unsupported command, wrong hart state, and bus access failures.
6. Single-step a known straight-line instruction. Require debug cause, expected
   PC movement, and expected register effect; test breakpoint insert/hit/remove
   separately. Restore debug settings under the approved cleanup policy.
7. Only then assess receiver attachment with an explicit consumer recovery/freeze
   contract. A generic tool must never silently disable production recovery.

## Follow-up scope and acceptance boundaries

- **PB-002 + PB-004:** create the non-destructive shared session and minimal
  fixture. Prove actual state/epoch preservation, not merely absence of reset
  text in generated commands. Keep unreserved scratch RAM disabled.
- **PB-008:** read explicit AP0 RAM ranges with image and epoch provenance;
  distinguish frozen evidence from live non-atomic samples and incomplete reads.
- **PB-006:** bind RTT to the chosen memory target and control block explicitly.
  Support accessible FLPR-produced bytes without claiming a FLPR debugger.
  Production producer layout is a consumer responsibility.
- **Direct FLPR debugger follow-up:** first validate MMIO status and abstract
  register commands with the approved fixture. Then choose a translated DMI
  bridge and FLPR-only target integration, comparing probe-rs and the OpenOCD
  fork precedent. Scope must include protection handling, bounded command
  polling, state cleanup, and real halt/register/step/breakpoint proofs. No
  tool-stack change before this gate.
- **PB-022:** publish the distinction between memory observation and core debug,
  RTT ownership/restart rules, and production evidence-retention responsibilities.

This research does not change any public tool, pin, receiver firmware, or SDK
selection. The feature items remain responsible for hardware acceptance.
