# nix-nrf-dev

Reusable Nix tooling for Nordic nRF firmware development: an NCS toolchain dev
shell and CMSIS-DAP flashing via a pinned openocd-master build. Verified on
nRF5340 and nRF54L15 hardware.

## Install

### New project (template)

```bash
nix flake init -t github:qarnet/nix-nrf-dev
direnv allow          # or: nix develop
```

### Existing project (flake input)

```nix
{
  inputs.nix-nrf-dev = {
    url = "github:qarnet/nix-nrf-dev";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

The `inputs.nixpkgs.follows = "nixpkgs"` directive lets the consumer's own
Nixpkgs revision replace the one pinned in nix-nrf-dev's `flake.lock` — and
with it the packaged nrfutil/sdk-manager versions.

```nix
devShells.default = nix-nrf-dev.lib.${system}.mkNrfShell {
  backend = "nrfutil";
  ncsVersion = "v3.3.0";
};
```

The shell provides `west` + Zephyr toolchain (via nrfutil sdk-manager, with
lazy SDK/toolchain bootstrap on the first `west` invocation), `ZEPHYR_BASE`,
`openocd` (master build), `nrfutil`, the `nix-nrf` CLI facade (`nix-nrf
versions`, `nix-nrf probes`, `nix-nrf bootstrap`, `nix-nrf doctor`), and
multilib GCC for `native_sim`.

**Scoped toolchain environment:** Nordic's sdk-manager env script exports
`PYTHONHOME`, `PYTHONPATH`, `LD_LIBRARY_PATH` and `GIT_EXEC_PATH` — toxic to
non-toolchain tools. `mkNrfShell` does NOT eval it into the shell; a `west`
wrapper loads it only inside west's process tree. The shell itself stays
clean — `nix`, agents, and editors launched from it work normally.

## SEGGER / J-Link

The packaged nrfutil derivation in Nixpkgs unconditionally depends on
`segger-jlink-headless` and sets `NRF_JLINK_DLL_PATH` — **including when only
the sdk-manager extension is composed**. This repository therefore configures
`allowUnfree = true` and `segger-jlink.acceptLicense = true` in its own
Nixpkgs import. `inputs.nixpkgs.follows` only replaces the Nixpkgs *source*
revision; nix-nrf-dev still imports that source with its own config, so
consumers using the default package need no extra configuration. Consumers
who construct or override nrfutil from their own `pkgs` — a `nrfutilPackage`
override, or their own `pkgs.nrfutil.withExtensions [ "nrfutil-sdk-manager" ]`
— must configure `allowUnfree = true` and `segger-jlink.acceptLicense = true`
(or equivalent per-package license handling) or that package will fail to
build. There is no sdk-manager-only composition that avoids J-Link.

## Backends

`mkNrfShell` takes a `backend` argument (default `"nrfutil"`):

- `"nrfutil"` — uses Nordic's sdk-manager for the NCS toolchain environment.
  This is the default and recommended backend. Omit the argument or pass
  `backend = "nrfutil"` explicitly; both behave identically.
- `"west"` — **experimental** hybrid backend: Nix owns the exact Zephyr SDK,
  host tools, and Python interpreter, while the official mutable west
  workspace and a version-local venv own the NCS source, west, and workspace
  Python requirements — no nrfutil/sdk-manager. Currently supports only
  `v3.3.0` on `x86_64-linux` (metadata-driven in
  `nix/backends/west/versions.nix`).
- `"sdk-nrf"` — reserved for a future Nix-native build environment (see
  `goals.md`). It is **not** implemented: any unsupported value fails at Nix
  evaluation with an unsupported-backend error instead of silently falling
  back.

```nix
# nrfutil (default, recommended):
devShells.default = nix-nrf-dev.lib.${system}.mkNrfShell {
  backend = "nrfutil";
  ncsVersion = "v3.3.0";
};

