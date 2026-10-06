# RTT and debug fixture verification

PB-004 fixture lives in `tests/firmware/debug-fixture`. It is not production
firmware or a DMA recorder. Host protocol tests run without hardware. Physical
acceptance requires explicit approval and a test-owned XIAO nRF54L15.

## Build only

An already provisioned NCS v3.4.1 SDK/toolchain is required. This expression
disables automatic bootstrap. It does not update or download an SDK:

```bash
nix develop --impure --expr \
  '(builtins.getFlake (toString ./.)).lib.x86_64-linux.mkNrfShell { ncsVersion = "v3.4.1"; autoBootstrap = false; }' \
  -c west build --no-sysbuild -b xiao_nrf54l15/nrf54l15/cpuapp \
  -d /tmp/opencode/pb004-build "$PWD/tests/firmware/debug-fixture"
```

Choose an existing writable build parent on another host. Keep build products
outside source control. The firmware is a CPUAPP image, not a sysbuild/FLPR
bundle. Debug-open Kconfig choices do not recover an already locked target.

If using clangd, point its compilation database at the resulting per-image
build and use the matching compiler query driver. Bare-tree header diagnostics
are not a substitute for the firmware build.

## Provisioning is separate and destructive

Flashing replaces the current application and resets the board. It can destroy
fault evidence. Use a test-owned board and obtain explicit approval. Capture
tools never provision it. Once approved, the existing recipe can program the
fixture, with reviewed absolute image and recipe paths:

```bash
openocd -f interface/cmsis-dap.cfg -c 'cmsis-dap backend usb_bulk' \
  -c 'adapter serial SERIAL' -f target/nordic/nrf54l.cfg \
  -f tcl/nrf54l_flash.tcl -c init \
  -c 'nrf54l_flash /tmp/opencode/pb004-build/zephyr/zephyr.hex' -c shutdown
```

This example assumes a simple serial/path without Tcl metacharacters. Do not
interpolate arbitrary input into raw OpenOCD commands. Stop any session owner
first. Never run recovery or erase to make a failed test pass.

## Fixture behavior

- RTT channel 0 emits `PB004 text channel\n` every 100 ms. It has no console,
  shell, logging backend, or input command loop.
- RTT channel 1 emits 128 fixed 64-byte DATA attempts at 10 ms intervals,
  followed by a SUMMARY. Whole-record nonblocking skip exposes producer loss.
  A summary retries with 50 ms sleeps until delivered; the next burst starts
  after two seconds. It reports trailing losses even if no later DATA succeeds.
- Named `pb004_text` and `pb004_binary` threads coexist with main blocked on
  `fixture_main_gate`. Zephyr debug-thread metadata is enabled.
- `fixture_ram_pattern` is 256 writable RAM bytes filled once with `i ^ 0xa5`.
  It remains unchanged, including during intrusive scenarios.
- Resolve `_SEGGER_RTT` and `fixture_*` addresses from the matching ELF. The
  harness validates expected SRAM ranges and the initialized build tag before
  configuring RTT. The full ELF SHA-256 is recorded as image provenance.
- `fixture_boot` is a validated `.noinit` warm-reset counter, not a globally
  unique boot identity. `fixture_retained_valid` records whether its previous
  state validated. Power loss, RAM loss, a firmware load, or counter wrap can
  defeat continuity detection. Reset-cause flags may accumulate. Neither
  uptime nor this counter proves absence of all reset types.

### Wire format

All integers are little-endian. `src/wire.h` is the serializer used both by the
firmware and the host C encoder in CI.

| Offset | Contents |
| --- | --- |
| 0..3 | ASCII `PB04` |
| 4 | Version 1 |
| 5 | Kind 1 DATA or 2 SUMMARY |
| 6..7 | Length 64 |
| 8..11 | DATA attempt sequence, or next attempt number for SUMMARY |
| 12..15 | Cumulative dropped DATA attempts before this record |
| 16..19 | Warm-reset counter |
| 20..23 | Uptime milliseconds modulo 2^32 |
| 24..27 | Total attempts, sequence+1 for DATA, sequence for SUMMARY |
| 28..31 | Source/config build tag, not a full image hash |
| 32..55 | Byte `i` equals `(sequence + 17*i) & 255` |
| 56..59 | Unsigned sum of bytes 0..55 |
| 60..63 | End marker `0x0df00d04` |

