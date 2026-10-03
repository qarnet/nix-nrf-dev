#!/usr/bin/env python3
"""Process/port lifecycle peer. It does not model target hardware safety."""

import os
import re
import signal
import socket
import sys
import time

script = sys.argv[sys.argv.index("-c") + 1]
match = re.search(r"NIX_NRF_READY_([a-f0-9]+)", script)
assert match
token = match.group(1)
scenario = os.environ.get("SESSION_SCENARIO", "ready")
if scenario == "failure":
    print("CPUAPP examination failed; no recovery attempted", flush=True)
    sys.exit(1)
if scenario == "timeout":
    time.sleep(60)
if scenario == "stubborn":
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    signal.signal(signal.SIGTERM, signal.SIG_IGN)

listeners = []
ports = []
for pattern in (r"^tcl port (\S+)$", r"^nrf54l.cpu configure -gdb-port (\S+)$"):
    match = re.search(pattern, script, re.M)
    value = match.group(1) if match else "disabled"
    if value == "disabled":
        ports.append(-1)
        continue
    listener = socket.socket()
    listener.bind(("127.0.0.1", int(value)))
    listener.listen()
    listeners.append(listener)
    ports.append(listener.getsockname()[1])

line = f"NIX_NRF_READY_{token} {ports[0]} {ports[1]}\n"
# Pipes may split readiness at any byte boundary.
for part in (line[:9], line[9:]):
    sys.stdout.write(part)
    sys.stdout.flush()
    time.sleep(0.01)
if scenario == "exit-after-ready":
    time.sleep(0.2)
    sys.exit(7)
while True:
    time.sleep(1)
