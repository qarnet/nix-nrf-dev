---
id: PB-006
title: Capture receive-only RTT text and binary up-channels over CMSIS-DAP
status: Backlog
assignee: []
created_date: '2026-09-26 00:41'
updated_date: '2026-09-26 00:42'
labels:
  - 'area:rtt'
  - 'area:cli'
  - 'area:openocd'
dependencies:
  - PB-002
  - PB-004
priority: p1
type: feature
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

Receiver needs an additional evidence path independent of UART shell traffic, but this repository offers no binary-safe RTT capture workflow.

### Desired outcome

Users discover/select an up-channel and capture exact bytes through the shared OpenOCD session without application transmit or implicit run control.

### Scope / Non-goals

Channel listing/selection, matching-ELF control-block lookup, explicit address or bounded search, file/stdout capture, optional text viewing, separate diagnostics, and bounded shutdown/error handling. Define disconnect/session identity behavior. OpenOCD sockets remain bidirectional; the capture client sends no payloads. No console input, auto-flash, lossless guarantee for arbitrary firmware, or hidden device recovery.

### Technical context

nix/commands/default.nix; nix/hardware/openocd.nix; docs/product/research/debug-tooling.md#observation-and-evidence-limits. Up-channel consumption writes target read offsets; generic raw transport cannot infer firmware drops or acknowledge durable host storage. Receiver prj.conf enables UART shell; offload statistics use RTT to mean round-trip time, not SEGGER RTT.

Research and pinned upstream references: docs/product/research/debug-tooling.md. Receiver evidence: le-audio-receiver at 012b19739802e8fc53d6e8a701fb362a17a1c209, inspected read-only.

### Open questions

Finalize output/overwrite policy, bounded search validation, reconnect policy, incomplete-capture exit semantics, and supported concurrent readers/channels.

This item remains Backlog until refinement resolves implementation-shaping questions and assigns size. Hardware access, flashing, recovery, and intrusive operations still require explicit approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Public capture preserves exact fixture bytes including NUL and arbitrary binary values; diagnostics never enter payload output and text display is opt-in.
- [ ] #2 Channel listing and ELF/address lookup work; missing blocks, wrong channels, inaccessible ranges, and unsupported layouts fail clearly within bounded time.
- [ ] #3 Encoded-traffic tests prove the client sends no down-channel bytes and never reads stdin for commands; documentation identifies RTT read-offset writes and raw endpoint bidirectionality.
- [ ] #4 Approved target tests preserve boot/run state; slow reader, disconnect, cancellation, and file-write failure produce explicit results without reset or recovery.
- [ ] #5 Numbered fixture data demonstrates declared loss or incomplete capture without claiming arbitrary firmware loss detection; reconnection does not silently merge unrelated boot sessions.
- [ ] #6 Standalone capture and capture alongside explicit GDB share one OpenOCD owner and clean up only owned resources.
<!-- AC:END -->
