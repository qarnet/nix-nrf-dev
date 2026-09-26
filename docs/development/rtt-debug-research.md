# RTT and debug tooling research

Research recorded 2026-09-25. This document preserves requirements discussions
and sources behind PB-001 through PB-022. Task files own current scope and
priority; the coverage map below is not a status tracker. This is not an implementation plan
or a claim of hardware validation. No SDK installation, flashing, recovery, or
probe access was performed during research.

## Agreed scope

- Move the **nrfutil backend's tested baseline** from NCS v3.3.0 to v3.4.1.
  Leave the experimental west backend, its metadata, toolchain assets, and
  baseline tests unchanged. Do not globally replace version strings.
- Provide reusable RTT and debug tooling for the Seeed XIAO nRF54L15 with
  CMSIS-DAP, without requiring a J-Link probe.
- This repository owns host tooling and small verification firmware fixtures.
  The consuming firmware project owns its production DMA fault recorder,
  record schema, fault triggers, and timing constraints.
- Prioritize capabilities that help le-audio-receiver. Read-only inspection
  of its actual offload and debug workflows informed the initial priorities;
  see the receiver evidence below.
- Investigate FLPR debugging at high priority. Important application workflows
  run there; do not defer it merely because the current OpenOCD configuration
  exposes only AUX memory access.
- Keep profiling and SWO/trace as later investigations, not omitted ideas.
- Initially exclude interactive RTT consoles, down-channel commands, automatic
  flashing, and automatic device recovery from the capture workflow.

## Repository evidence

- `nix/flake/dev-shells.nix` selects v3.3.0 for default nrfutil and clean-env
  shells. `tests/clean-room/run.sh`, `tests/hardware/run.sh`, active examples,
  and baseline documentation need a coordinated nrfutil-only update.
- `nix/backends/west/versions.nix` explicitly supports v3.3.0 with Zephyr SDK
  0.17.0. `nix/flake/components.nix`, the exported
  `west-zephyr-sdk-v3_3_0` package, and west tests are intentionally separate.
- `nix/backends/nrfutil/shell.nix` scopes Nordic's toolchain environment to the
  west subprocess. It deliberately does not globally load Nordic environment
  variables into the user's shell. Preserve this isolation when adding tools.
- `nix/commands/default.nix` exposes versions, probes, bootstrap, and doctor.
  There is no dedicated RTT or debugger session command.
- `nix/hardware/openocd.nix` pins OpenOCD commit
  `da3920b0a52dc2d394afb222c688dac7e57acc1b`.
- `docs/hardware.md` and `tests/hardware/preflight_xiao.py` cover explicit
  CMSIS-DAP v2 bulk USB access. Doctor inspects access without opening the
  probe; probes starts OpenOCD for target identification.
- `tcl/nrf54l_flash.tcl` resets, enables RRAM writes, loads/verifies, and runs.
  It must not be reused as the lifecycle of an observation session.
- Existing hardware tests prove programmed bytes, not FLPR execution, IPC,
  heartbeat, or debugging. See `tests/hardware/README.md`.
- `docs/development/roadmap.md` already proposes RTT, GDB attach guidance, and
  a serial-console helper. Reconcile that entry when backlog items replace it.

## SDK baseline findings

Official NCS v3.4.1 release notes identify Zephyr 4.4.2, Mbed TLS 4.1.1, and
TF-M 2.3.1, with five-year LTS for the v3.4 branch. The tagged Linux tools file
specifies Zephyr SDK 1.0.1, Python 3.12.4, CMake 4.2.1, and Ninja 1.13.2.
These are release metadata, not versions verified in an installed local bundle.

Research found a metadata discrepancy: tools YAML lists west 1.4.0 while
requirements-fixed.txt pins west 1.5.0. Resolve selected bundle behavior during
baseline validation rather than assuming either description is the executable.
The reported Linux toolchain checksum is `8285d8ad56`; verify it through the
selected sdk-manager installation before relying on it in a test contract.