# west (experimental; v3.3.0 / x86_64-linux only):
devShells.default = nix-nrf-dev.lib.${system}.mkNrfShell {
  backend = "west";
  ncsVersion = "v3.3.0";
};
```

`ncsVersion` is a **required** argument — every caller selects an NCS release
explicitly (there is no `"latest"` alias or default). `"v3.3.0"` is the tested
release used by this repository's own shells, examples, and template, but it
is not an architecture lock. For `backend = "west"`, the release must exist in
the west backend metadata; an unknown release fails evaluation naming the
supported west versions.

Toolchain selection (nrfutil backend):

- Omit `toolchainBundleId` (normal case) → the west wrapper runs
  `nrfutil sdk-manager toolchain env --ncs-version <ncsVersion>`, selecting
  the newest compatible patched toolchain for that release.
- Set `toolchainBundleId = "<bundle-id>"` → the wrapper runs
  `nrfutil sdk-manager toolchain env --toolchain-bundle-id <bundle-id>`,
  selecting that exact bundle. If it fails, the error names the exact bundle
  rather than falling back to the newest compatible one.

`backend = "west"` rejects `toolchainBundleId` and non-default
`nrfutilPackage` overrides (no nrfutil participates); `autoBootstrap`,
`packages`, `inputsFrom`, `name`, `withMultilib`, and `extraShellHook` behave
like the nrfutil backend.

## Bootstrap

`nix-nrf bootstrap` provisions the configured NCS SDK source and selected
toolchain before they are needed. It is **explicit** (`nix-nrf bootstrap`),
**lazy** (the `west` wrapper checks on every invocation and installs only when
something is missing), and **manual** when `autoBootstrap = false`:

```text
$ nix-nrf bootstrap                  # explicit; prompts before downloading
$ nix-nrf bootstrap --yes            # approve the required downloads up front
$ nix-nrf bootstrap --check          # inspect only; never installs (exit 1 when missing)
$ nix-nrf bootstrap --print-sdk-path # print only the absolute SDK root on success
```

- `--yes` and `NIX_NRF_BOOTSTRAP_YES=1` bypass the interactive confirmation.
  Nordic's sdk-manager itself has **no** `--yes` option — this flag is the
  repository's confirmation bypass and is never forwarded to nrfutil. Without
  a terminal, unapproved bootstrap fails with the exact re-run command and
  exit 2 instead of mutating state.
- With no exact `toolchainBundleId`, a missing SDK or toolchain runs
  `nrfutil sdk-manager install <ncsVersion>` (SDK source plus the newest
  compatible patched toolchain for the release).
- With an exact `toolchainBundleId`, only the missing actions run:
  `nrfutil sdk-manager sdk install <ncsVersion>` for the SDK source and
  `nrfutil sdk-manager toolchain install --toolchain-bundle-id <bundle-id>`
  for that exact toolchain — it never downloads the newest compatible
  toolchain accidentally.
- All status, prompts, and nrfutil progress go to stderr; stdout stays empty
  unless `--print-sdk-path` succeeds, so command substitution stays
  machine-readable.

The `west` wrapper bootstraps lazily (`autoBootstrap = true`, the default):
each invocation ensures the selected SDK source and toolchain exist (installing
only when missing and approved), exports `ZEPHYR_BASE` inside west's process,
then loads the scoped toolchain env. With `autoBootstrap = false`, west only
checks and, if anything is missing, prints that automatic bootstrap is disabled
plus the exact `nix-nrf bootstrap` remediation — it never mutates.

Shell entry is always non-mutating: the shell hook runs the read-only
`--check` path and exports `ZEPHYR_BASE` only when the installed SDK is found.
A bootstrap that installs a missing SDK happens inside west's process; re-enter
the shell (or `direnv reload`) to pick up `ZEPHYR_BASE` for non-west commands.

## Clean bootstrap verification (clean-room)

`tests/clean-room/run.sh` proves the whole flow from an empty, isolated Linux
home: it bootstraps NCS v3.3.0 and the selected toolchain under a
script-created `HOME`, re-enters the shell, derives `ZEPHYR_BASE` from the
isolated installation, and runs a real `west build -p always --sysbuild` of
the XIAO nRF54L15 blinky sample, verifying the resulting `zephyr.elf` and
`domains.yaml`. It never flashes hardware.

```bash
bash tests/clean-room/run.sh   # downloads several GiB; needs >= 25 GiB free
```

The isolated home is removed on exit unless `NIX_NRF_CLEAN_KEEP=1`; a
caller-provided `NIX_NRF_CLEAN_HOME` is never removed. The test runs
manually via `.github/workflows/clean-room.yml` (`workflow_dispatch` on the
`nrf-hardware` self-hosted runner, no schedule) — normal PR CI never
downloads SDK/toolchain bundles. See `tests/clean-room/README.md`.

**Proven 2026-08-05 (Linux x86_64):** `bash tests/clean-room/run.sh` exited 0
with bootstrap 458 s, blinky sysbuild 66 s, and a measured clean-home NCS
install of 13 G under `$HOME/ncs/v3.3.0` with toolchain bundle `911f4c5c26`;
artifacts `blinky/zephyr/zephyr.elf` and `domains.yaml` were asserted
non-empty. The GitHub workflow was not dispatched; evidence is the local real
run (see `docs/development/clean-bootstrap-versioning-plan.md`, Phase 3).

## Experimental: west backend (public, v3.3.0 / x86_64-linux only)

The west backend (`mkNrfShell { backend = "west"; ... }`) is the hybrid
model: Nix supplies the exact Zephyr SDK, host tools, and Python interpreter,
while the official mutable west workspace and a version-local Python venv own
the NCS source, west, and workspace Python requirements — no nrfutil/
sdk-manager and no Nordic toolchain bundle. See
`docs/development/archive/west-backend-environment-handoff.md` and
`docs/development/west-backend-status.md`. This supersedes the earlier
`sdk-nrf` prototype plan (`docs/development/archive/sdk-nrf-prototype-handoff.md`).
It is **experimental**: only `v3.3.0` on `x86_64-linux` is supported, and the
nrfutil backend remains the default/recommended fallback.

Backend-aware surface:

```text
packages.west-zephyr-sdk-v3_3_0      exact Zephyr SDK 0.17.0 (minimal + ARM/RISC-V compilers)
nix-nrf versions                     lists west backend metadata releases (never nrfutil)
nix-nrf bootstrap                    creates/updates the mutable west workspace + venv
tests/west-backend/run.sh            clean-room proof (real setup + blinky sysbuild)
checks.west-bootstrap-tests          fake-boundary fixture tests
checks.west-versions-tests           fake-boundary versions command tests
checks.west-backend-metadata         versions.nix schema check
checks.west-backend-quoting          metadata quote-embedding regression
checks.west-shell-boundary           public shell boundary gate (fake-ready workspace)
```

Typical flow inside a public west shell:

```bash
nix-nrf bootstrap --yes     # creates $HOME/ncs/v3.3.0 workspace + .venv (multi-GiB; approved)
nix-nrf bootstrap --check   # read-only readiness (exit 0 ready, 1 missing)
west build -p always -b xiao_nrf54l15/nrf54l15/cpuapp --sysbuild zephyr/samples/basic/blinky
```

The west backend supports only `x86_64-linux`. The real clean-home proof
(`tests/west-backend/run.sh`) downloads several GiB; each run requires its
own fresh explicit approval — approval is never permanent. Normal CI never
downloads a workspace.

**Proven 2026-08-05 (Linux x86_64):** the prototype-phase
`bash tests/west-backend/run.sh` exited 0 from a script-created isolated
`/tmp` HOME: `nix-nrf bootstrap --yes` completed in 436 s (west init + west
update + venv requirements with the then-current metadata constraint
`cbor2<6`, which installed `cbor2==5.9.0`; since tightened to the exact
`cbor2==5.9.0` pin), the scoped west wrapper then built
`xiao_nrf54l15/nrf54l15/cpuapp` sysbuild blinky in 18 s, artifacts
`zephyr.elf`/`domains.yaml` were asserted non-empty, and the temp home was
removed on exit. Workspace (incl. venv) 6.4 G, build 29 M; Zephyr SDK came
from `/nix/store/...-zephyr-sdk-0.17.0`; `nrfutil` absent throughout. See
`docs/development/west-backend-status.md`.

**Proven 2026-08-06 (Linux x86_64, public API rerun):** `bash
tests/west-backend/run.sh` exited 0 through the public
`backend = "west"` shell from a script-created isolated `/tmp` HOME:
`nix-nrf bootstrap --yes` 474 s (west init + west update + venv requirements
with the metadata `cbor2==5.9.0` pin), scoped `west` sysbuild blinky 19 s,
workspace (incl. venv) 6.4 G / build 29 M, artifacts `zephyr.elf` and
`domains.yaml` asserted non-empty, west v1.4.0, compilers `(Zephyr SDK
0.17.0) 12.2.0`, `ZEPHYR_SDK_INSTALL_DIR` under `/nix/store`, `nrfutil` and
the temporary `nix-nrf-west-setup` command absent from PATH, zero approval
prompts on the ready second entry (the lazy bootstrap is a no-op when the
workspace is ready), and the temp home removed on exit. See
`docs/development/west-backend-status.md`.

## nix-nrf CLI

`nix-nrf` is the project's command facade: `nix-nrf versions`, `nix-nrf probes`,
`nix-nrf bootstrap`, and `nix-nrf doctor`. It dispatches to the packaged tools
with `exec`, so delegated stdout, stderr, options, and exit status are
preserved:

```
$ nix-nrf versions
$ nix-nrf versions --json
$ nix-nrf versions --help
$ nix-nrf probes
$ nix-nrf probes --find nrf53
$ nix-nrf probes --help
$ nix-nrf bootstrap
$ nix-nrf bootstrap --check
$ nix-nrf bootstrap --help
$ nix-nrf doctor
$ nix-nrf doctor --json
$ nix-nrf doctor --help
$ nix-nrf help versions
$ nix-nrf help probes
$ nix-nrf help bootstrap
$ nix-nrf help doctor
```

`nix-nrf versions` is backend-aware: in a nrfutil shell it delegates to
`nrfutil sdk-manager search` without parsing or maintaining a local version
list (sdk-manager remains the runtime authority); in a west shell it lists the
repository-supported west backend metadata releases (sorted text or `--json`
string array) and never invokes nrfutil. `nix-nrf probes` runs the internal
probe command module (`$out/libexec/nix-nrf/probes`); `nix-nrf bootstrap` runs
the internal bootstrap command module (`$out/libexec/nix-nrf/bootstrap` — the
nrfutil-backed or the west workspace/venv module, depending on the shell's
backend); `nix-nrf doctor` runs the internal doctor command module
(`$out/libexec/nix-nrf/doctor`); there are no standalone
`nrf-probes`/`nrf-bootstrap`/`nrf-doctor` binaries or packages. The old
`nrf-sdk-versions` command is removed; use `nix-nrf versions`.

## Hardware access diagnostics (`nix-nrf doctor`)

`nix-nrf doctor` is read-only environment and probe-access diagnostics. It
distinguishes a ready versus missing SDK/toolchain, no visible debug probe,
visible-but-inaccessible CMSIS-DAP/J-Link candidates, at least one accessible
candidate, and mixed access. It never opens probe nodes, never invokes
OpenOCD/J-Link tools, never runs a mutating bootstrap (only the `--check`
path), never runs `sudo`, and never installs or reloads host udev rules — it
prints the exact remediation instead:

```text
$ nix-nrf doctor
SDK/toolchain
  status: pass
  NCS v3.3.0 ready: /home/user/ncs/v3.3.0

