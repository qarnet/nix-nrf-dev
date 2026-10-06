# Issue 11: native Linux amd64 and arm64 support

Planning/research snapshot and subsequent isolated Pi experiments, 2026-10-04.
Baseline observations below describe the merged-main revision, not the current
worktree. PB-026 now adds ARM64 outputs; native qualification and the forced-TCG
udev VM gate pass. The changes are not published, and hosted CI has not run.
Current caller contracts live in [backends.md](../backends.md); execution status
and acceptance evidence belong to PB-026. Issue: [#11](https://github.com/qarnet/nix-nrf-dev/issues/11).
Repository base: merged main `78df6f5a49ec8fcd28a51345ce4cd070b7e3e164`.
Root Nixpkgs: `643809054d65fdd466a63e3155b8c498cb483c04`.
Snapshot NCS baseline was v3.3.0; active v3.4.1 qualification is recorded in
[west-backend-status.md](west-backend-status.md#v341-qualification). Product
release and SDK versions remain independent; older results are not relabeled.

Follow-up [west coverage and toolchain installation research](west-toolchain-research.md)
records actual JFrog indexes, Docker platform/digest findings, Python/tool parity
gaps, a public readiness false-positive experiment, and environment-path policy.

## Recommendation and scope

Publish native `x86_64-linux` and `aarch64-linux` package/shell outputs. Keep
amd64 behavior intact. Qualify the existing Nix-toolchain `west` backend on
arm64; do not advertise the Nordic-managed `nrfutil` build backend on Linux
arm64. Native nRF Util availability does not establish native Nordic toolchain
availability.

Recommended first-release contract:

| Capability | x86_64-linux | aarch64-linux |
| --- | --- | --- |
| OpenOCD, udev package/module, project CLI and initializer | Native | Native, after qualification |
| Packaged nRF Util core + pinned sdk-manager extension | Native | Native, after qualification |
| Nordic-managed `backend = "nrfutil"` firmware workflow | Existing support | Explicitly unavailable |
| `backend = "west"`, NCS v3.3.0 | Existing experimental support | Qualified native path; still experimental |
| Existing-source workspace routing | Both backends | West backend |
| x86 `native_sim` multilib / `-m32` | Existing support | Not supported |
| Physical flashing, RTT/GDB state preservation | Existing evidence/limits | Not inferred from host tests |

Do not expand to macOS, Windows, ARM32, new NCS releases, host cross-compilation,
x86 emulation, or a replacement Nordic toolchain bundle. Do not install SDKs,
Python dependencies, or operate hardware during planning. Native firmware
qualification later needs an approved, prepared ARM64 environment.

**Accepted PB-026 scope:** native ARM64 development through west, not Nordic
sdk-manager backend parity. If identical Nordic-managed workflows are
mandatory, upstream toolchain support is a blocker, not a CI problem.

## Implementation qualification status

- Both-host public output evaluation passes. Intended amd64 worktree passes
  `nix flake check -L` and `python3 -B scripts/ci.py packages`.
- `west-sdk-native-probes` executes SDK compilers, compiles ARM/RISC-V ELF32
  objects, verifies machine headers, and runs plain GDB. Both native hosts pass.
  This does not claim GDB Python parity.
- Portable `imported_workspace.py` rerun on amd64 passes four real builds and
  four negative checks, with linked manifest-owned module evidence and preserved
  seed state. Evidence: `/tmp/opencode/pb026-amd64-imported-workspace/result.json`.
- Intended ARM64 imported-workspace rerun passes two west builds and two negative
  checks, including linked module and source/config/Git preservation. Total
  675.27s; build phases 149.95s single-image and 161.94s sysbuild. Evidence:
  Pi `~/nix-nrf-experiments/pb026-native-imported-workspace/result.json`, copied
  to `/tmp/opencode/pb026-evidence/native-firmware-result.json`.
- Both hosts pass native package builds, packaged executable smoke runs,
  both-system generated-west-project evaluation, native shell entry, and clean
  environment checks without mutable SDK acquisition. Reports live under
  `/tmp/opencode/pb026-amd64-consumer` and Pi `pb026-native-consumer`.
- Pi intended implementation previously passed all native flake checks with
  KVM. That does not qualify hosted ARM64 software emulation.
- TCG full trials fail before guest assertions. A bounded initrd diagnostic
  suppressing bulk coldplug proves native filesystem probing, runtime worker
  control, and a targeted `vda` event: label `nixos`, a resulting
  `/dev/disk/by-label/nixos` symlink, and matching udev database properties.
  Retained Pi evidence: `~/nix-nrf-experiments/tcg-initrd-probe-observed/console.log`.
  This narrower probe is not a substitute for the full udev VM gate.
- On pinned systemd 261.1, the runtime `SetChildrenMax` control path is needed
  to apply the worker budget; static config merging omits `children_max`.
  Longer control/service/device budgets alone failed. A full-coldplug trace
  shows module/driver-event enumeration and receive-side priority starving
  worker dispatch. The current ARM64 test-only candidate coldplugs
  `--type=devices` in both stages: every actual device still uses real rules and
  workers, but subsystem/driver-object stress is outside this test's claim.
  Root-label discovery, root mount, stage-2 boot, and backdoor shell now pass in
  the full TCG trial after removing stage-2 startup-control coupling. The
  original `udevadm control --reload` assertion still fails with a varlink reply
  timeout. An attempted bounded `udevadm settle` also times out on its initial
  varlink ping and has been removed as an unsuccessful mitigation. These trials
  did not qualify hosted ARM64 CI. The subsequent stat-key repair below passes
  the complete forced-TCG test; no assertion is waived.
  No udev assertions are removed or skipped.
- CI topology and complete shared/native check partition pass regression tests;
  actionlint passes. Hosted workflow execution requires separate Git publication
  approval. Docker remains PB-025, outside this implementation.

### Pinned udev reload defect

Further source diagnosis reproduced an architecture-independent systemd 261.1
defect. `udev_rules_parse_file()` saves file stats under `ConfFile.original_path`,
while `config_get_stats_by_path()` enumerates paths with resolved parent
directories. NixOS's `/etc/udev/rules.d` symlink therefore produces unequal map
keys for unchanged files. Masked/empty rules are correctly excluded and are not
the cause.

A native diagnostic using the real pinned shared-library enumeration/stat/map
functions reports unequal original-path maps and equal resolved-path maps for a
symlinked directory; both maps match for the direct-directory control. This is
not a full daemon test, but isolates false reload detection without another
guest boot. Sources: systemd v261.1
[udev-rules.c](https://github.com/systemd/systemd/blob/v261.1/src/udev/udev-rules.c),
[conf-parser.c](https://github.com/systemd/systemd/blob/v261.1/src/shared/conf-parser.c),
and [conf-files.c](https://github.com/systemd/systemd/blob/v261.1/src/basic/conf-files.c).

`nix/flake/checks/udev-systemd.nix` now provides a same-version, test-image-only
repair: save stats under `c->result`. Consumer packages and dependency pins are
unchanged; explicit reloads and rule parsing remain intact. The patched amd64
package, its 44-rule install verification, and original amd64 VM assertions pass.
Native ARM64 package and exact VM image builds also pass. The complete forced-TCG
test passes every original assertion in 1518.35s, within its 1800s global budget,
on the approved Pi. Evidence: Pi `state/pb026-tcg-stat-path-repair.json` and
`logs/pb026-tcg-stat-path-repair.stderr`, copied under
`/tmp/opencode/pb026-evidence`. KVM permissions are restored and the VM has stopped.
Hosted CI design stays unchanged, as selected by the product owner; actual GitHub
workflow execution still requires separately authorized publication.

## Verified facts and blockers

### nRF Util and its extension are separate from the toolchain bundle

Locked Nixpkgs already provides nRF Util 8.2.0 for `aarch64-linux` and native
SEGGER J-Link 9.52. Read-only derivation evaluation succeeded for both. Nixpkgs'
ARM64 extension catalog differs from amd64 and includes sdk-manager 1.15.0;
the repository intentionally replaces that extension with 1.16.1.

Sources: locked Nixpkgs `pkgs/by-name/nr/nrfutil/source.nix:55-82`,
`pkgs/by-name/nr/nrfutil/package.nix`, and
`pkgs/by-name/se/segger-jlink/source.nix`. nRF Util's wrapper includes J-Link
even without optional extensions; retain the existing license configuration in
`nix/flake/per-system.nix:13-23` and verify the native library closure.

Repository `nix/backends/nrfutil/package.nix:12-15,47-52` currently hard-codes
the amd64 sdk-manager archive and metadata. Nordic publishes this exact arm64
1.16.1 archive:

```text
https://files.nordicsemi.com/artifactory/swtools/external/nrfutil/packages/nrfutil-sdk-manager/nrfutil-sdk-manager-aarch64-unknown-linux-gnu-1.16.1.tar.gz
sha256-G3ABdtS6jPsvaDt2fedJ2OXhqtlsujBFNQUCOx+/ZLc=
```

Hash provenance: [official storage metadata](https://files.nordicsemi.com/artifactory/api/storage/swtools/external/nrfutil/packages/nrfutil-sdk-manager/nrfutil-sdk-manager-aarch64-unknown-linux-gnu-1.16.1.tar.gz),
3,527,525 bytes, SHA-256
`1b700176d4ba8cfb2f683b767de749d8e5e1aad96cba30453505023b1fbf64b7`.
Metadata was inspected; archive bytes were not downloaded or executed.

Nordic explicitly states: **"The sdk-manager command does not support toolchain
installation with Linux ARM64 installation of nRF Util."** See
[installation documentation](https://docs.nordicsemi.com/bundle/nrfutil/page/nrfutil-sdk-manager/guides/sdk_manager_installing.html)
and [supported operating systems](https://docs.nordicsemi.com/bundle/nrfutil/page/README.html#supported-operating-systems),
retrieved through Nordic documentation MCP. Current nRF Util's Debian ARM64
support is not NCS v3.3.0 Linux ARM64 support or a Nordic support promise for NixOS.
Pinned [NCS v3.3.0 requirements](https://github.com/nrfconnect/sdk-nrf/blob/v3.3.0/doc/nrf/installation/recommended_versions.rst)
also mark Linux ARM64 unsupported.

Current `nix/backends/nrfutil/shell.nix:120-126` obtains the whole environment
through `sdk-manager toolchain env`, including Python and other host binaries.
The already installed v3.3.0 bundle's Python/compiler are x86-64 ELF binaries.
Changing the nrfutil launcher or source paths does not make that bundle native.
Registry-wide absence of every possible alternate bundle was not proven; the
explicit upstream limitation is sufficient not to claim this backend supported.

### West has native host assets, but repository currently rejects ARM64

`nix/backends/west/zephyr-sdk.nix:23-28,155-159` and
`nix/backends/west/shell.nix:65-67` reject non-amd64 hosts. Metadata in
`nix/backends/west/versions.nix:26-54` contains only amd64 assets. These are
repository restrictions, not missing upstream ARM64 compiler archives.

The official [Zephyr SDK 0.17.0 release](https://github.com/zephyrproject-rtos/sdk-ng/releases/tag/v0.17.0)
and [checksum file](https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v0.17.0/sha256.sum)
provide:

| ARM64-host asset | SHA-256 |
| --- | --- |
| `zephyr-sdk-0.17.0_linux-aarch64_minimal.tar.xz` | `889f10c68a179f5ff2e4ea84749202c117bb522af705d5a888ebe76373acac5a` |
| `toolchain_linux-aarch64_arm-zephyr-eabi.tar.xz` | `b88e22918c0f9e7d33a329f01000d47a2bd00c4dfb80cc83c5308095f0eaeebd` |
| `toolchain_linux-aarch64_riscv64-zephyr-elf.tar.xz` | `ecd7f16fcb53d3415cccbdbc15faeff96a6967001c96f93153407a84342e9d35` |

Asset URL prefix is
`https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v0.17.0/`.
Host changes to AArch64; firmware compiler targets remain `arm-zephyr-eabi` and
`riscv64-zephyr-elf`. Preserve the existing removal of interactive SDK installers
and registry exports; Nix supplies the host tools.

Metadata establishes availability, not successful autoPatchelf or execution.
Existing SDK packaging intentionally lacks working Python-enabled GDB because
of legacy Python/crypt ABIs (`zephyr-sdk.nix:69-77`); ARM64 support must not
silently turn that limitation into a debugger-parity claim.

Publisher metadata provides universal wheels for
[nrf-regtool 9.2.1](https://pypi.org/pypi/nrf-regtool/9.2.1/json) and
[zcbor 0.8.1](https://pypi.org/pypi/zcbor/0.8.1/json). Their transitive native
dependencies still need ARM64 execution/build evidence. Keep Python 3.12 and
existing SDK pins, including cbor2 5.9.0; do not loosen pins to make setup pass.

### Multilib and consumer scaffolding are additional blockers

Both shell implementations use `pkgs.stdenv.isLinux && withMultilib`, while the
public default is true (`nix/backends/default.nix:132-133`). On ARM64, evaluating
`pkgs.gccMultiStdenv.cc` fails with
`i686 Linux package set can only be used with the x86 family.`

`nix/init-project/skeleton/flake.nix.in:9-17` hard-codes both the output system
and library selection to x86_64-linux. Root output expansion alone would leave
generated projects unusable on arm64. Qualification harnesses also hard-code
`lib.x86_64-linux` in their expressions (`tests/application-types/run.py` and
`imported_workspace.py`); they need explicit selected-host inputs.

Pinned Backlog.md `3c7fde65e28a6e5e154f63126957649514eee370` exposes aarch64-linux.
Its ARM64 derivation and this repository's product-shell construction evaluate.
Keep its separate Nixpkgs `61b7c44c4073f0b827768aff0049561b5110ea5a` rather than
making it follow the root pin. Native build/runtime remains unverified.

## Platform selection: already a Nix responsibility

Use exactly `x86_64-linux` and `aarch64-linux` in the flake's explicit supported
system list. Nix selects `devShells.<system>.default`, `apps.<system>`, and
`packages.<system>` for normal `nix develop`, `nix run`, and `nix build` usage.
Source: [nix develop output selection](https://nix.dev/manual/nix/2.34/command-ref/new-cli/nix3-develop#flake-output-attributes).

Do not add `uname` detection to pure flake outputs, or replace explicit output
enumeration with `builtins.currentSystem`. That builtin is unavailable during
pure evaluation ([manual](https://nix.dev/manual/nix/2.34/language/builtins.html#builtins-currentSystem)).
Builders select host assets through `pkgs.stdenv.hostPlatform.system`, which is
already used by west SDK packaging and the public NixOS module. Firmware target
architecture is not the development-host system. This project will build native
host tools on each native runner, not use `pkgsCross` for host migration.

An explicit ARM64 derivation can be evaluated on an amd64 machine. That does
not supply an ARM64 executor. Likewise, `--all-systems --no-build` proves
evaluation only, not that foreign executables run.

## Recommended default/backend policy

1. Preserve public `mkNrfShell`'s `backend = "nrfutil"` default and amd64
   behavior. On ARM64, an omitted/explicit nrfutil backend fails with a clear
   host/backend message recommending `backend = "west"`; no implicit fallback.
2. Repository `devShells.default` and `clean-env-test` explicitly choose
   nrfutil on amd64 and west on arm64. This is a declared host preset, not
   recovery after a requested backend fails. Their banners expose the choice.
3. Initializer default chooses the supported host preset: existing nrfutil
   default on amd64, west on arm64. An explicit unsupported ARM64 nrfutil
   request fails before remote version lookup or destination writes.
4. Generate west consumer projects for both supported Linux hosts using pure
   per-system mapping. Explicit nrfutil projects expose only x86_64-linux;
   do not publish a known-failing ARM64 shell. A project wanting one portable
   firmware toolchain uses west explicitly on both hosts. Do not require a
   second Nixpkgs/flake-utils input just to generate the mapping.
5. Standalone `packages.nix-nrf` keeps its nrfutil-based command identity;
   ARM64 `bootstrap` must report unsupported Nordic toolchain management
   before acquisition, while help/probe/session commands remain usable.
   Direct users to the west shell's backend-aware bootstrap. Native packaged
   nrfutil is still available for its supported non-toolchain uses.
6. Make `withMultilib` default host-aware: true on x86_64-linux, false on
   aarch64-linux. Explicit `true` on ARM64 fails with a repository-owned
   message; never force the i686 package set or silently promise `-m32`.

Centralize the small host/backend capability policy used by the public factory,
repository shells, initializer wrapper, and check selection. Keep versioned
asset ownership in the existing backend metadata/package modules. Do not make
contributor tools dependencies of consumer shells.

## CI: three validation jobs, not three self-hosted runner machines

Use one shared job followed by a two-entry native matrix. This produces three
validation job instances; retain the existing trusted-main release job after
both native entries succeed.

```yaml
jobs:
  shared:
    runs-on: ubuntu-24.04
    # source lint, release contract, all-system evaluation

  native:
    needs: shared
    name: Native (${{ matrix.system }})
    strategy:
      fail-fast: false
      matrix:
        include:
          - system: x86_64-linux
            runner: ubuntu-24.04
          - system: aarch64-linux
            runner: ubuntu-24.04-arm
    runs-on: ${{ matrix.runner }}
    # native package builds, behavior checks, CLI/shell/initializer smoke

  release:
    needs: [shared, native]
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    # preserve existing privileged reusable-release invocation
```

This is a topology sketch, not a complete workflow. GitHub's
[runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
lists both native Ubuntu labels. This repository is public; standard hosted
runner usage is free. Prefer explicit 24.04 labels over `ubuntu-latest` for
stable baseline behavior. No runner registration or persistent machine is
needed for normal native package tests.

### Shared job

- Run formatting, pre-commit source lint, and release-consistency once on
  amd64; build existing `formatting`, `pre-commit`, `release-consistency` checks.
- Materialize nested contributor source paths through writable product-shell
  evaluation before the read-only gate, preserving the cold-store workaround.
  After publishing both systems, evaluate each product shell's `.drvPath`.
- Run `nix flake check --all-systems --no-build -L` and assert both published
  host output sets exist. Check asset/target coverage for every declared host.
- If native CI excludes the three shared checks to avoid duplicate work,
  derive the native check list from all current check names minus that explicit
  shared list. Validate the partition, so new checks cannot disappear silently.
  Keep full `nix flake check -L` as the local complete gate.

### Each native job

- Install Nix with the existing `cachix/install-nix-action@v31`, and retain
  `cachix/cachix-action@v17`. Their composite/Node24 definitions are not tied
  to x86 executables; actual native operation is a first-run acceptance gate.
  Assert effective Nix system equals the matrix system before tests.
- Build native checks outside the three shared source-only gates, including
  Backlog.md behavior on each host, source-routing tests, session/Tcl traffic,
  fixture protocol, bootstrap behavior, and NixOS module/udev tests.
- Build all six existing package outputs on each host and execute real
  OpenOCD/nrfutil/sdk-manager/project CLI version/help/offline checks. Help
  alone is not SDK/toolchain or physical programming qualification.
- Execute both native-host compiler binaries after ELF fixup; compile tiny
  freestanding objects for ARM and RISC-V and inspect target ELF architecture.
- Exercise shell entry, selected backend banner, parent environment isolation,
  native Node/Git/Python tools, and generated-consumer shell entry. Do not assert
  nrfutil exists in a west firmware shell: it intentionally excludes nrfutil.
- Run supported-backend behavior coverage. Preserve nrfutil shell tests on
  amd64; replace unavailable ARM64 shell construction with explicit public
  rejection/non-acquisition tests. Do not bypass the platform guard merely to
  make old synthetic two-backend fixtures run on ARM64.
- Use one `qarnet` Cachix cache: Nix derivations already distinguish systems.
  Any Actions-level mutable cache keys must include host system, SDK/Python
  versions and relevant inputs. Do not share venvs or CMake build directories
  between architectures. Public/fork PRs must work with cache reads and no
  write secrets. Preserve contents-read permissions and do not introduce
  `pull_request_target` or persistent self-hosted runners for untrusted PRs.

### Important ARM64 VM exception

Existing `udev-vm` runs a booted NixOS VM, not a simple text/unit check.
Pinned Nixpkgs `nixos/lib/testing/run.nix:59-64,162` requires `kvm` by default
on Linux. GitHub runner-image maintainers report ARM64 hosted runners do not
expose nested KVM ([issue 14062](https://github.com/actions/runner-images/issues/14062#issuecomment-5352403358)).
This is different from native ARM64 package execution and cannot be fixed by
inventing a `kvm` system-feature flag.

Recommended first attempt: run the same ARM64 guest/udev assertions under QEMU
TCG, with `requiredFeatures.kvm = false` and `qemu.forceAccel = false` for the
ARM64 test only. Both knobs exist in the pinned test framework; the latter
already defaults false (`nixos/lib/testing/driver.nix:152-160`). Record actual
runtime/free-space costs and bound the job (initial native job budget 45 minutes).
Keep amd64 KVM behavior intact. If TCG cannot meet the budget, require a separate
trusted/manual KVM-capable ARM64 builder for that gate; do not silently mark the
VM test passed or weaken its udev assertions. No such builder is currently proven
available. That infrastructure decision is conditional, not a reason to create
three self-hosted runners up front.

## Implementation slices and observable acceptance

1. **Host/package construction.** Add per-host sdk-manager 1.16.1 assets,
   ARM64 west SDK assets, metadata-based guards, native ELF fixup checks, and
   multilib default/validation. Preserve existing amd64 hashes and dependency
   pins. Both host package derivations must evaluate; native binaries must run.
2. **Public defaults and initializer.** Apply the declared capability policy;
   keep the public nrfutil default, explicit ARM64 errors, usable host presets,
   and multi-host west templates. Smallest regression gate: execute packaged
   initializer, evaluate generated outputs for both systems, enter each native
   shell, and verify correct tools/defaults. Unsupported requests leave the
   destination and existing SDK state untouched.
3. **Check portability and CI graph.** Update west asset schema/target checks
   (`nix/flake/checks/west.nix:93-213`), nrfutil archive checks
   (`nix/flake/checks/nrfutil.nix`), backend/source fixtures and workflow hard-coded
   system references. Add TCG ARM64 udev qualification. Publish the two host
   output sets only alongside coherent package/shell/check construction.
4. **Native hosted qualification.** Run shared gate and both required native
   jobs on a fresh PR. Exercise cold-store evaluation, native package execution,
   ELF targets, environment isolation, generated consumer entry, and explicit
   unsupported paths. Both native jobs must gate trusted-main publication;
   branch protection must require the new job names, not stale `check` only.
5. **Real firmware qualification before support claims.** On an approved
   ARM64 host with prepared v3.3.0 sources and Python, run west single-image
   and sysbuild builds for the existing XIAO CPUAPP baseline. Include the
   application-owned imported manifest/module fixture, verified source paths,
   linked module symbol, compiler/Python host identity, retained ELF hashes,
   and original-source non-mutation. Extend opt-in harnesses to select a
   requested host/backend rather than always x86/both backends. Preserve
   existing amd64 evidence and perform relevant regression builds after changes.
   No native ARM64 result may be inferred from an amd64 emulated build, a
   metadata declaration, or a fake-toolchain test.
6. **User documentation and issue closure.** Update README/install/backend,
   architecture and contributor references with the two-system support matrix,
   ARM64 west choice, supported NCS release, multilib and GDB limitations, and
   qualification evidence. Document portable west consumer flakes and optional
   physical tests. Close issue only after agreed scope and native acceptance
   pass; release bump/publication remain separately authorized work.

Normal PR CI remains free of mutable SDK bootstrap, pip installation, source
updates, and hardware control. Nix package realization may fetch the declared
fixed-output compiler/tool archives, as current package CI already does.
Real SDK/Python setup and hardware acceptance remain separate approved work.

## Research validation performed

Before provisioning the Pi, read-only source/metadata inspection and Nix
evaluation established:

```text
builtins.currentSystem on this research host: x86_64-linux
current public packages systems: [x86_64-linux]
locked Nixpkgs ARM64 nrfutil/J-Link derivation evaluation: success
locked ARM64 gccMultiStdenv.cc evaluation: failure
current repository ARM64 nrfutil composition evaluation: failure
current repository ARM64 west SDK evaluation: failure
pinned Backlog.md ARM64 and product-shell derivation evaluation: success
```

No ARM64 package build, ARM64 runner execution, TCG VM run, real firmware build,
new Python environment, or hardware operation was performed during this research.
Successful evaluation is feasibility evidence only. Native runtime and resource
claims remain acceptance work, not completed tests.

Reproduce the pinned package/multilib evaluation without building or installing:

```bash
nix eval --impure --json --expr '
  let
    f = builtins.getFlake (toString ./.);
    p = import f.inputs.nixpkgs {
      system = "aarch64-linux";
      config = { allowUnfree = true; segger-jlink.acceptLicense = true; };
    };
  in {
    host = p.stdenv.hostPlatform.system;
    nrfutil = p.nrfutil.drvPath;
    jlink = p.segger-jlink-headless.drvPath;
    multilib = (builtins.tryEval p.gccMultiStdenv.cc.drvPath).success;
  }
'
```

The `--impure` flag here permits this local research expression's unlocked
checkout reference. It is not a proposed requirement for consumer flakes.

## Raspberry Pi experimentation host: read-only inventory

On 2026-10-04, the user supplied SSH alias `thomas-rpi4`. Inventory used remote
standard system tools and a local script streamed to Python over SSH. No script
was installed remotely and no packages, configuration, repositories, SDKs,
toolchains, or device permissions were changed. No probes were opened.

| Property | Observed result |
| --- | --- |
| Model | Raspberry Pi 4 Model B Rev 1.1 |
| Host ISA / userspace | AArch64 / 64-bit; system Python and GCC confirmed AArch64 ELF |
| OS | Debian 13 (trixie), os-release reports 13.7; Raspberry Pi kernel 6.18.50+rpt-rpi-v8 |
| CPU | Four Cortex-A72 cores, reported maximum 1.5 GHz |
| RAM | 3.7 GiB total, about 3.5 GiB available at inventory |
| Swap | 2 GiB zram, unused; not an additional 2 GiB of physical RAM |
| Storage | Samsung SSD 840 EVO 120 GB, root ext4, about 103 GiB available |
| SSD connection | USB storage link reports 5000 Mbit/s; no throughput benchmark performed |
| `/tmp` | tmpfs, about 1.9 GiB capacity; unsuitable as the default large-build scratch location |
| Thermal/power flags | About 43-44 C idle; `vcgencmd get_throttled` returned `0x0` |
| Network | Wired Ethernet active; HTTPS Nix/Cachix/Nordic metadata requests succeeded |
| Time | systemd-timesyncd active; NTP synchronization reported true |
| Existing tools | Python 3.13.5, GCC 14.2.0, make, pkg-config, curl/wget, file/readelf, archive tools |
| Missing tools | Nix, Git, nrfutil, west, CMake, Ninja, patchelf, QEMU executable |
| Existing SDK | No SDK at inspected standard locations; home `ncs`, `/opt/nordic/ncs`, `/nix`, `/etc/nix` absent |
| Serial/probe devices | No `/dev/ttyACM*` or `/dev/ttyUSB*`; USB enumeration showed hubs and SSD bridge only |
| Account | `thomas-rpi4`, uid 1000, includes sudo/dialout/plugdev; no kvm membership |
| Privilege | `sudo -n -l` failed with `sudo: a password is required` |

The installed kernel logged `CPU: All CPU(s) started at EL2` and
`kvm [1]: Hyp nVHE mode initialized successfully`. `/dev/kvm` exists, owned by
root:kvm with mode 0660. Current account cannot read/write it, so no KVM API or
guest execution was tested. This host is a promising alternative for a trusted
native ARM64 VM gate, but permission, Nix-builder access, memory and runtime
qualification remain necessary. Do not grant world-writable device access just
to make the check pass.

Existing apt metadata offers native `nix-bin` and `nix-setup-systemd`
2.26.3+dfsg-1, Git 2.47.3, and QEMU 10.0.13. Nothing was installed. Whether to
use distribution Nix or match the newer CI installation should be decided
before provisioning; preserve explicit experimental-feature configuration.
The system Python is not the west backend's selected Python 3.12. Use the
metadata-selected Nix interpreter rather than changing SDK dependency pins.

Pi-side HTTPS requests returned 200 for `cache.nixos.org/nix-cache-info`,
`qarnet.cachix.org/nix-cache-info`, and the official ARM64 sdk-manager 1.16.1
storage metadata. The latter matches the asset checksum recorded above. The
documentation-referenced toolchain remote-config URL returned 404; this does
not establish that every toolchain index or ARM64 bundle is absent. Once the
native manager is available, inspect its effective configuration/index lookup
rather than guessing replacement URLs.

Next experiment requires approval for provisioning Git/Nix and downloading
native nrfutil/manager packages. Use SSD-backed scratch space, initially one
concurrent Nix build and two compilation cores, and record memory/thermal cost.
Then inspect native manager versions, help, and toolchain metadata before any
approved isolated toolchain installation. Success requires native compiler and
Python execution plus firmware qualification, not archive unpacking alone.
Repository ARM64 support is still unimplemented; native locked Nixpkgs core can
be tested independently while the repository's amd64-only extension packaging
remains a known blocker.

## Approved native experiments: measured results

After the user enabled key-only SSH/passwordless sudo and approved full Pi
experimentation, Git and Debian Nix 2.26.3 were installed. This Nix release
successfully evaluated the locked inputs and built native packages; an installer
upgrade was unnecessary for these experiments. The account was added to Debian's
`nix-users` group. Original `/etc/nix/nix.conf` was backed up before enabling
flakes, one concurrent build, two compilation cores and the nixbld build group.
A systemd drop-in selects SSD-backed `/var/tmp/nix-nrf-build` for daemon scratch.
Client scratch lives under the experiment root. SSH configuration was not changed.
Symlinks under `tool-roots` retain nrfutil, Python 3.12 and Zephyr SDK as Nix GC
roots for repeat experiments; keep the copied SDK seed for the shared workspace
clones. No background experiment or VM is left running.

All working data is retained at
`/home/thomas-rpi4/nix-nrf-experiments` on `thomas-rpi4`. The detached repository
copy starts at main `78df6f5`; eight files have experiment-only modifications:
ARM64 output/asset selection, disabled multilib default, SDK host guards, VM
acceleration selection and the socket-test framing correction below. These are
not a completed portable implementation or changes to the main local checkout.
Exact patch: `state/experimental-arm64.patch`.

### Native Nordic manager: package works, toolchain does not

Native nrfutil 8.2.0 and repository-pinned sdk-manager 1.16.1 built, passed their
version checks, and report `aarch64-unknown-linux-gnu`. Cold package realization
took 93.5 seconds, including dependency downloads. Only the known archive/hash
and platform-metadata restrictions were adapted for the experiment; no manager
version downgrade or x86 emulation was used.

Actual native commands produced:

```text
sdk-manager config show --json --skip-overhead:
{"default":{"install_dir":null,"sdk_index":null,"toolchain_index":null},"sdk_indexes":{},"toolchain_indexes":{}}

sdk-manager toolchain search --json --skip-overhead:
{"mappings":{},"ncs_versions":[]}

sdk-manager toolchain install --ncs-version v3.3.0
  --install-dir /home/thomas-rpi4/nix-nrf-experiments/nordic-install
  --skip-cmake-registration:
exit 1: Error: No toolchain available for NCS version: v3.3.0
```

The manager created its isolated installation directory but installed no usable
toolchain bundle. This is native empirical evidence for the current version and
default configuration, not merely a documentation-based inference. Alternate
custom indexes/bundles and other NCS releases were not qualified.

### Packages, checks and firmware

All six package outputs realized natively: OpenOCD wrapped/unwrapped, nrfutil,
nix-nrf, udev-rules, and Zephyr SDK 0.17.0. The ARM64 SDK package built in 145.4
seconds; both compilers execute and generate ARM/RISC-V ELF objects. Their host
ELF headers identify AArch64. Both plain GDB executables pass version execution;
Python-enabled GDB remains outside the supported package boundary.

**Thirty of 33 check outputs passed** on the experimental checkout across the
retained batches, including native Python/Tcl behavior, source routing with
real west/CMake, encoded fixture protocol, initializer raw/packaged units,
Backlog.md lifecycle tests, lint/formatting, package version/offline dispatch,
NixOS module checks, and the accelerated VM gate. One existing west-bootstrap
unit test was skipped, as reported by that suite. Fake Nordic toolchain tests
do not establish a working Nordic-managed firmware backend.

The remaining three check outputs are confirmed portability blockers:

- `nrfutil-shell-boundary` and `west-shell-boundary` unconditionally evaluate
  `pkgs.gccMultiStdenv.cc.outPath` while testing multilib absence. On ARM64 they
  fail evaluation even with multilib disabled.
- `nrfutil-supply-definition` asserts a literal versioned x86_64 archive string
  and fails for the correctly pinned ARM64 asset.

Whole-flake evaluation therefore does not pass yet. The metadata/target checks
also still inspect their original x86 asset entries; passing them is not claimed
as comprehensive ARM64 metadata schema coverage.

Native initializer execution succeeds, but its generated west flake contains
only x86_64-linux outputs. A real attempt to enter it on the Pi fails. Passing
the existing initializer unit suite is not sufficient acceptance for portable
generated projects.

The session suite exposed an architecture-independent TCP test bug: one reply
was consumed with a single `recv`, so an unread frame delimiter could be mistaken
for the next response. Consuming that response through its delimiter fixed the
observed failure; all nine session tests then passed with real pinned OpenOCD
and the no-hardware dummy target. Only the disposable checkout contains the fix.

For real firmware, 48 clean repositories from the already installed local
v3.3.0 SDK were copied to the Pi as an independent seed, retaining Git objects.
Matter/CMock were excluded as in PB-024. The existing helper prepared an
application-owned imported workspace at `workspace-import`, with Nordic at
`sdk/nrf`, Zephyr at `sdk/rtos`, and the manifest-owned extra module. Nix Python
3.12.13 plus an isolated venv supplied SDK-pinned build profiles. Nordic's mirror
could not satisfy pinned PyYAML on this host; retry used PyPI and the Pi's
existing system-configured piwheels extra index. Existing SDK version constraints
were preserved; the resolved transitive environment is recorded in
`state/python-freeze.txt`. No SDK requirement files were edited.

Both real builds used public ARM64 `mkNrfShell`, explicit west/workspace mode,
`autoBootstrap = false`, and two build threads:

| XIAO nRF54L15 CPUAPP case | Result | Seconds |
| --- | --- | --- |
| Imported application, single-image | Pass | 204.6 |
| Imported application, sysbuild | Pass | 210.8 |

Sampled source/compiler/Python selections point to the intended workspace,
native Nix compiler and prepared environment. All generated module maps remain
inside the workspace and include Nordic plus the manifest-owned module. The
final ELF links `source_import_fixture_value`; hashes were independently
recomputed. Copied SDK seed tracked/Git metadata and workspace config remained
unchanged. Original local SDK state was separately rechecked after copying.
No firmware was flashed or executed on a Nordic target.

### VM and resource findings

ARM64 QEMU TCG boot reached systemd but the test driver timed out waiting for its
shell; udev acceptance did not run to completion. The combined cold VM/contributor
batch took 25.5 minutes, including many first-time dependencies. This does not
establish a usable hosted-runner TCG gate; a larger startup budget or a trusted
KVM-backed gate needs qualification.

The `acl` package was then installed and `/dev/kvm` granted read/write access to
the `nixbld` group only. Root:kvm ownership and lack of world access were retained;
this ACL is temporary until device recreation/reboot, not a persistent udev rule.
The test was rerun with `requiredFeatures.kvm = true` and `qemu.forceAccel = true`.
It passed every original udev assertion in **80.2 seconds total**, with the VM
test script completing in **42.0 seconds**. No hardware passthrough occurred.

Five-second telemetry samples across the instrumented runs showed a maximum
61.8 C, no throttling/undervoltage flags, at least about 1.4 GiB available memory,
and at most about 244 MiB zram swap use. These are sampled workload measurements,
not a stress-test certification. Final kernel-log inspection found no OOM events.
Retained data occupies about 7.1 GiB in the
experiment root plus 15 GiB in `/nix/store`; root filesystem still has about
80 GiB free. Pi is practical for small firmware acceptance and trusted native
VM tests, while hosted ARM64 CI remains preferable for routine PR throughput.

Raw reports/logs and the patch are also copied to
`/tmp/opencode/rpi4-first-evidence` on the workstation. Relevant report names:
`toolchain-investigation.json`, `six-native-packages.json`,
`firmware-qualification.json`, `native-kvm-udev.json`,
`remaining-blockers.json`, and `performance-summary.json` (local derived summary).
These are retained session artifacts, not durable published team evidence.

Next implementation should replace the experiment-only retargeting with
two-host asset/capability metadata, portable initializer outputs, explicit
Nordic-backend refusal, corrected check assumptions/framing, and the shared/native
CI graph. Do not close issue 11 or advertise parity based on this experiment.