The nrfutil backend accepts explicit releases independently of west metadata.
The initializer resolves `latest` dynamically; it is not a hard-coded v3.3.0
default. The nix-nrf-dev project release version remains independent of NCS.
Historical changelog entries and version-selection fixtures need not change.

Acceptance should include clean nrfutil provisioning/environment checks and
representative nRF5340 and nRF54L15 builds, while retaining west checks at their
existing baseline. Installation and hardware validation require approval.

Sources:

- <https://github.com/nrfconnect/sdk-nrf/releases/tag/v3.4.1>
- <https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/doc/nrf/releases_and_maturity/releases/release-notes-3.4.1.rst>
- <https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/scripts/tools-versions-linux.yml>
- <https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/scripts/requirements-fixed.txt>

## Recommended host capabilities

### Shared OpenOCD sessions

Use one process owning the selected CMSIS-DAP probe. RTT, GDB, and optional Tcl
clients share that process rather than competing for USB access. Target state
is shared too: a GDB halt affects firmware producing RTT.

Expose explicit probe selection, application-core target, configurable adapter
speed and ports, session diagnostics, and predictable cleanup. Fail on ambiguous
probe selection. Bind endpoints to loopback and disable unused services. These
are target-control interfaces, not authenticated remote-debug services.

Separate observation from intrusive debugging:

- Observation permits RTT bookkeeping and explicit memory reads, but no
  deliberate halt, resume, reset, erase, flash, or unlock. Disable GDB by default.
- Debug mode explicitly permits GDB run control and defines halt-on-attach and
  disconnect behavior. Do not promise GDB non-stop mode; OpenOCD lacks it.

Pinned OpenOCD installs `gdb-attach "halt 1000"` by default. An empty override
before default handlers are installed can be treated as missing. Any future
live-GDB profile must handle server events and GDB interrupt-on-connect, not
just omit a reset command.

The pinned nRF54L target reserves a 16 KiB work area at `0x20000000`, with no
backup. Declaration does not itself overwrite memory, but helper algorithms
may use it. Disable work-area allocation for observation, or use explicitly
reserved RAM in profiles that need target algorithms.

### RTT capture

RTT works through debug memory access and does not require a J-Link. Use the
already pinned OpenOCD as the first supported transport, not three probe stacks.

Provide channel discovery, explicit channel selection, binary-safe file/stdout
capture, optional text display, bounded control-block search, and matching ELF
symbol lookup where possible. Keep tool diagnostics separate from payload.
Report missing control blocks, inaccessible memory, probe contention, channel
errors, disconnect, and output-write failure. Define restart/reconnect behavior
without resetting the target or silently joining unrelated boot sessions.

OpenOCD RTT TCP is bidirectional and has no receive-only server switch in the
pinned implementation. Our capture client must not read stdin or send payloads.
Do not advertise the underlying socket as enforcing receive-only access. A
strict enforcement boundary would need a proxy or server change.

Consuming an up-channel writes its read offset in target RAM. Thus application
receive-only is not literal target-memory read-only. Debug setup also writes
debug registers. No recovery is allowed: locked devices must fail without
erasing firmware or evidence.

The pinned RTT implementation documents a single-target limitation and does
not respect channel buffer flags. Start with application-core RTT; investigate
multi-core ownership and FLPR-produced buffers rather than assuming support.

### Scoped GDB and offline tools

Expose the selected toolchain's GDB and useful binutils: addr2line, nm, objdump,
readelf, and size. Preserve arguments, exit codes, and environment isolation.
Do not silently fall back to an unrelated host debugger. Missing tools should
produce actionable errors without an unrequested installation.

Provide ELF/symbol loading and explicit attach guidance. Loading symbols must
not imply loading firmware onto the target. Keep advanced commands accessible
through GDB monitor and optional Tcl rather than wrapping every OpenOCD command.

The west SDK packaging currently documents plain GDB and an unpatched gdb-py
ABI limitation. Do not promise Python-based debugger extensions across both
backends without runtime verification. No west SDK upgrade is part of this work.

### Memory snapshots and fault inspection