Summary retries do not increment DATA attempt counters. Decoder validates
payload/checksum, boot/build continuity, and sequence gaps against drop counts.
It rejects incomplete trailing records and captures without DATA followed by
SUMMARY. Leading history is unknown when attaching mid-stream. A second reader
or a prior partially consumed stream can cause alignment/loss failures rather
than silent success. This decoder is only for the fixture protocol.

## Approved observation and evidence collection

The following steps access hardware. Obtain approval first. The harness reads
RAM and DHCSR, configures RTT, and permits RTT read-offset writes. DHCSR reads
clear sticky status bits. It never halts, resumes, resets, flashes, or sends RTT
down-channel data. It requires a dedicated session without other RTT owners.

In terminal 1, start the approved observation session and leave it running:

```bash
nix develop .#hardware-tests -c nix-nrf session start \
  --serial SERIAL --tcl-port 0 > /tmp/opencode/pb004-session.json
```

In terminal 2, after readiness JSON is present:

```bash
nix develop .#hardware-tests -c python3 tests/hardware/debug/check.py \
  --approve-observe --session /tmp/opencode/pb004-session.json \
  --elf /tmp/opencode/pb004-build/zephyr/zephyr.elf \
  --output /tmp/opencode/pb004-evidence
```

Output must be a new directory. It retains raw channel files, Tcl commands and
responses, matching ELF hash/symbols, build `.config`, CMake cache, session/probe
serial, OpenOCD version, before/after state, and `result.json`. Missing provenance,
bad data, disconnect, or incomplete capture fails rather than marking success.
Record board revision and probe firmware separately in the hardware test notes;
the harness cannot infer them from a serial string.

Use `--stall-ms 600` with another fresh output directory to pause RTT polling
at the start of a new burst and require observable producer drops. Use
`--scenario snapshot --expect-state halted` only when the fixture was already
halted through a separately approved debug operation. Snapshot mode does not
change execution state or configure RTT.

For attach/detach acceptance, record a successful snapshot, stop the owner,
restart observation without target reset, and run another snapshot with
`--baseline /path/to/previous/result.json`. Repeat for running and halted
targets. This compares pattern, build, warm-reset count, and expected state;
independently monitor power/reset if absence of all reset types is required.
An individual capture result does not prove the whole acceptance matrix.

## Explicit intrusive scenarios

These operations write target state, interrupt execution, or trigger fatal
handling. They require separate approval. The capture harness never invokes
them. Start `nix-nrf session start --serial SERIAL --mode debug` and use
matching GDB/ELF symbols. Enable `--tcl-port 0` when using the capture harness.

- Hardware breakpoint at `fixture_breakpoint_site`, or hardware watchpoint on
  `fixture_watch_word`: set `fixture_action = 1` and continue. The text thread
  clears the request and increments that word once. Inspect the stop context,
  then explicitly remove the breakpoint/watchpoint and choose whether to resume.
- Set `fixture_action = 2` and continue to trigger `k_panic()`. This is a kernel
  panic scenario, not a hardware HardFault claim. Inspect registers/backtrace.
  Recovery from this scenario is a separately approved reset/provisioning step.
- With Zephyr awareness configured in OpenOCD, inspect both named threads and
  blocked main. Metadata availability alone does not validate decoded frames.
- Combined RTT/GDB: start one debug session with Tcl, run the capture harness
  through that Tcl endpoint, and connect GDB to the same server. A halt may make
  capture timeout; report that honestly. Do not launch another OpenOCD process.

Physical tests also cover inaccessible/locked target failure, unplug/replug,
second-owner refusal, and unavailable ports. Do not deliberately lock a device
merely to exercise a failure case. Record unavailable tests as unverified.
