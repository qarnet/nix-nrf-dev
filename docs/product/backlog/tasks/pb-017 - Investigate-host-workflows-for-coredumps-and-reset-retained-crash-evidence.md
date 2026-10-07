---
id: PB-017
title: Investigate host workflows for coredumps and reset-retained crash evidence
status: Backlog
assignee: []
created_date: '2026-09-26 00:42'
labels:
  - 'area:debug'
  - 'area:documentation'
dependencies: []
priority: p3
type: research
ordinal: 17000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

RAM snapshot tooling cannot guarantee evidence survives reset or power loss, and fatal firmware may never drain its own recorder. Receiver has tight SRAM and multiple images.

### Desired outcome

A generic host-side recovery/symbolication recommendation defines what evidence can be recovered and what the firmware must provide.

### Scope / Non-goals

Evaluate Zephyr coredump formats, matching-ELF analysis, retained-RAM export, reset causes, and CPUAPP/FLPR image identity. Production crash hooks, storage layout, retention policy, and persistent writes stay consumer-owned.

### Technical context

docs/product/research/debug-tooling.md#observation-and-evidence-limits; receiver boards/nrf54l15dk_nrf54l15_cpuapp.conf documents SRAM pressure. No configured coredump path was established during receiver inspection.

Research and pinned upstream references: docs/product/research/debug-tooling.md. Receiver evidence: le-audio-receiver at 012b19739802e8fc53d6e8a701fb362a17a1c209, inspected read-only.

### Open questions

Which supported coredump format and host analyzer fit the toolchain, what reset-retention guarantees exist, and is any consumer budget available?

This item remains Backlog until refinement resolves implementation-shaping questions and assigns size. Hardware access, flashing, recovery, and intrusive operations still require explicit approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Report separates live/frozen RAM, reset-retained state, and power-loss persistence without treating .noinit as a retention guarantee.
- [ ] #2 Proposed host flow identifies matching images, failure/incomplete evidence, and application-owned format/storage prerequisites.
- [ ] #3 A minimal fixture recovery and symbolication experiment is specified, with approved evidence or explicit blockers; no production recorder framework is added.
<!-- AC:END -->
