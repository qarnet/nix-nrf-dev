# West toolchain coverage, installation alternatives and environment ownership

Research snapshot: 2026-10-04, NCS v3.3.0 and repository main `78df6f5`.
This extends the [Linux host platform plan](linux-host-platform-plan.md).
Findings distinguish current implementation, native experiments, and recommended
future work. No Docker backend or new environment-management API is implemented.

## Conclusions

- The native Linux ARM64 Nordic toolchain-bundle index is publicly declared but
  empty. This explains the Pi's native sdk-manager result; changing installation
  prefix, source workspace, or region does not manufacture a native bundle.
- Nordic documents manual installation using Zephyr SDK plus Python requirements.
  Our west approach follows that alternative, but Linux ARM64 remains outside
  Nordic's NCS supported-host matrix. Project qualification must be scoped.
- Managed west bootstrap explicitly installs the three documented aggregate
  requirement inputs. Existing-workspace mode installs nothing. Neither model
  guarantees the whole Nordic bundle's inventory or exact Python resolution.
- Readiness currently checks only five Python imports and west version. A native
  public-boundary audit passed despite 24 declared distributions missing.
- Keep immutable tools in Nix store and mutable Python per user/workspace. Do not
  default to a root-owned `/opt/ncs` environment or place consumer state in this
  library checkout.
- Nordic's published Docker image is a credible optional digest-pinned AMD64
  build backend, not a native Linux ARM64 solution. Keep that work separate from
  issue 11's native host support.

## 1. Official installation alternatives

