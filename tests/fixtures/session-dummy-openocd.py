#!/usr/bin/env python3
"""Replace only physical adapter/target with real OpenOCD's no-hardware testee."""

import os
import sys

script = sys.argv[sys.argv.index("-c") + 1]
script = script.replace("source [find interface/cmsis-dap.cfg]", "adapter driver dummy")
script = script.replace("cmsis-dap backend usb_bulk", "transport select jtag")
script = script.replace(
    "set part [lindex [nrf54l.cpu read_memory 0x00FFC31C 32 1] 0]", "set part 0x54B15"
)
script = script.replace(
    "source [find target/nordic/nrf54l.cfg]",
    "jtag newtap nrf54l cpu -irlen 4\n"
    "target create nrf54l.cpu testee -chain-position nrf54l.cpu\n"
    "target create nrf54l.aux testee -chain-position nrf54l.cpu\n"
    "proc jtag_init {} {}",
)
script += "\nlappend pre_shutdown_commands {echo SESSION_CLEAN_SHUTDOWN}\n"
os.execv(os.environ["REAL_OPENOCD"], [os.environ["REAL_OPENOCD"], "-c", script])
