# Qualified capabilities and known limitations

This matrix describes the active NCS v3.4.1 baseline, not every tool registered
by the SDK. Registration, parser loading, compile/link success, offline packaging,
and physical device behavior are separate verification boundaries.

## Current evidence

| Capability | amd64 nrfutil | amd64 west | ARM64 west | What is proved |
| --- | --- | --- | --- | --- |
| SDK-independent core west | qualified | qualified | qualified | Public command/help/workspace behavior; no implicit SDK bootstrap |
| nRF52840 single/sysbuild; nRF5340 CPUAPP/CPUNET; nRF54L15 CPUAPP/FLPR | qualified | qualified | qualified | Compile/link and ELF architecture; FLPR includes CPUAPP launcher, not physical startup |
| Application-owned imported workspace/module | qualified | qualified | qualified | Selected source/compiler/Python and linked module; original source/config/Git state unchanged |
| Stock extension registry/parser audit | 38/39 load | 38/39 load | 38/39 load | All 39 declarations accounted for across four layouts; missing suit-manifest retained as failure |
| `west suit-manifest` | unavailable | unavailable | unavailable | Upstream descriptor references removed Python implementation |
| MCUboot signing/update package creation | not separately qualified | not separately qualified | offline sample qualified | One nRF52840 SMP/MCUboot configuration, public debug key, package bytes and tamper rejection; not production signing policy |
| MCUboot/SMP transport, install, rollback/recovery | not qualified | not qualified | not qualified | Requires separately approved hardware/transport acceptance |
| Python-enabled GDB integration | not separately tested | offline initialization smoke passes | offline initialization smoke passes | ARM/RISC-V GDB imports Python/gdb; no remote target or debug lifecycle qualification |
| Nordic-managed ARM64 firmware bundle | not applicable | not applicable | unavailable | Public Nordic Linux ARM64 bundle index empty; use experimental west explicitly |
| x86 `native_sim` multilib on ARM64 | not applicable | not applicable | unavailable | Architecture-specific `-m32` workflow; explicit `withMultilib = true` rejected |

PB-001 and PB-026 retain source revisions and acceptance evidence. Repeatable
[qualification procedures](../tests/application-types/README.md) use prepared
sources/Python and keep registry, parser and firmware results separate. They do
not establish arbitrary boards, manifests or optional SDK features.

Offline signing covers the SDK's nRF52840 `smp_svr` sample with `--sysbuild`,
`EXTRA_CONF_FILE=bt.conf` and `SB_CONFIG_PARTITION_MANAGER=n`: debug P-256
signature verification, package CRCs/byte identity and tamper rejection.
The public debug key and insecure demonstration settings, including unrestricted
MCUmgr filesystem access, are not production security policy. No BLE/USB/serial
transfer, install, rollback, recovery or device lifecycle behavior is qualified.

Python-GDB coverage is initialization and `import gdb` only, with foreign Python
variables cleared. Target attachment, breakpoints, flashing and debugger-client
integration are not qualified.

## Missing suit-manifest: precise loss

Stock v3.4.1 `nrf/scripts/west-commands.yml` declares `suit-manifest`, but
`nrf/scripts/west_commands/suit_manifest.py` does not exist. Its help/import fails
with `FileNotFoundError` through both backends. Four application layouts repeat
this one defect: eight amd64 failures across two backends, four ARM64 failures.
No failure is silently skipped, and no SDK file is patched by this repository.

Historical implementation had three operations:

- `init`: copy selected Nordic YAML/Jinja templates into the application's SUIT
  directory and record original-template provenance.
- `review`: show changes between recorded and current Nordic templates; accepting
  updates provenance, not automatic merging into customized application templates.
- `check`: report whether Nordic template originals changed. It was not envelope
  validation or signature verification.

The helper did **not** generate envelopes, sign firmware, produce update archives,
or transmit DFU traffic. Those historical operations belonged to suit-generator,
sysbuild integration and device-side/transport tooling.

Nordic removed integrated SUIT support in NCS v3.1.0. Its current tagged migration
guide moves nRF54H20 from SUIT to IronSide SE plus local-domain DFU, for example
MCUboot. The template-management script was removed later; the descriptor remains
stale. Therefore the missing helper is not a new compiler/backend regression and
does not disable the accepted non-SUIT builds. Restoring that one Python file
would not restore removed SUIT generators, integration or samples.

For a legacy nRF54H20 SUIT application, the loss is the removed upstream workflow,
not just one west alias. Migration is not a universally safe recovery operation:
Nordic warns that SUIT-provisioned devices in lifecycle state `RoT` cannot return
to `EMPTY`, which the new IronSide provisioning path requires. Do not attempt
provisioning, erase, recovery or lifecycle changes as part of host validation.

## Alternatives and boundaries

- nRF52840 has SDK-documented MCUboot/SMP BLE and USB CDC sample configurations.
- nRF5340 has a separately documented simultaneous application/network-core DFU
  workflow; CPUNET compile success is not multi-image update acceptance.
- nRF54L has MCUboot and NSIB+MCUboot paths. FLPR compile/launcher success is not
  qualification of FLPR update payload packaging.
- Separate `nrfutil suit`, standalone suit-generator or mobile tooling are not
  presumed available or working merely because their names occur in old docs.

These are possible routes to validate, not drop-in replacements for the removed
template helper. Offline signing/packaging checks must stay separate from
transport/update/recovery on a device.

## Upstream evidence

- [v3.4.1 stale registration](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/scripts/west-commands.yml#L27-L31)
- [Historical helper operations, v3.0.0](https://github.com/nrfconnect/sdk-nrf/blob/v3.0.0/scripts/west_commands/suit_manifest.py#L129-L264)
- [Helper removal commit](https://github.com/nrfconnect/sdk-nrf/commit/dfbd28c5c6861f73cc8d1f2144dfe944288b17ac)
- [Tagged SUIT to IronSide/MCUboot migration](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/doc/nrf/releases_and_maturity/migration/migration_3.1_54h_suit_ironside.rst)
- [v3.1.0 release notes: removed SUIT support/samples](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/doc/nrf/releases_and_maturity/releases/release-notes-3.1.0.rst)
- [nRF5340 multi-image DFU](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/doc/nrf/app_dev/device_guides/nrf53/simultaneous_multi_image_dfu_nrf5340.rst)
- [nRF54L DFU configuration](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/doc/nrf/app_dev/device_guides/nrf54l/dfu_config.rst)
