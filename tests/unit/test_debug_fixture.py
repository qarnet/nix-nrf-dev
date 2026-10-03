"""Decode actual C-encoded fixture traffic across transport chunk boundaries."""

import os
from pathlib import Path
import socket
import socketserver
import struct
import subprocess
import sys
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[2]
HARDWARE = Path(os.environ.get("FIXTURE_HARNESS", ROOT / "tests/hardware/debug"))
sys.path.insert(0, str(HARDWARE))
from wire import Decoder, WireError
from check import Rpc, capture, check_baseline, CheckError


class FixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.encoded = subprocess.check_output([os.environ["FIXTURE_ENCODER"]])

    def test_arbitrary_transport_chunks_and_trailing_loss(self):
        for step in (1, 7, 64, 65, 256):
            decoder = Decoder()
            for offset in range(0, len(self.encoded), step):
                decoder.feed(self.encoded[offset : offset + step])
            result = decoder.finish()
            self.assertEqual(result["records"], 2)
            self.assertEqual(result["last"]["drops"], 4)
            self.assertEqual(result["last"]["attempts"], 6)

    def test_corrupt_missing_and_partial_records_are_not_success(self):
        corrupt = bytearray(self.encoded)
        corrupt[40] ^= 1
        variants = [
            bytes(corrupt),
            self.encoded[:64] + self.encoded[128:],
            self.encoded[:-1],
            self.encoded[:128],
        ]
        for data in variants:
            with self.subTest(length=len(data)), self.assertRaises(WireError):
                decoder = Decoder()
                decoder.feed(data)
                decoder.finish()

    def test_boot_change_and_duplicate_rejected(self):
        changed = bytearray(self.encoded)
        struct.pack_into("<I", changed, 64 + 16, 2)
        struct.pack_into("<I", changed, 64 + 56, sum(changed[64:120]))
        for data in (
            changed,
            self.encoded[:64] + self.encoded,
            self.encoded + self.encoded[-64:],
        ):
            with self.assertRaises(WireError):
                Decoder().feed(data)

    def test_cli_without_approval_cannot_create_evidence_or_connect(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "evidence"
            result = subprocess.run(
                [
                    sys.executable,
                    str(HARDWARE / "check.py"),
                    "--session",
                    "missing",
                    "--elf",
                    "missing",
                    "--output",
                    str(output),
                ],
                capture_output=True,
            )
            self.assertEqual(result.returncode, 2)
            self.assertFalse(output.exists())

    def test_baseline_requires_same_probe_but_allows_new_owner(self):
        state = dict(
            fixture_boot=1,
            fixture_build_tag=42,
            pattern_sha256="pattern",
            run_state="running",
        )
        session = dict(serial="probe-A", target="nrf54l.cpu", id="new-owner")
        baseline = dict(
            outcome="passed",
            elf_sha256="image",
            after=state,
            session=dict(session, id="old-owner"),
        )
        check_baseline(baseline, state, session, "image")
        with self.assertRaises(CheckError):
            check_baseline(baseline, state, dict(session, serial="probe-B"), "image")
        with self.assertRaises(CheckError):
            check_baseline(baseline, dict(state, fixture_boot=2), session, "image")

    def test_tcl_frames_split_response_and_error(self):
        # Exercise actual encoded TCP framing, not a mocked Rpc.call.
        with socket.socket() as listener, tempfile.TemporaryFile(mode="w+") as log:
            listener.bind(("127.0.0.1", 0))
            listener.listen()
            received = []

            def peer():
                conn, _ = listener.accept()
                with conn:
                    for response in (b"0\n42\x1a", b"1\nfailed\x1a"):
                        request = b""
                        while not request.endswith(b"\x1a"):
                            request += conn.recv(1024)
                        received.append(request)
                        for byte in response:
                            conn.sendall(bytes([byte]))

            thread = threading.Thread(target=peer, daemon=True)
            thread.start()
            rpc = Rpc(listener.getsockname()[1], log)
            try:
                self.assertEqual(rpc.call("expr {6 * 7}"), "42")
                from check import CheckError

                with self.assertRaises(CheckError):
                    rpc.call("error failed")
            finally:
                rpc.close()
                thread.join(timeout=3)
            self.assertEqual(len(received), 2)
            self.assertIn(b"catch", received[0])

    def test_capture_persists_encoded_channels_and_releases_only_its_services(self):
        commands = []
        listeners = []
        active = []
        peers = []
        stop = threading.Event()
        connected = threading.Barrier(2)
        payloads = [b"PB004 text channel\n", self.encoded]
        sent_from_host = []

        def stream(listener, payload):
            conn, _ = listener.accept()
            with conn:
                connected.wait(timeout=5)
                for start in range(0, len(payload), 7):
                    conn.sendall(payload[start : start + 7])
                stop.wait(timeout=5)
                conn.settimeout(2)
                sent_from_host.append(conn.recv(1024))

        class Handler(socketserver.BaseRequestHandler):
            def handle(self):
                pending = b""
                while True:
                    chunk = self.request.recv(8192)
                    if not chunk:
                        return
                    pending += chunk
                    while b"\x1a" in pending:
                        frame, pending = pending.split(b"\x1a", 1)
                        command = (
                            frame.decode()
                            .split("catch {", 1)[1]
                            .rsplit("} result]", 1)[0]
                        )
                        commands.append(command)
                        result = ""
                        if "foreach s [services]" in command:
                            result = ",".join(str(s.getsockname()[1]) for s in active)
                        elif command.startswith("rtt server start"):
                            channel = int(command.split()[-1])
                            listener = socket.socket()
                            listener.bind(("127.0.0.1", 0))
                            listener.listen()
                            listeners.append(listener)
                            active.append(listener)
                            peer = threading.Thread(
                                target=stream,
                                args=(listener, payloads[channel]),
                                daemon=True,
                            )
                            peers.append(peer)
                            peer.start()
                        elif command.startswith("rtt server stop"):
                            if command.split()[-1] == "0" and active:
                                active.pop(0)
                                stop.set()
                        elif command == "rtt channellist":
                            result = "fixture channels"
                        self.request.sendall(b"0\n" + result.encode() + b"\x1a")

        with (
            socketserver.ThreadingTCPServer(("127.0.0.1", 0), Handler) as server,
            tempfile.TemporaryDirectory() as tmp,
            tempfile.TemporaryFile(mode="w+") as log,
        ):
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            rpc = Rpc(server.server_address[1], log)
            try:
                result = capture(
                    rpc, {"_SEGGER_RTT": (0x20000000, 96)}, Path(tmp), 5, 0
                )
                self.assertEqual(result["last"]["drops"], 4)
                self.assertEqual(
                    (Path(tmp) / "channel1.bin").read_bytes(), self.encoded
                )
                self.assertEqual((Path(tmp) / "channel0.bin").read_bytes(), payloads[0])
            finally:
                stop.set()
                rpc.close()
                server.shutdown()
                thread.join(timeout=3)
                for peer in peers:
                    peer.join(timeout=3)
                for listener in listeners:
                    listener.close()
        self.assertEqual(sent_from_host, [b"", b""])
        self.assertEqual(active, [], "ephemeral RTT services leaked")
        self.assertEqual(sum(c.startswith("rtt server stop") for c in commands), 2)
        self.assertNotIn("shutdown", commands)


if __name__ == "__main__":
    unittest.main()
