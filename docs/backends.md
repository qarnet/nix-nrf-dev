# Backends

`mkNrfShell` takes a `backend` argument that selects how the NCS toolchain
environment is provided, and a `ncsVersion` that is **required** in every
configuration: each project pins an explicit NCS release — there is no
`"latest"` alias or default. NCS **v3.3.0** is the tested baseline used by
this repository's own shells and template.

| Backend | Status | Toolchain provision | Supported releases |
|---------|--------|---------------------|--------------------|
| `nrfutil` | default, recommended | Nordic sdk-manager manages a mutable SDK/toolchain under your home directory | releases advertised by sdk-manager through `ncsVersion` |
| `west` | experimental | Nix owns the Zephyr SDK, host tools, and Python; a mutable west workspace + venv own the NCS source | v3.3.0 on x86_64-linux only |
| `sdk-nrf` | not implemented | — | none; fails at Nix evaluation |

An unknown `backend` value fails at Nix evaluation listing the supported
backends — there is no silent fallback.

## nrfutil backend (default)

Omit `backend` or pass `backend = "nrfutil"`; both behave identically. The
backend uses Nordic's sdk-manager to install and manage the NCS SDK source and
toolchain bundle under your home directory (for example
`$HOME/ncs/v3.3.0`).

Toolchain selection:

- Omit `toolchainBundleId` (the normal case) — the west wrapper runs
  `nrfutil sdk-manager toolchain env --ncs-version <ncsVersion>`, selecting
  the newest compatible patched toolchain for the release.
- Set `toolchainBundleId = "<bundle-id>"` — the wrapper runs
  `nrfutil sdk-manager toolchain env --toolchain-bundle-id <bundle-id>`,
  selecting that exact bundle. If it fails, the error names the exact bundle
  rather than falling back to the newest compatible one.

Bootstrap:

- `nix-nrf bootstrap` — explicit provisioning; prompts before downloading.
- `nix-nrf bootstrap --yes` — approves the required downloads up front.
- `nix-nrf bootstrap --check` — read-only readiness check; exits 1 when
  something is missing and never installs.
- `nix-nrf bootstrap --print-sdk-path` — prints the absolute SDK root on
  success.

`autoBootstrap` (default `true`) makes the west wrapper check on every
invocation and install only when something is missing and approved. With
`autoBootstrap = false` the wrapper only checks and prints the exact
`nix-nrf bootstrap` remediation when something is missing — it never mutates.

Shell entry is always non-mutating: the shell hook runs the read-only
`--check` path and exports `ZEPHYR_BASE` only when the installed SDK is found.
Without a terminal, an unapproved bootstrap fails with the exact re-run
command and exit 2 instead of mutating state.

## west backend (experimental)

`backend = "west"` is the hybrid model: Nix supplies the exact Zephyr SDK,
host tools, and Python interpreter, while the official mutable west workspace
and a version-local venv own the NCS source, west, and workspace Python
requirements — no nrfutil, no sdk-manager, and no Nordic toolchain bundle.

Constraints:

- Only NCS v3.3.0 on `x86_64-linux` is supported. An unknown release fails
  evaluation naming the supported west releases.
- `toolchainBundleId` and non-default `nrfutilPackage` overrides are rejected
  (no nrfutil participates in this backend).

Bootstrap is explicit: `nix-nrf bootstrap` creates or updates the west
workspace and venv (`--yes` approves up front, `--check` is a read-only
readiness check). `nix-nrf versions` lists the west backend's supported
releases and never invokes nrfutil.

## Scoped toolchain environment

Nordic's sdk-manager environment script exports `PYTHONHOME`, `PYTHONPATH`,
`LD_LIBRARY_PATH`, and `GIT_EXEC_PATH` — variables that break any
non-toolchain tool run from the same shell (including Nix itself). The shell
does **not** eval that script globally; the `west` wrapper loads it only
inside west's process tree. The shell stays clean, so `nix`, agents, and
editors launched from it work normally.

## Should I use `inputs.nixpkgs.follows`?

Not required — nix-nrf-dev works out of the box with the nixpkgs revision it
pins in its own `flake.lock`.

If your project already pins its own nixpkgs, adding `inputs.nixpkgs.follows`
makes nix-nrf-dev reuse that revision, reducing duplicate nixpkgs inputs and
replacing the packaged nrfutil/sdk-manager versions:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-nrf-dev = {
      url = "github:qarnet/nix-nrf-dev";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

Omit `follows` to keep nix-nrf-dev's tested/pinned nixpkgs revision. See the
official [Nix flake documentation](https://nix.dev/concepts/flakes.html) for
how `follows` propagates input revisions.

## SEGGER / J-Link caveat

The packaged nrfutil derivation in Nixpkgs unconditionally depends on
`segger-jlink-headless` and sets `NRF_JLINK_DLL_PATH` — including when only
the sdk-manager extension is composed. The default flake therefore imports
Nixpkgs with `allowUnfree = true` and `segger-jlink.acceptLicense = true`,
so most users need no action — even when they only use a CMSIS-DAP probe.
CMSIS-DAP use does **not** remove the packaged J-Link dependency.

Consumers who construct or override nrfutil from their own `pkgs` — a
`nrfutilPackage` override, or their own `pkgs.nrfutil.withExtensions
["nrfutil-sdk-manager"]` — must configure the same license handling
themselves, or that package will fail to build. There is no sdk-manager-only
composition that avoids J-Link.

## See also

- [hardware.md](hardware.md) — probe access, flashing, recovery safety
- [README](../README.md) — quick start and template usage
