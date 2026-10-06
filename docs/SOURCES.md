# External sources for future research

These references were supplied by the maintainer and recorded on 2026-10-06.
Their repository descriptions/READMEs were checked; integration has not been
evaluated or approved. Recording a source does not make it a dependency.

## Nordic Linux udev rules

- Source: https://github.com/NordicSemiconductor/nrf-udev
- Research item: PB-027.
- Purpose: Linux udev rules for Nordic development kits, including USB access,
  serial-port permissions, and avoiding unwanted ModemManager interaction.
- Possible use: compare device coverage and permission policy against this
  repository's pinned OpenOCD rules; evaluate a verification reference or an
  explicit, optional integration rather than assuming replacement is appropriate.
- Current ownership: `nix/hardware/udev-rules.nix`, `nix/flake/checks/udev-vm.nix`,
  and the public `nixosModules.udevRules` output.
- Security consideration: upstream README warns that its rules make Nordic
  devices readable/writable by all users. Evaluate that policy explicitly before
  adopting rules; do not silently broaden device access.

## nRF Connect Toolchain Manager

- Source: https://github.com/nordicsemi/pc-nrfconnect-toolchain-manager/tree/main
- Research item: PB-028.
- Purpose: nRF Connect for Desktop application for installing and managing NCS
  development tools.
- Possible use: investigate relevant SDK/toolchain discovery, installation and
  environment-management behavior as implementation/reference material. Whether
  any behavior or code is useful to this Nix repository remains open.
- Current ownership: `nix/backends/nrfutil/` and `nix/backends/west/`.
- Research must distinguish this desktop app from the pinned `nrfutil
  sdk-manager` CLI. Verify maintenance status, supported versions/platforms,
  licensing and provenance before recommending reuse.

Existing general references remain in the root [sources.md](../sources.md).
Research task status and eventual decisions belong in the product backlog.

## Nordic artifact and release metadata

Verified v3.4.1 checksum derivation, Python fixed-file semantics, west-version
history, public Artifactory API access, and proposed maintainer/consumer tooling
boundaries are recorded in
[Nordic artifact metadata research](development/nordic-artifact-metadata-research.md).

Initial Git-shareable JSONL inventory and capture limits:
[Nordic artifact catalog](research/nordic-artifacts/README.md).
Acquisition research: PB-029. Automation sequence: PB-030 through PB-033.
