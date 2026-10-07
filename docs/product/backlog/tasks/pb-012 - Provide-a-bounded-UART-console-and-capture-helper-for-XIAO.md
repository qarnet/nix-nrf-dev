---
id: PB-012
title: Provide a bounded UART console and capture helper for XIAO
status: Backlog
assignee: []
created_date: '2026-09-26 00:41'
labels:
  - 'area:serial'
  - 'area:cli'
dependencies: []
priority: p2
type: feature
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

UART remains the practical fallback, but repo users lack a standard helper. Receiver already has HIL serial ownership and raw log capture, so replacing its orchestration would create competing readers.

### Desired outcome

A generic user-facing serial workflow selects a port, captures raw output, and exits predictably while respecting existing owners.

### Scope / Non-goals

Explicit port/baud selection, binary-preserving capture, optional console mode, clear contention errors, bounded cancellation, and documented DTR/RTS behavior. No application command automation or replacement of receiver HIL. No assertion that native nRF54L15 USB exists.

### Technical context

docs/hardware.md covers host permissions. Receiver scripts/hil/serial_io.py:1-16,74-89 already retains raw RX/TX and controls pre-open line settings. Board SAMD11 bridges USB serial; verify exact board revision before documenting pins.

Research and pinned upstream references: docs/product/research/debug-tooling.md. Receiver evidence: le-audio-receiver at 012b19739802e8fc53d6e8a701fb362a17a1c209, inspected read-only.

### Open questions

Reuse an existing packaged serial tool or build a thin helper? What line-state and ownership defaults avoid unintended board resets, and how should console versus capture mode be selected?

This item remains Backlog until refinement resolves implementation-shaping questions and assigns size. Hardware access, flashing, recovery, and intrusive operations still require explicit approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Public pseudo-terminal tests prove raw byte preservation, baud/port handling, output failures, cancellation, and resource release.
- [ ] #2 Approved board validation documents actual bridge behavior and line-state effects; no unexpected reset or command transmit occurs in capture mode.
- [ ] #3 A busy/missing port fails clearly; docs prohibit concurrent readers with serial-mcp or receiver HIL and show explicit handoff.
- [ ] #4 Console input is explicit, capture diagnostics stay separate, and native USB versus bridge UART limitations are accurate.
<!-- AC:END -->
