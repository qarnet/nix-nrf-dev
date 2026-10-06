---
id: PB-025
title: Add an optional Nordic Docker toolchain backend
status: Backlog
assignee: []
created_date: '2026-10-04 12:22'
labels:
  - 'area:toolchain'
  - 'area:nix'
  - 'area:ci'
dependencies: []
references:
  - 'https://github.com/nrfconnect/sdk-nrf/pkgs/container/sdk-nrf-toolchain'
priority: p3
type: feature
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

Some users want Nordic's complete containerized toolchain environment rather than host-level bundle integration or individually assembled Nix tools. Docker support is not implemented. The user explicitly deferred pursuing this feature.

### Desired outcome

An optional backend uses a selected official Nordic toolchain image for development/build workflows, with accurate platform and capability documentation.

### Scope / Non-goals

Deferred feature; no implementation in the current Linux ARM64 work. Define supported runtimes, platforms, image selection and workflow scope before Ready. Do not imply native ARM64 support from amd64 emulation or automatically grant privileged hardware access.

### Technical context

Research: docs/development/west-toolchain-research.md; existing backend dispatch in nix/backends/default.nix and child-process toolchain scoping in nix/backends/nrfutil/shell.nix. Official ghcr.io/nrfconnect/sdk-nrf-toolchain v3.3.0 image digest sha256:f24d8932ff081ebcd8da9c248f4449bdabe461c0620a7a4ac9e95eb577ba2276 is linux/amd64. Public registry research found no runnable ARM64 image among 145 tags. Latest currently points to preview, so pin image digest and SDK source revision.

### Open questions

Docker only or a rootless/Podman-compatible runtime? Native amd64 only versus explicit emulation/remote execution? Build-only initial scope or separate debugging/flashing capability? How should mounts, UID/GID ownership, writable cache/HOME and daemon-host paths be managed? Which releases/images become supported?
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Supported backend invocation selects the configured immutable image and builds representative firmware with verified compiler/Python/source identity; no silent image/platform fallback.
- [ ] #2 Host/runtime prerequisites, supported platforms and build/debug limitations are documented and verified; emulated amd64 is not advertised as native ARM64.
- [ ] #3 Existing-source commands preserve source/configuration and do not implicitly update repositories or install host tools; privileged/device access requires separately explicit approval.
- [ ] #4 Public-boundary tests cover output ownership/path mapping, errors, cancellation, cleanup and repeat builds through the chosen runtime.
<!-- AC:END -->