Provide explicit address/length binary export using OpenOCD memory access,
including target state, address range, and supplied ELF/build identity metadata.
Never infer application recorder format or decoder rules.

Live multiword reads are not atomic snapshots. CPU or DMA writers may change
memory during the read. Halting the CPU does not prove peripheral writers have
stopped. Consistency requires firmware cooperation or control of every writer.
Avoid arbitrary peripheral scans: register reads can have side effects.

Support documented register inspection, backtraces, and Cortex-M fault catch in
intrusive debug mode. Fault catch can preserve earlier failure context but
changes execution. Define cleanup for debug settings.

Pinned vector-catch implementation accepts `hard_err`, `int_err`, `bus_err`,
`state_err`, `chk_err`, `nocp_err`, `mm_err`, `reset`, `all`, and `none`. The
manual's `irq_err` spelling is stale; implementation is authoritative.
`cortex_m maskisr auto|on|off|steponly` exists, requires halt, and affects interrupt
behavior during stepping. Its auto mode may need a spare hardware breakpoint.

### Breakpoints, watchpoints, and Zephyr awareness

Provide GDB/OpenOCD recipes for hardware breakpoints and read/write/access
watchpoints. Report comparator exhaustion, unsupported ranges, and alignment
errors. Cortex-M DWT watchpoints observe CPU transactions, not arbitrary
peripheral DMA writes. They can catch CPU pointer/register updates, not replace
a DMA flight recorder or external timing measurement.

Offer optional Zephyr RTOS awareness. OpenOCD has `-rtos Zephyr` support;
firmware must include debug-thread metadata and the host needs matching ELF.
Verify thread listing and backtraces on real test firmware. Saved floating-point
and security contexts need qualification before broad support claims.

Pinned source expects `_kernel`, `_kernel_thread_info_offsets`, and
`_kernel_thread_info_size_t_size`, with optional
`_kernel_thread_info_num_offsets`. Older documented `_kernel_openocd_*` names
are stale. Verify required Kconfig against the selected SDK during refinement.

## FLPR investigation: high priority, not deferred

The pinned target config creates `nrf54l.cpu` as Cortex-M on AP0 and
`nrf54l.aux` as a memory-access target on AP1. AUX is not a RISC-V run-control
target. Existing FLPR flash verification establishes neither stepping nor
register access.

Investigate against le-audio-receiver's actual FLPR responsibilities:

- Silicon debug architecture, access-port capabilities, and security settings.
- Whether a supported OpenOCD configuration, newer revision, or another
  CMSIS-DAP-capable stack provides FLPR run control, registers, or breakpoints.
- Whether FLPR-owned RTT buffers can be read through an accessible RAM alias,
  and how the host selects the correct ELF/address space.
- Shared-RAM snapshots, counters, IPC breadcrumbs, and application-core export
  as alternatives if direct run control is unavailable.
- Effects of halting one core while the other continues, including DMA and IPC.
- Whether a second tool stack is justified by a demonstrated capability gap.

Return an evidence-backed capability matrix and smallest hardware proof before
deciding which implementation items to create. Do not label FLPR unsupported
solely from the current OpenOCD script.

## Other observability and later work

- **UART:** retain the onboard USB bridge as a logging fallback; consider a
  serial-console helper and document conflicts with firmware UART ownership.
  Board docs inspected during SDK research identify SAMD11 CMSIS-DAP plus CDC
  serial, console UART20 on P1.09/P1.08 and header UART21 on P2.08/P2.07. Recheck
  board revision and selected SDK before publishing wiring instructions.
- **Native USB:** nRF54L15 has no native USB peripheral. The XIAO connector's
  bridge does not establish native USB CDC firmware support.
- **GPIO timing markers:** useful with a logic analyzer for DMA/IRQ deadlines.
  Measure instrumentation overhead. This is primarily firmware guidance, not
  a new OpenOCD transport.
- **BLE telemetry:** useful while firmware/radio remain healthy; poor primary
  fatal-fault path and may perturb LE Audio workloads. No implementation agreed.
