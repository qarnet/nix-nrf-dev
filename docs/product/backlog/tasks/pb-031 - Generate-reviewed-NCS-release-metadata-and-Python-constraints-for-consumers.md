---
id: PB-031
title: Generate reviewed NCS release metadata and Python constraints for consumers
status: Backlog
assignee: []
created_date: '2026-10-06 03:57'
labels:
  - 'area:toolchain'
  - 'area:west'
  - 'area:nix'
  - 'area:testing'
dependencies:
  - PB-030
priority: p2
type: feature
ordinal: 29000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

Manual release entries and isolated Python pin workarounds make maintenance error-prone. Users need locked reviewed packages, not live upstream inference.

### Desired outcome

A maintainer-only generator produces deterministic candidate release metadata and validated Python constraints from an exact upstream revision; normal consumers use the committed reviewed result.

### Scope / Non-goals

Build on checksum/mapping validation. Record SDK Git identity, source digests, declared/resolved/observed tool versions, platform asset hashes and explicit policy overrides. Derive constraints without installing optional packages implicitly. Consumer paths stay offline/deterministic with existing source/Python ownership. No automatic acceptance/publication or environment-manager redesign.

### Technical context

Current nix/backends/west/versions.nix holds active v3.4.1 metadata. Fixed requirements contain extras and --index-url, so cannot be used unchanged with pip -c. Nordic tools YAML west1.4.0 differs from fixed/observed1.5.0. Compiler SDK1.0.1 changed GNU archive layout. See docs/product/research/nordic-release-metadata.md; PB-030 supplies checksum validation.

### Open questions

What generated representation and artifact-lock policy should be committed? How should extras, markers, package indexes, native wheels and isolated build dependencies be normalized and validated?
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Generator is deterministic for identical committed inputs and has check-only mode; output preserves SDK/source/hash provenance and separates upstream expectations from repository selections.
- [ ] #2 Derived constraints preserve version/marker semantics, handle extras and index directives explicitly, and retain user-selected optional tooling without installing the entire upstream resolution.
- [ ] #3 Public consumer evaluation/shell entry uses committed locks only and performs no generation/live inference; public-boundary tests prove drift detection and malformed/conflicting data refusal.
- [ ] #4 Candidate release includes package/parser/firmware qualification requirements on supported hosts; generating metadata or hashes alone does not assert compatibility.
<!-- AC:END -->
