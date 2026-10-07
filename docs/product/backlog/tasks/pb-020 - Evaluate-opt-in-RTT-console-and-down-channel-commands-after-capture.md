---
id: PB-020
title: Evaluate opt-in RTT console and down-channel commands after capture
status: Backlog
assignee: []
created_date: '2026-09-26 00:42'
updated_date: '2026-09-26 00:42'
labels:
  - 'area:rtt'
  - 'area:cli'
  - 'area:security'
dependencies:
  - PB-006
priority: p3
type: research
ordinal: 20000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

Initial receive-only capture intentionally excludes commands. OpenOCD's raw TCP endpoint is already bidirectional, so future interactive use needs a distinct safety contract.

### Desired outcome

A later decision defines whether and how explicit interactive RTT can coexist with safe capture without silently enabling transmit.

### Scope / Non-goals

Evaluate channel pairing, console encoding versus binary framing, buffering, multiple clients, command authority, and strict receive-only enforcement options. No default stdin forwarding, automatic commands, flashing, or application command schema.

### Technical context

Pinned src/server/rtt_server.c forwards socket input down-channel and has no receive-only switch; docs/product/research/debug-tooling.md#observation-and-evidence-limits. Initial capture client must remain application receive-only.

Research and pinned upstream references: docs/product/research/debug-tooling.md. Receiver evidence: le-audio-receiver at 012b19739802e8fc53d6e8a701fb362a17a1c209, inspected read-only.

### Open questions

Is an interactive RTT consumer needed beyond existing UART shell, and should strict receive-only protection require a proxy or server change?

This item remains Backlog until refinement resolves implementation-shaping questions and assigns size. Hardware access, flashing, recovery, and intrusive operations still require explicit approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Decision states a concrete console use case or keeps the feature deferred, preserving the receive-only command contract.
- [ ] #2 Proposed interface separates explicit transmit from capture, specifies channel/framing/ownership and failure semantics, and assesses host command risks.
- [ ] #3 Verification plan includes encoded down-channel traffic, accidental stdin input, concurrent clients, and full/disconnected buffers; no implementation is enabled by research alone.
<!-- AC:END -->
