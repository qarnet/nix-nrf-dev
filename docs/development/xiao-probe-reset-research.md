# XIAO probe research moved

Canonical SAMD11 firmware/reset investigation now lives in the sibling project:

- Workspace: `~/repos/xiao-samd11-debug-probe`
- Entry point: `HANDOFF.md`
- Research: `docs/xiao-probe-reset-research.md`
- Proposed PA04 fix: `docs/reset-pin-fix.md`
- Hardware evidence: `docs/pb002-pb004-hardware.md`

It includes the pinned `baorepo/free-dap` source, Seeed schematics, analyzed
release images, and preserved diagnostic artifacts. No SAMD11 update or
working physical target-reset fix has been validated yet.

PB-002/PB-004 remain in this repository and are blocked on physical target
access. Host session tooling, the small nRF54L15 test fixture, and the generic
RTT/GDB backlog have not moved. Do not silently add resets or erase/recovery
to observation mode to work around the probe issue.
