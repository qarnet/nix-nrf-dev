---
id: PB-016
title: Investigate XIAO SWO ITM and trace support through CMSIS-DAP
status: Backlog
assignee: []
created_date: '2026-09-26 00:42'
labels:
  - 'area:debug'
  - 'area:openocd'
dependencies: []
priority: p3
type: research
ordinal: 16000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

SoC SWO support does not prove board routing or SAMD11 probe firmware capability. Older SDK limitations are not a reliable current support matrix.

### Desired outcome

A board/probe/SDK-qualified decision identifies any practical trace path and required hardware or firmware changes.

### Scope / Non-goals

Verify silicon trace facilities, XIAO revision/schematics, exposed pins, onboard probe firmware, CMSIS-DAP transport, and host decoding. Distinguish SWO/ITM from wider instruction trace. No pin reassignment, probe firmware update, or trace implementation without separate approval.

### Technical context

docs/product/research/debug-tooling.md notes unverified SWO routing. Seeed XIAO guide and exact selected SDK bindings are starting references, not proof of capture.

Research and pinned upstream references: docs/product/research/debug-tooling.md. Receiver evidence: le-audio-receiver at 012b19739802e8fc53d6e8a701fb362a17a1c209, inspected read-only.

### Open questions

Are trace pins routed and free, does the onboard probe implement capture, and can supported host tooling decode data at useful bandwidth?

This item remains Backlog until refinement resolves implementation-shaping questions and assigns size. Hardware access, flashing, recovery, and intrusive operations still require explicit approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Capability matrix separates silicon, board routing, probe firmware, transport, and decoder support with exact versions and source references.
- [ ] #2 A minimal approved capture proves any claimed working route; otherwise required hardware/firmware and validation blockers are explicit.
- [ ] #3 Recommendation states whether trace is worthwhile alongside RTT/GPIO and provides bounded follow-up scope without claiming generic CMSIS-DAP implies SWO support.
<!-- AC:END -->
