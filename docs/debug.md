# Shared OpenOCD sessions

`nix-nrf session` owns one foreground OpenOCD process for an explicitly selected
CMSIS-DAP v2 probe and nRF54L15 CPUAPP. It is independent of the selected SDK
backend and never bootstraps, builds, flashes, unlocks, or recovers a device.
FLPR run control is not provided. See [product research](product/research/debug-tooling.md#flpr-capabilities).

Host lifecycle and actual OpenOCD Tcl transport are tested without hardware.
Running/halted target preservation and combined physical RTT/GDB operation
still require the [approved fixture procedure](../tests/hardware/debug/README.md).
Do not treat these as validated production-board workflows yet.

## Observation

Starting a session opens the probe and examines the target. Obtain approval
before executing it against hardware. `status` only reads local ownership
metadata and does not open the probe.

```bash
nix-nrf session start --serial SERIAL
```

Default observation disables GDB, Tcl, and Telnet listeners, reserves no scratch
RAM, and turns off OpenOCD background target polling before examination. That
polling can otherwise halt a CPU in double-fault lockup. The launcher never
deliberately halts, resumes, or resets the target in observation mode.

This is not passive attachment: OpenOCD examination enables/configures debug
hardware and can clear existing breakpoint/trace settings. Debug mode can
change sleep and timing behavior. Another debugger must not own this probe.
The launcher deliberately does not report cached OpenOCD `curstate` as a fresh
hardware measurement; metadata uses `run_state: "not-sampled"`.

## Explicit endpoints and sharing

Raw Tcl permits arbitrary target commands. It is disabled unless requested:

```bash
nix-nrf session start --serial SERIAL --tcl-port 0 > session.json
```

Port `0` requests an available port. A numbered port requests exactly that port.
Once target examination, nRF54L15 part identification, and requested listeners
succeed, stdout emits one JSON readiness object. OpenOCD diagnostics go to
stderr. The process stays in the foreground; it does not exit after readiness.
In another terminal:

```bash
nix-nrf session status --serial SERIAL
```

Schema 1 metadata includes session `id`, serial, mode, `nrf54l.cpu` target,
loopback host, nullable `tcl_port`/`gdb_port`, owner/child PIDs, OpenOCD executable,
adapter speed, start time, and manifest path. IDs identify host sessions, not
target boots. Clients use these endpoints rather than opening a second probe
process. Tcl clients can compare `set nix_nrf_session_id` with metadata `id`
before target access to reject a stale file or reused port. The current fixture
harness demonstrates RTT over that same server;
the general-purpose capture command remains PB-006 work.

All endpoints bind `127.0.0.1`. They are unauthenticated target-control interfaces,
not safe remote services. Local users able to connect can control the target.
Do not expose ports or use raw endpoints on an untrusted multi-user host.
Explicit raw Tcl can defeat observation safeguards; the launcher is not a
command-filtering security boundary. Native RTT sockets are bidirectional even
when a particular capture client never transmits.

## Intrusive debug mode

The following explicitly enables run control. Connecting GDB halts CPUAPP;
disconnecting, including unexpected disconnect, leaves its state unchanged.
The launcher does not resume it on shutdown. GDB commands can themselves reset
or write firmware, so only use reviewed commands with permission.

```bash
nix-nrf session start --serial SERIAL --mode debug --gdb-port 3333 --tcl-port 0
```

GDB defaults to port 3333 in debug mode; AUX GDB and Telnet stay disabled.
Debug mode retains normal OpenOCD polling. It does not promise GDB non-stop
debugging. CPUAPP halt can stall RTT production and affect FLPR recovery.
Loading an ELF for symbols is separate from loading it onto the target.

## Ownership and failure

- Sessions use a same-user advisory lock keyed by the complete serial. An
  explicit serial must match exactly one accessible CMSIS-DAP v2 candidate in
  doctor output. There is no automatic probe selection or HID fallback.
- State lives in `$XDG_RUNTIME_DIR/nix-nrf`, or the private
  `$TMPDIR/nix-nrf-<uid>` directory when XDG runtime state is unavailable.
  `--runtime-dir` chooses another private directory; every cooperating owner
  must use the same directory. Locks do not police unrelated programs or users.
- Startup has a configurable `--startup-timeout`, default 15 seconds. Failure
  never triggers a recovery or reset attempt. Requested ports must bind before
  readiness. Failed identification, protection, and permissions remain errors.
- Ctrl-C or SIGTERM stops only the owned child with SIGTERM, then kills it if
  it fails to exit within three seconds. It removes published session metadata
  after child exit. Exit 130 means owner cancellation; errors use exit 1;
  invalid CLI arguments use exit 2.
- Lock files are retained intentionally to avoid inode-replacement races.
  JSON alone never establishes liveness: `status` requires a held lock.
  Abrupt SIGKILL of the owner cannot run cleanup; the child inherits the lock
  while alive. Investigate that process manually rather than launching another
  owner or deleting a held lock file. Stale unlocked metadata is not an active
  session and is replaced on the next start.
- There is no remote `stop` command or automatic PID-based killing. A consumer
  that merely connects must not shut down someone else's session.

`--speed` controls SWD kHz, default 1000, range 1 through 10000. A higher value
is not a promise of board/probe support. Fixture/probe firmware revisions and
physical access behavior must be recorded during validation.

## Explicit USB reset, not automatic recovery

For USB connection problems, the host's optional `usbreset` tool can select a
device by exact serial. Stop probe/serial owners first and obtain approval:

```bash
usbreset SN:SERIAL
```

This is a logical USB reset, not a guarantee of target reset or power removal.
It is deliberately outside `session start` and is not a capture fallback.
Reliable remote power cycling requires verified per-port switching. Target
reset can instead use reset-capable probe firmware or a separate controlled
reset line. A board reset circuit does not prove its probe firmware exposes it.
PB-002/PB-004 retain the physical-access blocker; probe-firmware diagnosis
belongs to the separate `xiao-samd11-debug-probe` project. Do not cycle an entire USB controller/hub,
assume a stale bus/device number still identifies the board, or run mass erase
because a logical reset failed.