User access
  user: user (uid 1000)
  groups: dialout users wheel

Debug probes
  1 accessible probe(s), 1 with limited access
  [OK] cmsis-dap  Debugprobe on Pico (CMSIS-DAP) (Raspberry Pi, ...)  /sys/bus/usb/devices/5-2.4
    usb /dev/bus/usb/005/033: exists, readable, writable
  [BLOCKED] cmsis-dap  Seeed Studio XIAO nrf54 CMSIS-DAP (Seeed Studio, ...)  /sys/bus/usb/devices/1-9
    hidraw /dev/hidraw0: exists
    usb /dev/bus/usb/001/017: exists, readable, writable

Remediation
  NixOS:
    imports = [ nix-nrf-dev.nixosModules.default ];

  Other Linux:
    nix build .#udev-rules
    Install result/lib/udev/rules.d/60-openocd.rules using your distribution's
    documented udev procedure, reload rules, then replug probe.

  Packaged udev rule: /nix/store/...-nix-nrf-udev-rules/lib/udev/rules.d/60-openocd.rules

  OpenOCD should not run as root.

PASS
```

Candidate recognition is descriptor-based (product/manufacturer strings), not
a repository VID/PID catalog: CMSIS-DAP when the product contains
`cmsis-dap`, J-Link when the product contains `j-link`/`jlink` or the
manufacturer contains `segger`. Access is decided by `os.access` on the mapped
nodes — hidraw for CMSIS-DAP (USB-node fallback when the probe exposes no
HID interface, e.g. CMSIS-DAP v2 bulk), USB bus node for J-Link. The base
`packages.nix-nrf` has no NCS default, so its doctor skips the SDK check but
still diagnoses hardware; the shell's `nix-nrf` checks the configured
selector. Both the standalone package and the shell's `nix-nrf` doctor carry
the exact packaged udev-rule store path (the shell's comes from internal
closure wiring in `mkNrfShell`, not a consumer option) and print it as
`Packaged udev rule:` in the remediation.

Exit: `0` when the SDK is pass/skip and at least one candidate is accessible,
`1` for SDK or hardware failure, `2` for CLI usage errors. `--json` emits one
JSON object with stable fields (`ok`, `sdk`, `user`, `hardware`,
`remediation`). In a west shell the human heading/status/remediation label
becomes `west workspace/Zephyr SDK` (JSON fields and exit codes never change);
the doctor still checks the west workspace/venv only through the read-only
`--check --quiet --print-sdk-path` contract.

## NixOS udev rules

OpenOCD's canonical `60-openocd.rules` (pinned revision
`e6752ecbcf72efe4e213e8418e381ff2e0ffdf54`) grants non-root access to
CMSIS-DAP and J-Link probes (`MODE="660"`, `GROUP="plugdev"`,
`TAG+="uaccess"`, covering `usb`, `tty`, and `hidraw` subsystems). The flake
exposes it as `packages.udev-rules`, copied byte-for-byte from the built
OpenOCD source (no repository VID/PID catalog), plus a minimal NixOS module
that activates it on the current system:

```nix
{
  inputs.nix-nrf-dev.url = "github:qarnet/nix-nrf-dev";
  # ...
  nixosConfigurations.myHost = nixpkgs.lib.nixosSystem {
    modules = [ { imports = [ nix-nrf-dev.nixosModules.default ]; } ];
  };
}
```

`services.udev.packages` imports every `etc/udev/rules.d` and
`lib/udev/rules.d` file from the listed packages, so passing OpenOCD itself
would not activate its contrib rule — the relocation package exists for that
reason. On non-NixOS Linux, `nix build .#udev-rules` and install
`result/lib/udev/rules.d/60-openocd.rules` via your distribution's documented
udev procedure, then reload rules and replug the probe. OpenOCD should not run
as root.

