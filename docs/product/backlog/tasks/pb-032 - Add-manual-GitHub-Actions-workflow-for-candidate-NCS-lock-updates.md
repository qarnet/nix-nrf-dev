---
id: PB-032
title: Add manual GitHub Actions workflow for candidate NCS lock updates
status: Backlog
assignee: []
created_date: '2026-10-06 03:57'
labels:
  - 'area:ci'
  - 'area:toolchain'
  - 'area:security'
dependencies:
  - PB-031
priority: p2
type: feature
ordinal: 30000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

Maintainers need a repeatable deliberate workflow to generate and validate release-lock updates without silently advancing consumer packages.

### Desired outcome

A manually triggered workflow creates reviewable candidate metadata and evidence, with both-host qualification before human acceptance.

### Scope / Non-goals

Use maintainer generator and checksum validation, record exact requested revision and lock diff, run applicable shared/native gates and report qualification gaps. No scheduled updates yet, auto-merge, automatic release, unsafe privileged fork execution or hardware operation.

### Technical context

PB-031 is the generator stage; existing .github/workflows/ci.yml and scripts/ci.py separate shared prerequisites from native Linux matrix. docs/product/research/nordic-release-metadata.md records consumer/maintainer separation.

### Open questions

Should initial workflow publish artifacts only or open a candidate PR? What bounded SDK acquisition, retention, credentials and cost limits are required?
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Manual workflow accepts explicit upstream revision and records deterministic generated diff and provenance; malformed inputs, mapping/hash mismatch and qualification failure are visible failures.
- [ ] #2 Both supported Linux entries and shared checks gate candidate qualification with no hidden omissions; credentials and permissions cannot expose privileged execution to untrusted fork code.
- [ ] #3 Candidate output is reviewable and existing consumer locks remain unchanged until normal human acceptance; workflow never merges or releases automatically.
<!-- AC:END -->
