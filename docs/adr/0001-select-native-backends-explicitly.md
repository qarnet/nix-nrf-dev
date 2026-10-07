# 0001: Select native backends explicitly

Status: Accepted

## Context

Native nrfutil and its sdk-manager extension are available on Linux ARM64,
but sdk-manager does not support installing a Nordic toolchain there. Nordic's
published Linux ARM64 toolchain index was empty when native host support was
qualified. Command availability is not compiler-bundle availability.

Zephyr SDK publishes native Linux amd64 and ARM64 compiler archives. This lets
the experimental west backend support both hosts without emulating Nordic's
amd64 bundle. It does not make that environment equivalent to every Nordic tool.

## Alternatives

- Reject ARM64 entirely: loses a working native firmware-build path.
- Fall back from nrfutil to west: silently changes compiler, Python, provisioning
  and supported workflows for the same consumer configuration.
- Run an amd64 container/emulator: adds runtime and filesystem requirements and
  does not establish native ARM64 support. Optional Docker work remains PB-025.

## Decision

Publish native `x86_64-linux` and `aarch64-linux` outputs. Use pinned native
Zephyr SDK assets for west on both hosts. Reject unsupported nrfutil firmware
requests on ARM64 before acquisition, without fallback.

Preserve the public `mkNrfShell` nrfutil default for compatibility. Repository
shells and the initializer apply declared host presets: nrfutil on amd64, west
on ARM64. A portable consumer explicitly chooses west. Centralize capabilities
and presets in `nix/platforms.nix`; keep release-specific assets backend-owned.

## Consequences

- Native ARM64 builds are possible without an x86 executor or privileged setup.
- Hand-written ARM64 shells must explicitly select west; omitted backend fails.
- Native standalone nrfutil remains useful without implying Nordic toolchain
  installation support. Multilib is independently host-gated.
- Both hosts need native package and behavior qualification. Firmware build,
  parser loading, signing, and hardware acceptance remain separate boundaries.
- If Nordic adds an ARM64 bundle, qualify it before changing this policy. Index
  presence alone is insufficient. A future default change needs explicit review.

## References

- [Nordic sdk-manager installation](https://docs.nordicsemi.com/bundle/nrfutil/page/nrfutil-sdk-manager/guides/sdk_manager_installing.html)
- [Published toolchain configuration](https://files.nordicsemi.com/artifactory/NCS/external/bundles/config.json)
- [Linux ARM64 toolchain index](https://files.nordicsemi.com/artifactory/NCS/external/bundles/v3/index-linux-aarch64.json)
- [Captured publisher metadata](../research/nordic-artifacts/README.md)
- [Backend caller contract](../backends.md#native-host-boundaries)
- PB-026 and [issue #11](https://github.com/qarnet/nix-nrf-dev/issues/11)