## Advanced: overriding nrfutil

`mkNrfShell` accepts a public `nrfutilPackage` override (defaulting to this
repository's composed package: Nixpkgs nrfutil with the sdk-manager
extension). Every nrfutil invocation — the `west` wrapper and the `nix-nrf
versions`/`bootstrap` subcommands included — uses the selected package, so an
advanced caller can substitute another compatible derivation:

```nix
devShells.default = nix-nrf-dev.lib.${system}.mkNrfShell {
  ncsVersion = "v3.3.0";
  nrfutilPackage = myNrfutil; # must provide `nrfutil` with sdk-manager
};
```

Without `nrfutilPackage`, replacing the Nixpkgs revision via
`inputs.nixpkgs.follows` is the supported way to change nrfutil/sdk-manager
versions.

## Hybrid consumers

`mkNrfShell` accepts `inputsFrom` for composing additional derivations
alongside the NCS toolchain:

```nix
devShells.default = nix-nrf-dev.lib.${system}.mkNrfShell {
  ncsVersion = "v3.3.0";
  inputsFrom = [ myPackage ];
};
```

This propagates the given derivations' environment variables and packages into
the shell without polluting the scoped `west` wrapper.

## Outputs

| Output | What |
|--------|------|
| `lib.<system>.mkNrfShell { backend, ncsVersion, toolchainBundleId, autoBootstrap, nrfutilPackage, packages, extraShellHook, withMultilib, inputsFrom, name }` | devShell factory — `ncsVersion` required; `backend` default `"nrfutil"` (recommended), `"west"` experimental (v3.3.0 / x86_64-linux only); `toolchainBundleId`/`autoBootstrap`/`nrfutilPackage` optional (nrfutil backend; rejected for west, see [Backends](#backends), [Bootstrap](#bootstrap), and [Advanced: overriding nrfutil](#advanced-overriding-nrfutil)) |
| `packages.openocd-master` | openocd from master (pinned), wrapped for libudev |
| `packages.openocd-master-unwrapped` | the raw build |
| `packages.nrfutil` | Nixpkgs nrfutil composed with the sdk-manager extension (includes SEGGER J-Link, see [SEGGER / J-Link](#segger--j-link)) |
| `packages.nix-nrf` | project CLI facade: `versions` (sdk-manager-backed NCS version list), `probes` (internal probe command module), `bootstrap` (internal SDK/toolchain bootstrap module), and `doctor` (internal read-only SDK/probe-access diagnostics module, see [Hardware access diagnostics](#hardware-access-diagnostics-nix-nrf-doctor) and [Bootstrap](#bootstrap)) |
| `packages.udev-rules` | upstream OpenOCD `60-openocd.rules` relocated to `lib/udev/rules.d`, byte-for-byte (see [NixOS udev rules](#nixos-udev-rules)) |
| `packages.default` | alias for `packages.nix-nrf` |
| `packages.west-zephyr-sdk-v3_3_0` | west backend exact Zephyr SDK 0.17.0 package (minimal bundle + ARM/RISC-V compilers, official layout, setup hook; see [Experimental: west backend](#experimental-west-backend-public-v330--x86_64-linux-only)) |
| `devShells.default` | dogfood shell for hacking on this repo |
| `formatter.<system>` | treefmt wrapper (`nix fmt`) |
| `nixosModules.default` | minimal NixOS module adding `packages.udev-rules` to `services.udev.packages` (no options; see [NixOS udev rules](#nixos-udev-rules)) |
| `checks.<system>` | `formatting` (treefmt) + `backend-selector` (eval gate: `ncsVersion` required, omitted equals nrfutil, `nrfutil`/`west`+v3.3.0 evaluate, `sdk-nrf`/west-unknown-release/west-toolchainBundleId/west-nrfutilPackage rejected, `toolchainBundleId` evaluates, `autoBootstrap` omitted/true/false evaluates for both backends, exact bundle in either bootstrap mode) + `bootstrap-tests` (fake-boundary unit tests, no network/real SDK) + `bootstrap-quoting` (wrapper shell-quoting regression for selector values with spaces/quotes) + `doctor-tests` (fake sysfs/dev-root doctor unit tests, no hardware) + `doctor-udev-wiring` (shell doctor reports the exact packaged udev-rule path) + `nix-nrf-help` (byte-for-byte standalone `nix-nrf --help` wording) + `udev-rules` (installed rule byte-identical to the pinned OpenOCD contrib rule) + `west-bootstrap-tests` (fake-boundary west bootstrap tests, no network/workspace; also runs the shared fake-west-workspace fixture safety suite) + `west-versions-tests` (fake-boundary west `versions` command tests) + `west-backend-metadata` (versions.nix schema) + `west-backend-quoting` (metadata quote-embedding regression for the public west shell hook/wrapper) + `west-shell-boundary` (public west shell boundary gate against a fake-ready workspace) + `pre-commit` (git-hooks.nix) |
| `templates.default` | project skeleton (flake.nix + .envrc) |
| `tcl/` | canonical flash recipes (see below) |

## Probing devices

`nix-nrf probes` is the preferred way to identify CMSIS-DAP probes and their
attached targets (read-only). Never assume the probe↔board mapping — probes
get replugged.

```
$ nix-nrf probes
SERIAL            PROBE                              TARGET    DPIDR       PART        VARIANT
8EE9B3FF          Seeed Studio XIAO nrf54 CMSIS-DAP  nRF54L15  0x6ba02477  0x00054b15  AAC0
E6635C08CB1F502B  Debugprobe on Pico (CMSIS-DAP)     nRF5340   0x6ba02477  0x00005340  QKAA

$ nix-nrf probes --find nrf53      # serial of the probe wired to an nRF53
E6635C08CB1F502B
```

Works on APPROTECT-locked chips via the DP/AP signature. Flash scripts should
select probes with `--find <family>` instead of hardcoding serials.

## Flash recipes (`tcl/`)

- **`nrf53_flash.tcl`** — nRF5340 dual-core flash with APPROTECT
  check/recovery and mandatory UICR.APPROTECT programming. Integrates with
  the west openocd runner (`check_approtect` / `flash_west`) or standalone
  (`flash_both`).
- **`nrf54l_flash.tcl`** — nRF54L RRAM flash (no flash driver; RRAMC
  write-enable + `load_image`/`verify_image`).

## Recovery coverage

| Chip | Recovery | Notes |
|------|----------|-------|
| nRF5340 | openocd `nrf53_recover` | proven; nRF53-specific CTRL-AP proc |
| nRF54L | **NONE** | upstream openocd has no nrf54l recovery. Fallback: `nrfutil device recover` with a J-Link. |

## Policy

openocd-master is the only flash backend. probe-rs was evaluated and rejected:
on the nRF5340 its attach model collides with soft-APPROTECT and its only
unlock remedy is a destructive mass erase that recreates the lock.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md). The repo uses Conventional Commits,
`nix fmt` (alejandra + black), and pre-commit hooks via git-hooks.nix. CI
builds all packages (cached via [Cachix](https://app.cachix.org) under
`qarnet`), runs smoke tests, flake checks, and TCL-parse tests on every PR.
Hardware integration tests run on a self-hosted runner — see
`tests/hardware/README.md`.

## Repository architecture

Maintainer reference: [docs/development/architecture.md](docs/development/architecture.md).

- `nix/flake/` — per-system construction (configured Nixpkgs, components,
  dev shells, checks).
- `nix/backends/` — public `mkNrfShell` dispatcher plus the `nrfutil` and
  `west` backend modules.
- `nix/commands/` — shared `nix-nrf` dispatcher, doctor, and probes command
  modules.
- `nix/hardware/` — OpenOCD build and udev-rules package.
- `nix/lib/mk-python-command.nix` — shared command packaging helper.
- `bin/` — command scripts, owned by their backend (`bin/backends/`) or
  shared (`bin/commands/`); installed only under `$out/libexec/nix-nrf/`.
- `tests/` — unit suites, fixtures, and the manual clean-room / west /
  hardware harnesses.

## License

MIT. See [LICENSE](LICENSE).
