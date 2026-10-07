# Debug tooling research

Source-backed findings behind PB-002 through PB-022. Product items own scope,
priority and acceptance. Nothing here establishes physical target behavior.
Completed PB-005 records the FLPR research result; current session behavior lives
in [the user guide](../../debug.md).

## FLPR capabilities

NCS v3.3.0 Nordic HAL revision `1acb428a205bad58f3dfd4e38f2d1663bb784ba1`
defines a memory-mapped VPR RISC-V debug module in
`nrfx/bsp/stable/mdk/nrf54l15_types.h`: DMCONTROL/DMSTATUS, abstract register
access, DPC and single-step controls. Defined fields do not prove implemented
command subsets or accessible board/security state.

The pinned OpenOCD `da3920b0a52dc2d394afb222c688dac7e57acc1b` exposes CPUAPP
Cortex-M on AP0 and AUX `mem_ap` on AP1. AUX halt/step changes software state,
not FLPR execution. Its RISC-V engine lacks the translated MEM-AP DMI bridge for
Nordic VPR. Merely adding a RISC-V target or changing the OpenOCD pin is not proof
of a working debugger. probe-rs and the Raspberry Pi OpenOCD fork provide bridge
precedents, but need Nordic address mapping, target integration and hardware tests.

Nordic's AP routing clarification permits VPR debug access through AP0/AP1;
AUX AP1 is not a general SRAM aperture. Protection and attribution can reject
an access. Do not automatically erase, unlock or change UICR to work around it.
DATA/PROGBUF reads can trigger commands through ABSTRACTAUTO, so a register sweep
is not inherently passive.

AP0 RAM observation and FLPR-produced RTT do not require FLPR run control.
Pointers and bookkeeping writes must be reachable in the selected target's
address space. OpenOCD retains one RTT control block; two producers need defined
channel ownership or an application export strategy, not competing probe owners.

## Observation and evidence limits

- OpenOCD's default GDB attach halts the target. Missing reset commands do not
  establish non-halting attachment. Work-area algorithms can overwrite RAM.
- RTT up-channel consumption writes target read offsets. The native TCP server
  accepts down-channel data; a receive-only client is not a socket security policy.
- Live multiword RAM reads are not atomic. Halting one core does not stop another
  core or peripheral DMA. Firmware owns freeze, schema and recovery policy.
- At receiver revision `012b19739802e8fc53d6e8a701fb362a17a1c209`, CPUAPP recovery
  can reset rings and reload FLPR SRAM after an 8 ms timeout. Independent-core
  halts can destroy evidence. Consumer addresses are not generic host defaults.
- DWT watchpoints observe CPU transactions, not arbitrary DMA writes. Zephyr
  thread awareness needs matching firmware metadata and ELF qualification.
- Profiling can fall back to halt/resume; semihosting traps perturb execution;
  SWO declarations do not prove board routing or probe support. Power neutrality
  and fatal-fault export require separate tests.

Physical PB-002/PB-004 acceptance remains blocked on target access. Flash byte
verification did not prove firmware execution or RTT. Probe firmware/reset
diagnosis belongs to the separate `xiao-samd11-debug-probe` project. No reset,
erase or recovery fallback belongs in observation startup.

## Pinned references

- [Nordic AP routing clarification](https://devzone.nordicsemi.com/f/nordic-q-a/118258/nrf54l-aux-ap-access-port-description-and-usage)
- [OpenOCD target and work area](https://github.com/openocd-org/openocd/blob/da3920b0a52dc2d394afb222c688dac7e57acc1b/tcl/target/nordic/nrf54l.cfg)
- [AUX dummy run control](https://github.com/openocd-org/openocd/blob/da3920b0a52dc2d394afb222c688dac7e57acc1b/src/target/mem_ap.c#L86-L123)
- [Default GDB attach](https://github.com/openocd-org/openocd/blob/da3920b0a52dc2d394afb222c688dac7e57acc1b/src/target/startup.tcl#L202-L215)
- [RTT TCP forwarding](https://github.com/openocd-org/openocd/blob/da3920b0a52dc2d394afb222c688dac7e57acc1b/src/server/rtt_server.c#L103-L187)
- [RTT target binding](https://github.com/openocd-org/openocd/blob/da3920b0a52dc2d394afb222c688dac7e57acc1b/src/rtt/tcl.c#L18-L47)
- [RTT read-index writes](https://github.com/openocd-org/openocd/blob/da3920b0a52dc2d394afb222c688dac7e57acc1b/src/target/rtt.c#L397-L403)
- [probe-rs MEM-AP bridge](https://github.com/probe-rs/probe-rs/blob/50e750702126a73e22e1808dd6845af6b8625a6b/probe-rs/src/architecture/riscv/dtm/mem_ap_dtm.rs)
- [Raspberry Pi DMI precedent](https://github.com/raspberrypi/openocd/blob/acff23ffd100479d6481a1155123774b79a990b9/src/target/riscv/riscv-013.c#L645-L670)
