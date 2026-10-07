---
id: PB-015
title: Investigate OpenOCD profiling with explicit intrusion limits
status: Backlog
assignee: []
created_date: '2026-09-26 00:41'
labels:
  - 'area:debug'
  - 'area:openocd'
dependencies: []
priority: p3
type: research
ordinal: 15000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

Statistical profiling may help later optimization, but the pinned Cortex-M implementation can silently fall back to halting/resuming and can resume an initially halted target.

### Desired outcome

A sourced capability decision states whether usable profiling exists on XIAO and how intrusive modes would be gated.

### Scope / Non-goals

Inspect DWT_PCSR support, OpenOCD fallback behavior, sampling quality, matching-image analysis, and measured overhead. No default profiler command or non-intrusive claim before validation.

### Technical context

Pinned src/target/cortex_m.c:2370-2429 and src/target/target.c:2343-2384; receiver's audio/FLPR deadlines make stop-based sampling a poor transparent default.

Research and pinned upstream references: docs/product/research/debug-tooling.md. Receiver evidence: le-audio-receiver at 012b19739802e8fc53d6e8a701fb362a17a1c209, inspected read-only.

### Open questions

Does PC sampling work on this silicon/probe combination, can fallback be detected before changing state, and is useful resolution achievable?

This item remains Backlog until refinement resolves implementation-shaping questions and assigns size. Hardware access, flashing, recovery, and intrusive operations still require explicit approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Report distinguishes background sampling from stop/resume fallback and initially halted-target behavior using exact source revisions.
- [ ] #2 Any approved experiment records initial/final state, sampling output, overhead, and firmware impact; untested capability remains unknown.
- [ ] #3 Recommendation either defines explicit intrusive consent/fail-closed checks and a validation plan or rejects the workflow with evidence; no automatic enablement is added.
<!-- AC:END -->