- **Semihosting:** optional debug/test I/O documentation. Cortex-M BKPT 0xAB
  traps require debugger service and perturb execution; not continuous logging.
- **Profiling:** later research. Pinned Cortex-M profiler samples DWT_PCSR but
  falls back to repeated halt/resume if unavailable. It may resume an initially
  halted CPU. Never advertise as non-intrusive without capability validation.
- **SWO/ITM/trace:** later board/probe feasibility investigation. Local SDK
  research found HAS_SWO selection, but that does not prove XIAO pin routing,
  SAMD11 firmware support, or a usable capture path. Old NCS 3.0.2 limitations
  must not become blanket claims about newer SDKs.
- **Coredumps/reset-retained records:** firmware-owned evidence mechanisms;
  generic host export and symbolication can assist. Power-loss persistence is
  separate from RAM retention.
- **Power:** debugger attachment can change low-power behavior. Validate battery
  operation separately from attached observation; do not claim power neutrality.

Other tool stacks were researched, not selected: pyOCD 0.42.0 has nRF54L15
support but its RTT command resumes the target, and automatic unlock defaults
need containment; probe-rs has an nRF54L15 target definition but that alone is
not XIAO hardware validation. Revisit only for a demonstrated OpenOCD gap.

## Firmware recorder evaluation, retained as consumer guidance

Original request: "Read-only up-channel capture is enough initially.
Interactive console, down-channel commands, and automatic flashing can wait.
Firmware side, I would use small fixed-size RAM records, freeze on first fault,
then drain over RTT. No formatted logging inside sensitive DMA-pointer update
sequence. Any dropped records must be detectable."

The direction is sound, with the following qualifications. These are not host
tool implementation requirements unless needed for a generic test fixture.

- Record bounded binary data into fixed-capacity RAM without allocation,
  formatting, blocking locks, or transport calls in the sensitive sequence.
  Measure maximum write overhead rather than accepting "small" as a criterion.
- Define thread/ISR concurrency and committed-record markers so interrupted
  writes are identifiable. Capture schema/build/session identity and relevant
  pointer/state values.
- Freeze the first qualifying fault's history and metadata; later faults must
  not overwrite it. Freezing the recorder need not halt the CPU.
- A surviving worker can export a recoverable fault's frozen snapshot. A fatal
  halt cannot rely on that worker. Host RAM extraction or separately validated
  reset-retained export is needed. Bytes already in RTT may remain readable
  after a CPU halt.
- Sequence gaps alone miss trailing loss. Retain loss counters and expected
  ranges/counts; distinguish rolling-history overwrite, recorder overflow,
  transport loss, and host persistence failure. Include framing/completeness
  checks. RTT read-offset advancement does not acknowledge durable disk storage.
- Prefer whole-record skip to trim for nonblocking streams. A frozen immutable
  snapshot can instead retry export outside the timing-sensitive producer.
- RAM-only evidence disappears on power loss; `.noinit` is not a retention
  guarantee. Fatal hooks may run after logging/coredump activity, so first-fault
  timing requires deliberate firmware placement.

## Verification scope

Small test firmware should emit known text and numbered binary records, expose
a known RAM pattern, retain boot/session identity, and have multiple threads.
Separate explicit intrusive tests can exercise faults and watchpoints. It must
not grow into a production recorder framework.

Public-boundary acceptance candidates:

1. Observe attach/detach preserves running or halted state without reset.
2. Capture preserves exact binary bytes and separates diagnostics.
3. Reader stalls, disconnects, and file-write failures report declared loss or
   incomplete capture; the fixture supplies sequence/completeness information.
4. The capture client sends no down-channel application data.
5. RTT and GDB share one server/probe, with explicit run-control behavior.
6. Frozen known RAM exports byte-for-byte with address/state metadata.
7. Debug mode proves breakpoints, CPU watchpoints, backtraces, and fault catch.
8. Zephyr awareness lists the fixture's real threads and useful stack frames.
9. GDB/binutils use the selected toolchain and preserve parent environment.
10. Locked/inaccessible devices fail without recovery or automatic flashing.
11. FLPR capability tests follow research findings rather than assuming current
    flash tests cover execution or debugging.

