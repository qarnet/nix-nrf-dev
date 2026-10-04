#!/usr/bin/env python3
"""Approval-gated fixture capture via an existing session, never provisioning."""

import argparse
import hashlib
import json
from pathlib import Path
import selectors
import socket
import struct
import sys
import time
from typing import Any

from wire import Decoder, WireError


class CheckError(Exception):
    pass


class Rpc:
    def __init__(self, port, log):
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=3)
        self.sock.settimeout(3)
        self.log = log
        self.pending = b""
        self.log_failure = None

    def call(self, command):
        # All caller commands use fixed names and validated numeric addresses.
        frame = f'set rc [catch {{{command}}} result]; format "%d\\n%s" $rc $result'
        self.sock.settimeout(3)
        self.sock.sendall(frame.encode() + b"\x1a")
        deadline = time.monotonic() + 3
        while b"\x1a" not in self.pending:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise CheckError("OpenOCD Tcl response deadline exceeded")
            self.sock.settimeout(remaining)
            chunk = self.sock.recv(8192)
            if not chunk:
                raise CheckError("OpenOCD Tcl connection closed")
            self.pending += chunk
            if len(self.pending) > 1024 * 1024:
                raise CheckError("OpenOCD Tcl response too large")
        raw, self.pending = self.pending.split(b"\x1a", 1)
        self.write_log(
            json.dumps(
                dict(
                    time=time.time(),
                    command=command,
                    response=raw.decode(errors="replace"),
                )
            )
            + "\n"
        )
        code, separator, result = raw.decode().partition("\n")
        if not separator or code != "0":
            raise CheckError(f"OpenOCD command failed: {command}: {raw!r}")
        return result

    def write_log(self, text):
        # A response-log failure must not hide a completed target operation or
        # prevent resource cleanup. Main reports evidence failure, never pass.
        try:
            self.log.write(text)
            self.log.flush()
        except OSError as exc:
            self.log_failure = str(exc)

    def words(self, address, width, count):
        result = self.call(f"nrf54l.cpu read_memory {address:#x} {width} {count}")
        values = [int(value, 0) for value in result.split()]
        if len(values) != count:
            raise CheckError("short memory read")
        return values

    def close(self):
        self.sock.close()


def elf_symbols(path):
    from elftools.common.exceptions import ELFError

    try:
        return read_elf_symbols(path)
    except (ELFError, struct.error, IndexError, KeyError, TypeError) as exc:
        raise CheckError(f"invalid fixture ELF: {exc}") from exc


def read_elf_symbols(path):
    # Supplied by Zephyr's installed Python dependencies, or the test shell.
    from elftools.elf.elffile import ELFFile

    with path.open("rb") as stream:
        elf = ELFFile(stream)
        if elf.elfclass != 32 or not elf.little_endian or elf["e_machine"] != "EM_ARM":
            raise CheckError("expected matching 32-bit little-endian CPUAPP Arm ELF")
        symtab = elf.get_section_by_name(".symtab")
        if symtab is None:
            raise CheckError("ELF has no symbols")
        symbols = {
            sym.name: (int(sym["st_value"]), int(sym["st_size"]))
            for sym in symtab.iter_symbols()
        }
        needed = [
            "fixture_magic",
            "fixture_ready",
            "fixture_boot",
            "fixture_build_tag",
            "fixture_attempts",
            "fixture_drops",
            "fixture_reset_cause",
            "fixture_retained_valid",
            "fixture_ram_pattern",
            "_SEGGER_RTT",
        ]
        if any(name not in symbols for name in needed):
            raise CheckError("ELF is missing fixture symbols")
        tag_symbol = symtab.get_symbol_by_name("fixture_build_tag")[0]
        section = elf.get_section(tag_symbol["st_shndx"])
        offset = tag_symbol["st_value"] - section["sh_addr"]
        tag = struct.unpack("<I", section.data()[offset : offset + 4])[0]
        if symbols["fixture_ram_pattern"][1] != 256:
            raise CheckError("unexpected fixture RAM pattern size")
        # Explicit SRAM ranges prevent a mismatched ELF becoming a register sweep.
        for name in needed:
            address, size = symbols[name]
            if not 0x20000000 <= address < address + size <= 0x20040000:
                raise CheckError(f"fixture symbol outside nRF54L15 SRAM: {name}")
        return symbols, tag


def snapshot(rpc, symbols, tag, expected):
    result = {}
    for name in (
        "fixture_magic",
        "fixture_ready",
        "fixture_boot",
        "fixture_build_tag",
        "fixture_attempts",
        "fixture_drops",
        "fixture_reset_cause",
        "fixture_retained_valid",
    ):
        result[name] = rpc.words(symbols[name][0], 32, 1)[0]
    if (
        result["fixture_magic"] != 0x50423034
        or result["fixture_ready"] != 1
        or result["fixture_build_tag"] != tag
    ):
        raise CheckError("target is not the initialized matching fixture")
    # DHCSR read can clear sticky status bits; no target halt/poll operation.
    dhcsr = rpc.words(0xE000EDF0, 32, 1)[0]
    state = "halted" if dhcsr & (1 << 17) else "running"
    if state != expected:
        raise CheckError(f"expected {expected} target, observed {state}")
    result["run_state"] = state
    pattern = bytes(rpc.words(symbols["fixture_ram_pattern"][0], 8, 256))
    if pattern != bytes(i ^ 0xA5 for i in range(256)):
        raise CheckError("frozen RAM pattern differs")
    result["pattern_sha256"] = hashlib.sha256(pattern).hexdigest()
    return result


