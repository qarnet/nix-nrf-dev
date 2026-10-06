---
id: PB-029
title: >-
  Research efficient Nordic artifact metadata acquisition and JSONL catalog
  coverage
status: Backlog
assignee: []
created_date: '2026-10-06 03:56'
labels:
  - 'area:toolchain'
  - 'area:nrfutil'
  - 'area:nix'
  - 'area:documentation'
dependencies: []
priority: p2
type: research
ordinal: 27000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

Web UI browsing is inefficient and incomplete for understanding Nordic artifacts. Maintainer requested a Git-shareable JSONL metadata database and research into easier official acquisition methods.

### Desired outcome

A documented, evidence-backed acquisition strategy makes relevant advertised artifacts searchable locally while distinguishing incomplete coverage from verified absence.

### Scope / Non-goals

Compare Nordic published SDK/toolchain/package indexes, PyPI Simple metadata, JFrog Storage/checksum APIs and supported search/export capabilities. Define useful JSONL coverage, refresh and query behavior. No authentication bypass, wholesale archive mirror, SDK installation, hardware action or consumer runtime metadata inference.

### Technical context

Initial scripts/nordic_artifact_catalog.py prototype captured nine public metadata sources as docs/research/nordic-artifacts/2026-10-06/catalog.jsonl: 391 records, source-level provenance/digests in manifest.json. Published indexes avoid broad recursive crawling; sdk-manager metadata is already JSONL. Nordic PyPI Simple endpoints returned HTML despite JSON negotiation. Anonymous basic Storage works, bulk list returned403, AQL/export require privileges. Evidence: docs/development/nordic-artifact-metadata-research.md and docs/research/nordic-artifacts/README.md.

### Open questions

Which additional package/project scopes are useful? What coverage, retention, query and refresh guarantees are appropriate? Can supported official exports reduce requests without credentials or privileged access?
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Research compares official acquisition methods with actual endpoint/authentication/schema evidence and recommends the least-request strategy for each artifact class.
- [ ] #2 JSONL coverage, provenance, checksums, refresh/retention and local query design are documented; empty inventories, denied/unvisited paths and partial failures cannot be mistaken for complete absence.
- [ ] #3 Proposed collector improvements name public HTTP/CLI regressions for malformed responses, permission denial, resource limits, refresh/retry and no artifact downloads; initial snapshot remains clearly labeled advertised inventory only.
<!-- AC:END -->