Use subprocess/protocol tests for host behavior and explicit approved hardware
tests for target behavior. Checking generated OpenOCD arguments alone does not
prove non-halting attachment. Keep destructive or intrusive tests out of normal
capture startup.

## Pinned OpenOCD sources

These references describe the repository's actual pinned revision, not latest
manual behavior. Source support still requires XIAO hardware validation.

- Target and work area:
  <https://github.com/openocd-org/openocd/blob/da3920b0a52dc2d394afb222c688dac7e57acc1b/tcl/target/nordic/nrf54l.cfg>
- Default GDB attach handler:
  <https://github.com/openocd-org/openocd/blob/da3920b0a52dc2d394afb222c688dac7e57acc1b/src/target/startup.tcl#L202-L215>
- RTT TCP input/down-channel forwarding:
  <https://github.com/openocd-org/openocd/blob/da3920b0a52dc2d394afb222c688dac7e57acc1b/src/server/rtt_server.c#L103-L187>
- RTT host read-position writes:
  <https://github.com/openocd-org/openocd/blob/da3920b0a52dc2d394afb222c688dac7e57acc1b/src/target/rtt.c#L397-L403>
- Watchpoints:
  <https://github.com/openocd-org/openocd/blob/da3920b0a52dc2d394afb222c688dac7e57acc1b/src/target/cortex_m.c#L2092-L2247>
- Profiling and fallback:
  <https://github.com/openocd-org/openocd/blob/da3920b0a52dc2d394afb222c688dac7e57acc1b/src/target/cortex_m.c#L2370-L2429>
  <https://github.com/openocd-org/openocd/blob/da3920b0a52dc2d394afb222c688dac7e57acc1b/src/target/target.c#L2343-L2384>
- Vector catch and interrupt masking:
  <https://github.com/openocd-org/openocd/blob/da3920b0a52dc2d394afb222c688dac7e57acc1b/src/target/cortex_m.c#L3223-L3346>
- Zephyr symbol discovery:
  <https://github.com/openocd-org/openocd/blob/da3920b0a52dc2d394afb222c688dac7e57acc1b/src/rtos/zephyr.c#L334-L392>
- Semihosting:
  <https://github.com/openocd-org/openocd/blob/da3920b0a52dc2d394afb222c688dac7e57acc1b/src/target/arm_semihosting.c#L265-L282>
- General command reference:
  <https://openocd.org/doc/html/General-Commands.html>

Other references:

- <https://wiki.seeedstudio.com/xiao_nrf54l15_sense_getting_started/>
- <https://devzone.nordicsemi.com/f/nordic-q-a/123902/flashing-custom-nrf54l15-usb-module-and-dfu-support>
- <https://github.com/pyocd/pyOCD/blob/v0.42.0/pyocd/subcommands/rtt_cmd.py>
- <https://github.com/pyocd/pyOCD/blob/v0.42.0/pyocd/core/options.py>
- <https://github.com/probe-rs/probe-rs/blob/master/probe-rs/targets/nRF54L_Series.yaml>

SDK-local research used a discovered v3.3.4 tree rather than the configured
v3.3.0 reference. Treat board/Kconfig observations from that tree as supporting
research, not proof of v3.4.1 behavior. Verify against the selected SDK when
refining firmware fixtures. Moving external references also need a revision pin
before becoming implementation evidence.

## Backlog migration

Created through the pinned CLI as Backlog items, not Ready implementation
specifications. Safety and public-boundary tests are part of each relevant
item's acceptance. Sizes and implementation-shaping questions remain for
refinement. No SDK or hardware changes accompanied item creation.