def capture(rpc, symbols, output, timeout, stall_ms):
    existing = rpc.call(
        "set ps {}; foreach s [services] {if {[dict get $s name] eq {rtt}} {lappend ps [dict get $s port]}}; join $ps ,"
    )
    if existing:
        raise CheckError(
            "session already has RTT services; refusing to replace another capture"
        )
    decoder = Decoder()
    started = False
    ports = []
    service_keys = []
    sockets = []
    try:
        address, size = symbols["_SEGGER_RTT"]
        rpc.call(f'rtt setup {address:#x} {size} "SEGGER RTT"')
        rpc.call("rtt start")
        started = True
        channels = rpc.call("rtt channellist")
        (output / "channels.txt").write_text(channels + "\n")
        for channel in (0, 1):
            rpc.call(f"rtt server start 0 {channel}")
            # OpenOCD removes services by the original configured string, not
            # the ephemeral port returned by services/getsockname().
            service_keys.append(0)
            listed = rpc.call(
                "set ps {}; foreach s [services] {if {[dict get $s name] eq {rtt}} {lappend ps [dict get $s port]}}; join $ps ,"
            )
            new = set(map(int, listed.split(","))) - set(ports)
            if len(new) != 1:
                raise CheckError("could not identify owned RTT endpoint")
            ports.append(new.pop())
        deadline = time.monotonic() + timeout
        stalled = False
        seen_summary = False
        drops_before_stall = None
        text = bytearray()
        with (
            selectors.DefaultSelector() as selector,
            (output / "channel0.bin").open("wb") as text_file,
            (output / "channel1.bin").open("wb") as binary_file,
        ):
            for channel, port in enumerate(ports):
                sock = socket.create_connection(("127.0.0.1", port), timeout=3)
                sockets.append(sock)
                selector.register(sock, selectors.EVENT_READ, channel)
            while time.monotonic() < deadline:
                for key, _ in selector.select(0.1):
                    assert isinstance(key.fileobj, socket.socket)
                    chunk = key.fileobj.recv(8192)
                    if not chunk:
                        raise CheckError("RTT endpoint disconnected")
                    if key.data == 0:
                        text_file.write(chunk)
                        text_file.flush()
                        text.extend(chunk)
                        if len(text) > 65536:
                            raise CheckError("text evidence limit exceeded")
                    else:
                        binary_file.write(chunk)
                        binary_file.flush()
                        for record in decoder.feed(chunk):
                            # Stall at the start of a new burst, not while the
                            # producer is already waiting to export its summary.
                            if (
                                stall_ms
                                and not stalled
                                and seen_summary
                                and record["kind"] == 1
                            ):
                                drops_before_stall = record["drops"]
                                rpc.call("rtt stop")
                                time.sleep(stall_ms / 1000)
                                rpc.call("rtt start")
                                stalled = True
                            if record["kind"] == 2:
                                seen_summary = True
                    if (
                        decoder.last_kind == 2
                        and decoder.records
                        and b"PB004 text channel\n" in text
                        and (not stall_ms or stalled)
                    ):
                        if stall_ms and (
                            decoder.drops is None
                            or drops_before_stall is None
                            or decoder.drops <= drops_before_stall
                        ):
                            raise CheckError("stall did not demonstrate producer drops")
                        return decoder.finish()
            raise CheckError(
                "capture timed out before a complete data/summary interval"
            )
    finally:
        for sock in sockets:
            sock.close()
        # Clean only services this harness created. Never stop the session.
        cleanup_errors = []
        for key in service_keys:
            try:
                rpc.call(f"rtt server stop {key}")
            except (CheckError, OSError, ValueError) as exc:
                cleanup_errors.append(str(exc))
        if started:
            try:
                rpc.call("rtt stop")
            except (CheckError, OSError, ValueError) as exc:
                cleanup_errors.append(str(exc))
        if cleanup_errors:
            message = "RTT cleanup incomplete: " + "; ".join(cleanup_errors)
            if sys.exc_info()[0] is None:
                raise CheckError(message)
            print(message, file=sys.stderr)


