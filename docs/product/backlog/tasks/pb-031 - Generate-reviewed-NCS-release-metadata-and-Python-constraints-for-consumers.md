---
id: PB-031
title: Generate reviewed NCS release metadata and Python constraints for consumers
status: Backlog
assignee: []
created_date: '2026-10-06 03:57'
updated_date: '2026-10-14 01:57'
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

Manual release entries and isolated Python pin workarounds make maintenance error-prone. Users need locked reviewed packages, not live upstream inference. PB-034 adds documentation tooling with release-specific Python/native requirements and build integration that also need a reviewed support policy.

### Desired outcome

A maintainer-only generator produces deterministic candidate release metadata and validated Python constraints from an exact upstream revision; normal consumers use the committed reviewed result. Documentation releases reuse shared pinned tooling environments where compatible, with explicit qualification rather than duplicated package pins or live consumer resolution.

### Scope / Non-goals

Build on checksum/mapping validation. Record SDK Git identity, source digests, declared/resolved/observed tool versions, platform asset hashes and explicit policy overrides. Derive constraints without installing optional packages implicitly. Include documentation requirement validation, shared environment-family mappings, native documentation tool constraints, release-specific build adapters, and real rendering qualification for claimed documentation support. Consumer paths stay offline/deterministic with existing source/Python ownership. This describes metadata consumption, not a guarantee that documentation rendering is offline. No automatic acceptance/publication, runtime dependency resolution, or environment-manager redesign.

### Technical context

Current nix/backends/west/versions.nix holds active v3.4.1 metadata. Fixed requirements contain extras and --index-url, so cannot be used unchanged with pip -c. Nordic tools YAML west1.4.0 differs from fixed/observed1.5.0. Compiler SDK1.0.1 changed GNU archive layout. See docs/product/research/nordic-release-metadata.md; PB-030 supplies checksum validation. PB-034 research at docs/product/research/ncs-documentation-refinement.md distinguishes requirements validation from dependency resolution. Python requirements do not cover all native tools or upstream build adapters. Documentation compatibility records should be independent of firmware backend selection and may share a pinned environment across releases. PB-034 initial bounded support does not depend on completing this general generator.

### Open questions

What generated representation and artifact-lock policy should be committed? How should extras, markers, package indexes, native wheels and isolated build dependencies be normalized and validated? Should documentation dependency locks use the existing pinned Nixpkgs/wheel definitions or maintainer-generated uv locks? What evidence permits a release to reuse a documentation environment family, and what triggers a separate family?
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Generator is deterministic for identical committed inputs and has check-only mode; output preserves SDK/source/hash provenance and separates upstream expectations from repository selections.
- [ ] #2 Derived constraints preserve version/marker semantics, handle extras and index directives explicitly, and retain user-selected optional tooling without installing the entire upstream resolution.
- [ ] #3 Public consumer evaluation/shell entry uses committed locks only and performs no generation/live inference; public-boundary tests prove drift detection and malformed/conflicting data refusal.
- [ ] #4 Candidate release includes package/parser/firmware qualification requirements on supported hosts; generating metadata or hashes alone does not assert compatibility.
- [ ] #5 Documentation candidate metadata records requirement and native-tool provenance, maps releases to reusable pinned environment families independently of firmware backend, rejects incompatible constraints without consumer-side installation, and requires actual HTML rendering qualification before claiming release support; requirements validation alone is not acceptance.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Product owner requested folding broader documentation version verification into the existing release-metadata item after PB-034 research. Added docs environment-family reuse, native constraints, adapters, and rendering qualification. Avoid per-release duplication when one pinned environment satisfies several releases. Status/priority/dependencies unchanged.

PB-034 product owner approved initial v3.4.1-only documentation support and future per-NCS-version tool indexing here. Index Python/native tools, requirement provenance, environment-family reuse, build adapters and qualified host outcomes. Actual mutable consumer workspaces remain runtime inputs; no live consumer dependency resolution. Approved initial contract: docs/product/research/ncs-documentation-contract.md.
<!-- SECTION:NOTES:END -->
