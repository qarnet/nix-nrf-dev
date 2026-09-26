---
id: PB-004
title: Add small RTT and debug verification firmware with an opt-in hardware harness
status: Backlog
assignee: []
created_date: '2026-09-26 00:41'
labels:
  - 'area:testing'
  - 'area:rtt'
  - 'area:debug'
dependencies: []
priority: p1
type: feature
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

Existing hardware tests prove image placement but not RTT bytes, attach state preservation, debug inspection, or FLPR execution. Reusing production audio firmware would couple generic tooling acceptance to application behavior.

### Desired outcome

Small test-owned firmware provides deterministic observable data and target state for public tooling tests.

### Scope / Non-goals

Provide known text and binary records, sequence/session identity, observable loss/completeness metadata, a frozen RAM pattern, and distinct threads. Keep fault/watchpoint scenarios explicitly intrusive. Separate approved provisioning from observation tests. Production DMA recorder/schema and audio implementation are non-goals; FLPR scenarios follow research findings.

### Technical context

tests/hardware/README.md; tests/hardware/run.sh; tests/hardware/preflight_xiao.py; docs/development/rtt-debug-research.md#verification-scope. Existing harness flashes but does not validate FLPR heartbeat or IPC.

Research and pinned upstream references: docs/development/rtt-debug-research.md. Receiver evidence: le-audio-receiver at 012b19739802e8fc53d6e8a701fb362a17a1c209, inspected read-only.

### Open questions

Which minimal board target and SDK configurations fit the test contract, how are scenarios selected without adding a production console, and what host-visible completion marker bounds each test?

This item remains Backlog until refinement resolves implementation-shaping questions and assigns size. Hardware access, flashing, recovery, and intrusive operations still require explicit approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Fixture emits reproducible text/binary records including non-text bytes, session identity, and known overflow/completion evidence without formatted logging in a sensitive producer path.
- [ ] #2 Known frozen RAM contents, distinct blocked/running threads, and explicit intrusive fault/watchpoint scenarios support repeatable assertions.
- [ ] #3 Build/provision and observe/debug stages are separate; normal CI neither flashes nor accesses hardware, and hardware provisioning requires approval.
- [ ] #4 Harness records probe, board, toolchain, image identity, commands, raw evidence, and outcomes; unknown or unavailable hardware results are not marked passed.
- [ ] #5 Tests remain small fixtures under tests, not a reusable production flight-recorder framework; each tooling feature retains its own acceptance tests.
<!-- AC:END -->
