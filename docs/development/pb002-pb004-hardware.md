# PB-002 and PB-004 hardware validation handoff

Detailed physical evidence moved to
`~/repos/xiao-samd11-debug-probe/docs/pb002-pb004-hardware.md`. Start with that
project's `HANDOFF.md`; its artifact manifest maps temporary capture paths to
preserved copies.

Current acceptance boundary:

- XIAO serial `EF0E3B64`, USB `2886:0066`, initially identified as nRF54L15 AAC0.
- The PB-004 fixture was built, flashed, and byte-verified. Execution and RTT
  output were not established.
- Subsequent SWD DPIDR reads fail while the SAMD11 USB probe remains accessible.
- Reset/reconnect experiments did not restore target access. RST2 attempts
  re-enumerated normal CMSIS-DAP mode, not the expected UF2 boot mode.
- Host tests pass, but physical PB-002/PB-004 criteria remain unchecked where
  no real evidence exists. No mass erase or SAMD11 firmware update was performed.

The separate probe workspace now owns this diagnosis. Once physical access is
restored, resume this repository's `tests/hardware/debug/README.md` procedure;
do not infer a completed feature from successful flash verification.
