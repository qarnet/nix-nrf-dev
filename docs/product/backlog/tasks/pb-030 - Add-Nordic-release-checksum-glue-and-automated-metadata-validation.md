---
id: PB-030
title: Add Nordic release checksum glue and automated metadata validation
status: Backlog
assignee: []
created_date: '2026-10-06 03:56'
labels:
  - 'area:toolchain'
  - 'area:west'
  - 'area:testing'
dependencies: []
priority: p2
type: feature
ordinal: 28000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

Release metadata is curated manually without an executable provenance check between tagged SDK metadata and Nordic published bundle mapping.

### Desired outcome

Maintainers can deterministically calculate Nordic bundle IDs from exact source files and validate published mappings and integrity metadata without installing a bundle.

### Scope / Non-goals

Implement checksum glue and validation first. Preserve upstream byte order/newline handling and separate short metadata fingerprint from full archive hashes. Normal users consume committed reviewed inputs; no network lookup or upstream inference during Nix evaluation or shell entry. No automatic release generation, SDK installation, hardware action or publication.

### Technical context

Tagged scripts/print_toolchain_checksum.sh hashes requirements-fixed.txt then platform tools YAML. v3.4.1 Linux calculation yields8285d8ad56 and matches the inspected published amd64 mapping. Index has mixed schema1/schema2 records, multiple selectors can share bundle, source-mirroring action supports mapping overrides. docs/product/research/nordic-release-metadata.md records source evidence.

### Open questions

What CLI/input format and committed validation fixtures best expose this contract? How should patched mappings and publisher drift be reported without silently rewriting locks?
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Public checksum command reproduces v3.4.1 input-derived ID and exposes source digests; regression fixtures cover exact concatenation order, CRLF handling, missing/malformed inputs and changed metadata.
- [ ] #2 Mapping validation detects unsupported schemas, duplicate/ambiguous selectors, mismatches and absent host inventory; short bundle ID never substitutes for archive integrity hash.
- [ ] #3 Offline verification of committed fixtures passes without network; deliberate live validation records snapshot provenance and drift separately, never changes consumer locks or installs tools.
<!-- AC:END -->
