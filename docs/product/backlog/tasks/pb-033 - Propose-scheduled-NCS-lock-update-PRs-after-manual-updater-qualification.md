---
id: PB-033
title: Propose scheduled NCS lock-update PRs after manual updater qualification
status: Backlog
assignee: []
created_date: '2026-10-06 03:57'
labels:
  - 'area:ci'
  - 'area:toolchain'
  - 'area:security'
dependencies:
  - PB-032
priority: p3
type: feature
ordinal: 31000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

After deliberate release-update tooling is proven, routine upstream checks can be automated without making normal consumers infer current upstream state.

### Desired outcome

A bounded scheduled workflow detects eligible changes and proposes reviewable update PRs with provenance and validation evidence.

### Scope / Non-goals

Later stage after manual updater qualification. Define eligible release/LTS policy, idempotent candidate branches/PRs, drift detection and failure reporting. Never auto-merge, auto-release, alter consumer locks outside reviewed PRs, run hardware operations or grant privileged execution to untrusted input.

### Technical context

PB-032 supplies manual workflow; PB-031 supplies candidate generator; PB-030 validates checksum/mapping provenance. docs/product/research/nordic-release-metadata.md records fixed consumer inputs and the automation boundary.

### Open questions

Which releases should schedule consider, including nRF52 v3.4 LTS constraints? What cadence, request/build budget, bot permissions and notification policy avoid churn and excessive cost?
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Scheduled job uses explicit eligible-release policy and bounded network/resource limits; unchanged metadata produces no duplicate candidate PR or lock churn.
- [ ] #2 Proposals retain source/hash provenance and qualification evidence; ambiguous mapping, missing artifacts or failed tests cannot be represented as a qualified update.
- [ ] #3 Repeated executions and concurrent candidates behave safely, secrets/permissions remain scoped, and human merge remains mandatory with no automatic release.
<!-- AC:END -->