| Research topic | Item |
| --- | --- |
| nrfutil-only v3.4.1 baseline | PB-001 |
| Shared observation/debug sessions and safety boundaries | PB-002 |
| Scoped GDB and offline binutils | PB-003 |
| Small verification firmware and approved hardware harness | PB-004 |
| FLPR capabilities and receiver offload evidence | PB-005 |
| Receive-only text/binary RTT capture | PB-006 |
| Explicit GDB attach alongside RTT | PB-007 |
| RAM exports and capture metadata | PB-008 |
| Fault inspection and vector catch | PB-009 |
| Hardware breakpoints, CPU watchpoints, interrupt stepping | PB-010 |
| Zephyr thread awareness | PB-011 |
| UART fallback and bounded serial helper | PB-012 |
| GPIO and logic-analyzer timing guidance | PB-013 |
| Optional semihosting | PB-014 |
| Later profiling research | PB-015 |
| Later SWO/ITM/trace feasibility | PB-016 |
| Coredumps and reset-retained evidence, host-side research | PB-017 |
| Sleep/battery and debugger-attachment qualification | PB-018 |
| Later BLE telemetry evaluation | PB-019 |
| Later interactive RTT/down-channel evaluation | PB-020 |
| Later explicit provision-and-debug workflow evaluation | PB-021 |
| Consumer adoption and firmware-recorder guidance | PB-022 |

The tasks live in `docs/product/backlog/tasks/`. Read an item with
`nix develop .#product -c backlog task PB-005 --plain`; use `backlog doctor`
through the same shell to validate IDs and dependencies. Unrelated roadmap
proposals were not silently converted or reprioritized.

### Receiver evidence used for initial priorities

Read-only inspection used le-audio-receiver revision
`012b19739802e8fc53d6e8a701fb362a17a1c209` on clean local main. No receiver
files, firmware, or hardware were changed. Paths below are relative to that
repository, not nix-nrf-dev.

- `src/audio_offload.c:5-37,61-103` routes decoded PCM through FLPR ASRC,
  uses an 8 ms deadline, and owns a dedicated recovery queue and submit mutex.
  Its RTT statistics mean round-trip time, not SEGGER capture support.
- `src/flpr_runtime.c:5-41,89-108` stops/reloads/restarts FLPR and checks a
  new handshake epoch without rebooting CPUAPP. An attached debugger can
  interact with this recovery and overwrite evidence if lifecycle is ignored.
- `boards/nrf54l15dk_nrf54l15_cpuapp.overlay:193-220` and `src/flpr_ring.h`
  establish shared-memory use. PCM rings occupy `0x2002C000`/`0x2002E000`;
  FLPR execution uses `0x20030000..0x20040000`. These are consumer-specific
  evidence, not generic host address defaults or coherent-snapshot guarantees.
- `prj.conf:78-95` enables UART shell; `src/flpr/prj.conf:9-24` has no console.
  `scripts/hil/serial_io.py` already owns raw UART evidence and connection
  lifecycle, so a new generic UART helper is useful but not an immediate gap.
- `boards/nrf54l15dk_nrf54l15_cpuapp.conf:104-114` documents tight stack/RAM
  budgets. Thread-aware debugging and matching-image inspection directly help
  recovery/workqueue diagnosis.
- `src/audio_timing_nrf54.c:8-25` distinguishes DMA-buffer FRAMESTART cadence
  from LRCK. The overlay already assigns D3/P1.7 to MCK. GPIO timing guidance
  must check pin ownership and event semantics rather than assume spare pins.
- `PLANNED_FEATURES.md:90-108` describes resume-pop investigation, but does
  not establish power management as its cause. Attached/detached testing and
  later profiling must not turn an unconfirmed explanation into a requirement.
- `flake.nix:24-30` pins NCS v3.3.0; `scripts/bin/fw-flash-54l15:107` uses the
  older `nrf-probes` command. Consumer integration must preserve deliberate SDK
  pins and explain current `nix-nrf probes`, not silently migrate production.

Initial priorities are P1 for direct receiver tooling, FLPR research, test
fixtures, and integration guidance; P2 for the requested nrfutil baseline,
UART convenience, semihosting, and sleep qualification; P3 for conditional
later capabilities. No P0 blocker was established. Required safety behavior
remains inside P1 acceptance even when broader research is lower priority.