Pinned [NCS v3.3.0 installation source](https://github.com/nrfconnect/sdk-nrf/blob/v3.3.0/doc/nrf/installation/install_ncs.rst#L436-L703)
documents an alternative system-wide/manual method. It explicitly recommends
Python virtual environments to avoid system/user package conflicts, installs
three Python requirement files, then directs users to Zephyr SDK. Matter needs
GN additionally. "System-wide" in this document is not an instruction to install
Python dependencies into system Python or mandate `/opt`.

The supplied latest Zephyr links describe alternative compiler setups and using
or omitting SDK host tools. They are Zephyr 4.4.99 documentation, not an assurance
that every listed compiler supports all NCS v3.3.0 features. Host GCC is useful
for host/simulation builds, not a replacement Cortex-M firmware compiler.
GNU Arm Embedded is a potential separately qualified path, but replacing the
already working Zephyr SDK 0.17.0 adds compatibility work without fixing an
observed native-build problem.

The VS Code extension's automatic management also uses a bundled manager. Its
external Zephyr SDK/PATH toolchain support is a possible front end to the native
environment, not evidence of another Nordic ARM64 compiler payload. Public
Zephyr SDK sources can be rebuilt, but no public Nordic bundle-production guide
or verified native Nordic bundler route was found. Custom bundle IDs/indexes
select supplied payloads; macOS ARM64 binaries are not Linux ARM64 binaries.

Evidence: pinned SDK `doc/nrf/installation/install_ncs.rst:436-440,656-679,695-702`,
`recommended_versions.rst:17-42`, `scripts/tools-versions-linux.yml`; Nordic MCP
official installation/VS Code guidance; upstream Zephyr SDK release/build docs.
Latest documentation versions must not replace the v3.3.0 tool/version baseline.

## 2. JFrog: useful public metadata and missing ARM64 payload

The UI links return a JavaScript shell to generic fetchers. Anonymous REST and
artifact requests with `Accept: application/json` and a non-browser client
provide useful metadata. No authentication bypass or private repository probing
was attempted. Some folder-list APIs return 403, and some parent folders return
404 despite accessible known child artifacts; those responses alone are not
proof of global absence.

Actual public toolchain config:

```text
https://files.nordicsemi.com/artifactory/NCS/external/bundles/config.json
```

Schema 3 declares `aarch64-unknown-linux-gnu`, pointing at:

```text
https://files.nordicsemi.com/artifactory/NCS/external/bundles/v3/index-linux-aarch64.json
```

Directly verified HTTP 200, JSON body `[]` plus newline, three bytes. SHA-256:
`37517e5f3dc66819f61f5a7bb8ace1921282415f10551d2defa5c3eb0985b570`.
[Storage metadata](https://files.nordicsemi.com/artifactory/api/storage/NCS/external/bundles/v3/index-linux-aarch64.json)
reports creation/modification `2026-01-12T10:53:13.804Z` and the same checksum.
The config hash is
`1f8c57ab6eef530874e190ddebf58a2882ab0f8b1929c32a616aa337acdc65e1`.

Research inspected all five default platform indexes and the public v3 bundle
directory: 563 archives, none named as Linux ARM64 payloads. Linux x86_64 index
has 237 records and macOS ARM64 234; these counts include aliases, not unique
archives. v3.3.0 Linux x86_64 maps to
`ncs-toolchain-x86_64-linux-911f4c5c26.tar.gz`; v3.4.1 and preview entries are also
present for supported hosts. Linux ARM64 remains empty in the inspected inventory.
Scope is current public default inventory, not every private/historical index.

Separate SDK source config/index lives under:

```text
https://files.nordicsemi.com/artifactory/ncs-src-mirror/external/sdk-manager/config.json
https://files.nordicsemi.com/artifactory/ncs-src-mirror/external/sdk-manager/index.json
```

The v3.3.0 source archive has no host-platform selector. Its association with a
toolchain version does not establish native toolchain availability. Source and
host-executable bundle ownership remain separate.

The ARM64 command registry advertises nrfutil 8.2.1 and sdk-manager 1.16.1 as its
latest entries at inspection. The project remains pinned to its tested core and
manager; no upgrade was performed. Command packages are distinct from bundles.

### Python mirror limitation confirmed

Both Nordic PyPI virtual indexes expose five PyYAML 6.0.3 files, but no Linux
ARM64 wheel or source distribution. PyPI provides the needed CPython 3.12
AArch64 wheel, with SHA-256:
`9149cad251584d5fb4981be1ecde53a1ca46c891a79788c0df828d2f166bda28`.
This is a supply/platform gap, not a version conflict requiring relaxed SDK pins.

Sources:
[Nordic package listing](https://files.nordicsemi.com/artifactory/api/pypi/nordic-pypi/simple/pyyaml/),
[PyPI release metadata](https://pypi.org/pypi/PyYAML/6.0.3/json), public JFrog
storage/index metadata. The inspected `public-pypi/public` listing likewise
contained no Linux AArch64 wheel filenames, while universal wheels/sdists may
still serve native hosts. This is not a guarantee about every Nordic Python repo.

## 3. What current west bootstrap installs

`nix/backends/west/versions.nix:58-71` selects:

```text
zephyr/scripts/requirements.txt
nrf/scripts/requirements.txt
bootloader/mcuboot/scripts/requirements.txt
```

These exactly match Nordic's pinned manual-install recipe. Installing the `west`
package alone installs only west's own dependencies; `west update` fetches
repositories, not their Python requirements. Our bootstrap separately runs pip.

`bin/backends/west/nix-nrf-west-bootstrap.run_setup` (`:387-475`) does, after
approval when not ready:

1. Create `.venv` using the selected Nix Python, if missing.
2. Install initial tested west (1.4.0 for this metadata entry), if needed.
3. Initialize the release-specific SDK workspace, if missing.
4. Run `west update`.
5. Run the venv's `python -m pip install -r` for each declared input, in order.

Aggregate includes matter:

| Requirement input | Includes |
| --- | --- |
| Zephyr aggregate | base, build-test, run-test, extras, compliance |
| Nordic aggregate | base, build |
| MCUboot scripts | signing/image-related dependencies and pytest |

The Zephyr extras header calls that profile optional/developer workflow. Thus
the current default is broader than a minimal firmware build profile, but still
does not include all Nordic CI/extra, documentation, or feature-specific inputs.

The SDK's fixed requirements represent a larger pinned union with transitive
resolution. They contain extras and platform markers; `-r` requests packages,
whereas `-c` only constrains packages requested elsewhere. The fixed file cannot
be passed unmodified as pip constraints because constraints reject extras.

Current implementation pins only cbor2 5.9.0 across pip commands. Other versions
remain resolution-dependent, including west after SDK requirements installation.
Nix pins the interpreter derivation through its input, but selected Python minor
3.12 is not a promise of Nordic's exact Python patch version or wheel artifacts.
The Pi's earlier manually fixed-profile setup was stronger than this shipped
managed-bootstrap version policy; do not infer managed setup parity from it.

`source.mode = "workspace"` instead returns after checks (`main:544-554`), even
with `--yes`. It never installs or repairs Python or sources. Caller prepares
`.venv` or selects an existing `pythonEnvironment`. Preserve this ownership
contract when improving checks/setup options.

`west packages pip --install` is not an automatic substitute for the recipe:
it discovers registered module package-manager metadata. Pinned Nordic module
metadata does not register its Python requirements; MCUboot registers a different
requirements file. Using it alone would not guarantee all three NCS inputs.

## 4. Readiness is incomplete: native public-boundary evidence

Current `readiness` (`:280-320`) verifies source/requirement files, Python/pip/west
executables, imports of `west,yaml,elftools,zcbor,nrfregtool`, and a compatible west
version. It does not validate the declared dependency graph, all version pins,
Python interpreter identity, native-wheel usability, or completed setup profile.

On the Pi, the existing build-profile venv contained 77 distributions. A
managed-shaped test fixture linked that environment to the copied SDK seed and
ran real public `bootstrap --workspace <seed> --check --print-sdk-path`. It
returned zero although **25 applicable requirement expressions representing 24
distinct distributions** were missing. `pip check` also returned zero: it checks
installed distributions' dependency consistency, not presence of all requested
SDK requirements. Examples missing: mypy, pyOCD, coverage, gcovr, OpenCV, Pillow,
GitPython, SPDX tooling. Basic firmware builds remain valid evidence, not proof
of that wider development environment.

Ready short-circuit (`main:565-573`) would also skip provisioning these missing
packages. Proposed acceptance: under managed mode the selected advertised profile
must be genuinely complete; a read-only check must report missing/incompatible
requirements without installing anything. Validate installed metadata against
profile inputs, extras and markers, plus relevant executable/native import probes.
`pip check` is useful but insufficient alone.

Evidence: Pi `state/west-coverage-audit.json`; workstation copy at
`/tmp/opencode/rpi4-first-evidence/west-coverage-audit.json`. The fixture adds only
a test-owned `.venv` symlink; no SDK requirement/config files were edited.

## 5. Native tool coverage is not Nordic bundle parity

`nix/backends/west/shell.nix:170-191` provides compiler SDK, Python, CMake, Ninja,
dtc, gperf, Git, ccache, dfu-util, file, xz, make, which, OpenOCD and the project
facade/west wrapper. Multilib is optional on the supported x86 host.

| Capability | Current west boundary |
| --- | --- |
| ARM/RISC-V compiler SDK | Exact Zephyr SDK 0.17.0 release assets |
| Host build tools | Nix packages; not necessarily Nordic bundle versions |
| Python packages | Declared manual recipe when provisioning runs; incomplete readiness and mostly loose resolution |
| GN / Matter build | GN not supplied by default; Matter unqualified |
| Separate bundled nanopb tools | Not reproduced wholesale; workspace/module tools require their own validation |
| nrfutil/device/J-Link workflows | Not included by west shell; not interchangeable with OpenOCD |
| SDK-specific QEMU hosttools | SDK hosttools installer removed; no default QEMU package in consumer west shell |
| Python-enabled GDB | Known unsupported legacy ABI dependencies |
| Documentation / broad SDK CI / SBOM | Additional Python/native tools; not generally qualified |

The installed Nordic bundle has 184 distributions, including pip, and a bundled
environment supplying loader/Python/Nordic command variables. Count differences
alone do not prove missing compile prerequisites, but make full-inventory claims
unsafe. Even the bundle is not every optional SDK workflow: its installed
inventory lacks some documentation/SBOM distributions.

Python wheels can embed native executables or load native libraries. NixOS needs
explicit executable/library handling; success on Debian with system libraries
does not establish a hermetic NixOS closure. Keep host-library/tool coverage
profile-specific rather than globally adding foreign loader paths.

## 6. Environment location recommendation

Current locations already differ from the proposed alternatives:

| Ownership mode | Current default |
| --- | --- |
| nrfutil on Linux | SDK `~/ncs/<version>`, bundles `~/ncs/toolchains/<bundle-id>` |
| Managed west | `~/ncs/<version>/.venv` |
| Existing-source west | `<selected-workspace>/.venv`, or explicit existing `pythonEnvironment` |
| Immutable compiler/native tools | Nix store, shared by Nix rather than duplicated in venv |

The library checkout is not an installation prefix for consumers. `/opt/ncs` is
not Linux nrfutil's default. Nordic's macOS prefix and container `/opt` layout
are separate cases, not reasons to require privileged Linux installation.

**Recommendation:** retain current per-user managed default and caller-owned
workspace/local environment behavior for issue 11. Keep project-specific Python
dependencies local when they differ. Support an administrator-prepared `/opt`
workspace/environment through existing explicit workspace/Python selection,
without sudo or shared mutation in shell/bootstrap.

If a reusable per-user managed environment mechanism is added separately, key
it by host system, NCS release, Python derivation, selected dependency profile
and requirement/lock fingerprint. Keep separate environments for modified SDK
requirements and host architectures, provide locking/completion state, and
retain interpreter GC roots. Do not share one mutable root-owned venv among
users/projects or silently repair caller environments.

Python [venv documentation](https://docs.python.org/3.12/library/venv.html)
describes environments as disposable and non-portable: shebang/interpreter paths
are absolute. Recreate at a new prefix; do not move or copy a populated venv.
Nix [Python environment guidance](https://nix.dev/guides/recipes/python-environment.html)
also distinguishes Python dependencies from native tools in a declarative shell.

One existing configuration trap: managed CLI `bootstrap --workspace` affects that
command only, while the shell wrapper/hooks still select `$HOME/ncs/<version>`.
It is not a coherent managed-prefix option. A future prefix setting must propagate
through shell, bootstrap, doctor and readiness. Existing-source mode is the
current supported way to select a different prepared workspace consistently.

## 7. Official Docker image: separate candidate backend

Anonymous OCI registry research examined all 145 currently listed tags. All
runnable image configs/descriptors identify **linux/amd64**; two OCI indexes
also contain attestation entries marked unknown/unknown, not ARM runnable images.
No layers were downloaded and no container was executed. This is metadata
coverage at inspection time, not a statement about private/deleted images.

NCS v3.3.0 tag and bundle-ID tag 911f4c5c26 resolve to:

```text
ghcr.io/nrfconnect/sdk-nrf-toolchain@sha256:f24d8932ff081ebcd8da9c248f4449bdabe461c0620a7a4ac9e95eb577ba2276
```

Manifest/config byte hashes were verified. Compressed layer descriptors total
about 1.69 GB. `latest` currently resolves to v3.5.0-preview2, not the highest
stable v3.4.1; there is no stable tag. Pin digest and SDK source revision, never
rely on latest or assume bundle-ID tags immutable.

Pinned Dockerfile and live config use Ubuntu 24.04, despite README's 22.04 claim.
The image installs an x86 Nordic bundle using legacy toolchain-manager, initializes
environment through Bash/BASH_ENV, defaults to container root, and conditionally
installs J-Link after license acceptance. Docker on ARM would require explicit
amd64 emulation or remote execution; `--platform` does not turn payloads native.

Sources: [official package](https://github.com/nrfconnect/sdk-nrf/pkgs/container/sdk-nrf-toolchain),
[pinned Docker source](https://github.com/nrfconnect/sdk-nrf/blob/v3.3.0/scripts/docker/Dockerfile),
[official README](https://github.com/nrfconnect/sdk-nrf/blob/v3.3.0/scripts/docker/README.rst),
[Docker platform model](https://docs.docker.com/build/building/multi-platform/).

**Recommendation:** consider a separate optional build-only container backend
for AMD64 bundle compatibility and CI. Do not add it as issue 11's native ARM64
path or silently fall back to emulation. Runtime acceptance must prove image
selection, environment initialization, UID/GID output ownership, path mapping,
fresh backend-specific build caches, compiler/Python identity, and real builds.
Container daemon availability is an explicit external prerequisite.

Do not copy the README's privileged hardware recipe into default backend setup.
No automatic `/dev` mounts, J-Link installation, source update, broad Git
safe.directory wildcard, or flashing. Rootless operation and hardware/debug
forwarding require separate validation; rootful/rootless UID mapping differs.
Bind mounts refer to daemon-host paths, so remote daemons need explicit transfer
or shared-source policy. Mounting over `/opt` would hide container tools.

## Recommended next work and verification

1. Complete native two-host package/backend metadata and explicit unsupported
   Nordic-backend behavior, using the already proven native Zephyr SDK route.
2. Define supported Python/tool profiles before claiming environment parity.
   Preserve current manual-recipe default until an explicit profile change is
   accepted; the lean build profile is useful, but not all development tools.
3. Add versioned constraints/lock provenance and real selected-profile validation.
   Handle public index selection explicitly; avoid inherited system pip indexes
   and distinguish missing wheels from incompatible version requirements.
4. Test native helpers/imports as well as successful pip resolution, especially
   on NixOS. Optional GN/Matter, QEMU, signing/debug and documentation coverage
   should have their own qualified requirements and smallest real workflow test.
5. Keep per-user/caller-owned paths. Treat a managed-prefix/cache redesign and
   digest-pinned container backend as separate scoped work, not implicit additions
   to ARM64 support. No product release or hardware claim follows from research.

Smallest readiness regression: public managed `bootstrap --check` on a prepared
environment missing an applicable selected-profile requirement must fail without
network/install/source mutation; the same environment with the requirement
installed must pass. Workspace mode must retain non-repair behavior. Container
metadata availability alone is not runtime acceptance.
