---
id: PB-027
title: Research Nordic nrf-udev rules as an integration or verification source
status: Backlog
assignee: []
created_date: '2026-10-06 00:16'
labels:
  - 'area:openocd'
  - 'area:nix'
  - 'area:security'
dependencies: []
priority: p3
type: research
ordinal: 25000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

Maintainer found NordicSemiconductor/nrf-udev. Its usefulness alongside current OpenOCD-derived Linux device rules has not been assessed.

### Desired outcome

An evidence-backed recommendation explains whether to integrate these rules, use them for verification, or keep them as reference only.

### Scope / Non-goals

Research device coverage, permission policy, serial/ModemManager behavior, packaging, provenance and licensing. Compare current repository behavior. No installation, udev reload, host permission changes or hardware access is authorized by this item. Implementation requires a separate approved scope.

### Technical context

Source https://github.com/NordicSemiconductor/nrf-udev; recorded in sources.md. Current rule ownership: nix/hardware/udev-rules.nix, public nixosModules.udevRules, nix/flake/checks/udev-vm.nix. Upstream README explicitly warns that its rules permit all users to read/write Nordic devices.

### Open questions

Which useful device/transport gaps exist? Can verification or optional integration improve coverage without broadening access unintentionally? What revision/license/update policy would adoption require?
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Research records inspected upstream revision, device/transport coverage, permission/security differences and provenance/license evidence compared with current rules.
- [ ] #2 Recommendation chooses integration, verification-only or reference-only and explains tradeoffs; any proposed integration names the smallest hardware-free public NixOS/udev regression that would detect incorrect behavior.
- [ ] #3 No host rules are installed/reloaded and no permissions or hardware state are changed during research.
<!-- AC:END -->
