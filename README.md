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
versions`, `nix-nrf probes`, `nix-nrf bootstrap`), and multilib GCC for
`native_sim`.

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
  This is the only implemented backend. Omit the argument or pass
  `backend = "nrfutil"` explicitly; both behave identically.
- `"sdk-nrf"` — reserved for a future Nix-native build environment (see
  `goals.md`). It is **not** implemented: any value other than `"nrfutil"`
  fails at Nix evaluation with an unsupported-backend error instead of
  silently falling back.

`ncsVersion` is a **required** argument — every caller selects an NCS release
explicitly (there is no `"latest"` alias or default). `"v3.3.0"` is the tested
release used by this repository's own shells, examples, and template, but it
is not an architecture lock.

Toolchain selection:

- Omit `toolchainBundleId` (normal case) → the west wrapper runs
  `nrfutil sdk-manager toolchain env --ncs-version <ncsVersion>`, selecting
  the newest compatible patched toolchain for that release.
- Set `toolchainBundleId = "<bundle-id>"` → the wrapper runs
  `nrfutil sdk-manager toolchain env --toolchain-bundle-id <bundle-id>`,
  selecting that exact bundle. If it fails, the error names the exact bundle
  rather than falling back to the newest compatible one.

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

## nix-nrf CLI

`nix-nrf` is the project's command facade: `nix-nrf versions`, `nix-nrf probes`,
and `nix-nrf bootstrap`. It dispatches to the packaged tools with `exec`, so
delegated stdout, stderr, options, and exit status are preserved:

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
$ nix-nrf help versions
$ nix-nrf help probes
$ nix-nrf help bootstrap
```

`nix-nrf versions` delegates to `nrfutil sdk-manager search` without parsing
or maintaining a local version list, so sdk-manager remains the runtime
authority. `nix-nrf probes` runs the internal probe command module
(`$out/libexec/nix-nrf/probes`); `nix-nrf bootstrap` runs the internal
bootstrap command module (`$out/libexec/nix-nrf/bootstrap`); there are no
standalone `nrf-probes`/`nrf-bootstrap` binaries or packages. The old
`nrf-sdk-versions` command is removed; use `nix-nrf versions`.

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
| `lib.<system>.mkNrfShell { backend, ncsVersion, toolchainBundleId, autoBootstrap, nrfutilPackage, packages, extraShellHook, withMultilib, inputsFrom, name }` | devShell factory — `ncsVersion` required; `toolchainBundleId`/`autoBootstrap`/`nrfutilPackage` optional (see [Backends](#backends), [Bootstrap](#bootstrap), and [Advanced: overriding nrfutil](#advanced-overriding-nrfutil)) |
| `packages.openocd-master` | openocd from master (pinned), wrapped for libudev |
| `packages.openocd-master-unwrapped` | the raw build |
| `packages.nrfutil` | Nixpkgs nrfutil composed with the sdk-manager extension (includes SEGGER J-Link, see [SEGGER / J-Link](#segger--j-link)) |
| `packages.nix-nrf` | project CLI facade: `versions` (sdk-manager-backed NCS version list), `probes` (internal probe command module), and `bootstrap` (internal SDK/toolchain bootstrap module, see [nix-nrf CLI](#nix-nrf-cli) and [Bootstrap](#bootstrap)) |
| `packages.default` | alias for `packages.nix-nrf` |
| `devShells.default` | dogfood shell for hacking on this repo |
| `formatter.<system>` | treefmt wrapper (`nix fmt`) |
| `checks.<system>` | `formatting` (treefmt) + `backend-selector` (eval gate: `ncsVersion` required, omitted/`nrfutil` evaluate, `sdk-nrf` rejected, `toolchainBundleId` evaluates, `autoBootstrap` omitted/true/false evaluates, exact bundle in either bootstrap mode) + `bootstrap-tests` (fake-boundary unit tests, no network/real SDK) + `pre-commit` (git-hooks.nix) |
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

## License

MIT. See [LICENSE](LICENSE).
