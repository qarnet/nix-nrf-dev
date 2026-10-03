"""PB-004 test protocol only. Not a decoder for consumer firmware records."""

import struct

SIZE = 64


class WireError(ValueError):
    pass


class Decoder:
    def __init__(self):
        self.pending = b""
        self.identity = None
        self.next_seq = None
        self.drops = None
        self.records = 0
        self.summaries = 0
        self.last_kind = None
        self.last = None

    def feed(self, data):
        self.pending += data
        result = []
        while len(self.pending) >= SIZE:
            raw, self.pending = self.pending[:SIZE], self.pending[SIZE:]
            magic, version, kind, size, seq, drops, boot, uptime, attempts, build = (
                struct.unpack("<4sBBH6I", raw[:32])
            )
            checksum, end = struct.unpack("<II", raw[56:])
            if magic != b"PB04" or version != 1 or kind not in (1, 2) or size != SIZE:
                raise WireError("invalid fixture record header or stream alignment")
            if checksum != sum(raw[:56]) or end != 0x0DF00D04:
                raise WireError("fixture checksum/end marker mismatch")
            if raw[32:56] != bytes((seq + 17 * i) & 255 for i in range(24)):
                raise WireError("fixture payload mismatch")
            if attempts != seq + (kind == 1) or drops > attempts:
                raise WireError("invalid attempt/drop counters")
            identity = (boot, build)
            if self.identity is not None and self.identity != identity:
                raise WireError("boot/build changed during capture")
            if self.next_seq is not None:
                if kind == 2 and self.last_kind == 2 and seq == self.next_seq:
                    raise WireError("duplicate summary record")
                if seq < self.next_seq or drops < self.drops:
                    raise WireError("counter regression; reset/wrap or stale data")
                if seq - self.next_seq != drops - self.drops:
                    raise WireError(
                        "unaccounted record loss or duplicate transport data"
                    )
            self.identity = identity
            self.next_seq = attempts
            self.drops = drops
            self.last_kind = kind
            self.records += kind == 1
            self.summaries += kind == 2
            self.last = dict(
                sequence=seq,
                drops=drops,
                boot=boot,
                build=build,
                uptime_ms=uptime,
                attempts=attempts,
                kind=kind,
            )
            result.append(self.last)
        return result

    def finish(self):
        if self.pending:
            raise WireError("incomplete trailing record")
        if self.last_kind != 2 or not self.records:
            raise WireError("capture lacks data followed by a complete summary")
        return dict(
            records=self.records,
            summaries=self.summaries,
            last=self.last,
            leading_history="unknown: capture may attach mid-session",
        )