def check_baseline(baseline, before, session, elf_hash):
    if (
        not isinstance(baseline, dict)
        or baseline.get("outcome") != "passed"
        or baseline.get("elf_sha256") != elf_hash
    ):
        raise CheckError("baseline is failed or refers to another ELF")
    if not isinstance(baseline.get("session"), dict) or any(
        baseline["session"].get(name) != session.get(name)
        for name in ("serial", "target")
    ):
        raise CheckError("baseline belongs to another probe or target")
    if not isinstance(baseline.get("after"), dict):
        raise CheckError("baseline lacks final state")
    for name in ("fixture_boot", "fixture_build_tag", "pattern_sha256", "run_state"):
        if before[name] != baseline["after"].get(name):
            raise CheckError(f"baseline continuity failed: {name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--approve-observe",
        action="store_true",
        help="explicit approval for fixture debug-memory/RTT access",
    )
    parser.add_argument(
        "--session",
        required=True,
        type=Path,
        help="manifest from a dedicated live session with --tcl-port",
    )
    parser.add_argument("--elf", required=True, type=Path)
    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help="new evidence directory; never overwritten",
    )
    parser.add_argument(
        "--scenario", choices=("snapshot", "capture"), default="capture"
    )
    parser.add_argument(
        "--expect-state", choices=("running", "halted"), default="running"
    )
    parser.add_argument(
        "--baseline",
        type=Path,
        help="previous successful result.json for bounded warm-reset continuity check",
    )
    parser.add_argument("--timeout", type=int, default=20)
    parser.add_argument("--stall-ms", type=int, default=0)
    args = parser.parse_args()
    if not args.approve_observe:
        parser.error(
            "--approve-observe required; this connects to hardware and writes RTT bookkeeping"
        )
    if not 1 <= args.timeout <= 120 or not 0 <= args.stall_ms <= 2000:
        parser.error("timeout must be 1..120 s; stall must be 0..2000 ms")
    if args.scenario == "capture" and args.expect_state != "running":
        parser.error(
            "capture requires running fixture; use snapshot for halted-state tests"
        )
    args.output.mkdir(mode=0o700, parents=False, exist_ok=False)
    report: dict[str, Any] = dict(
        outcome="failed",
        scenario=args.scenario,
        argv=sys.argv[1:],
        started_unix=time.time(),
        board="xiao_nrf54l15/nrf54l15/cpuapp",
        scenario_verified=False,
    )
    rpc = None
    try:
        session = json.loads(args.session.read_text())
        if (
            not isinstance(session, dict)
            or session.get("schema") != 1
            or session.get("host") != "127.0.0.1"
            or session.get("target") != "nrf54l.cpu"
            or not isinstance(session.get("tcl_port"), int)
            or not 1 <= session["tcl_port"] <= 65535
        ):
            raise CheckError("invalid session or Tcl endpoint not explicitly enabled")
        report["session"] = session
        report["elf_sha256"] = hashlib.sha256(args.elf.read_bytes()).hexdigest()
        symbols, tag = elf_symbols(args.elf)
        report["symbols"] = symbols
        # Preserve resolved build inputs when available, rather than inferring
        # toolchain identity from a requested SDK version.
        build_root = args.elf.parent.parent
        for name, path in (
            ("build-config.txt", args.elf.parent / ".config"),
            ("cmake-cache.txt", build_root / "CMakeCache.txt"),
        ):
            if not path.is_file():
                raise CheckError(f"missing build provenance: {path}")
            (args.output / name).write_bytes(path.read_bytes())
        with (args.output / "commands.jsonl").open("w") as log:
            rpc = Rpc(session["tcl_port"], log)
            if rpc.call("set nix_nrf_session_id") != session.get("id"):
                raise CheckError(
                    "stale session metadata or port reused by another owner"
                )
            report["openocd_version"] = rpc.call("version")
            before = snapshot(rpc, symbols, tag, args.expect_state)
            report["before"] = before
            if args.baseline:
                baseline = json.loads(args.baseline.read_text())
                check_baseline(baseline, before, session, report["elf_sha256"])
            if args.scenario == "capture":
                captured: dict[str, Any] = capture(
                    rpc, symbols, args.output, args.timeout, args.stall_ms
                )
                report["capture"] = captured
                last = captured["last"]
                if (last["boot"], last["build"]) != (before["fixture_boot"], tag):
                    raise CheckError("RTT records do not match sampled boot/build")
            after = snapshot(rpc, symbols, tag, args.expect_state)
            report["after"] = after
            if before["fixture_boot"] != after["fixture_boot"]:
                raise CheckError("warm-reset counter changed during check")
            if rpc.log_failure is not None:
                raise CheckError(
                    f"command evidence could not be persisted: {rpc.log_failure}"
                )
            report.update(
                outcome="passed",
                scenario_verified=True,
                limits="No power-loss identity guarantee; DHCSR reads clear sticky bits; no proof of FLPR or production behavior.",
            )
        return 0
    except (CheckError, WireError, OSError, ValueError, ImportError) as exc:
        report["error"] = str(exc)
        print(f"fixture check: {exc}", file=sys.stderr)
        return 1
    finally:
        if rpc:
            rpc.close()
        report["finished_unix"] = time.time()
        (args.output / "result.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    sys.exit(main())
