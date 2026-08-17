# nix-nrf-dev

[![Release](https://img.shields.io/github/v/release/qarnet/nix-nrf-dev?sort=semver)](https://github.com/qarnet/nix-nrf-dev/releases)

nRF Connect SDK (NCS) toolchain environments are awkward to compose
safely with Nix:

- SDKs and toolchains live outside the Nix store
- their environment scripts can interfere with unrelated tools
- CMSIS-DAP probes need extra setup for reliable flashing and probe access on nRF5340 and nRF54L15

This project packages all of that into one ready-to-use,
project-scoped Nix environment for building and flashing modern Nordic
firmware.

> The nix-nrf-dev project version is **independent from NCS versions**.
> `nix-nrf --version` reports the nix-nrf-dev project version (canonical
> `release.json`, e.g. `0.1.0`), while `ncsVersion` (e.g. `v3.3.0`) is the
> upstream SDK selection. See [CHANGELOG.md](CHANGELOG.md).

## What you get

- **NCS shell**: project-scoped `nix develop` environment with `west`, the
  Zephyr toolchain, and `ZEPHYR_BASE` pointing to the correct SDK, without contaminating your host tools.
- **CMSIS-DAP / OpenOCD support**: a pinned openocd-master build plus the
  host udev policy needed for reliable probe access.
- **`nix-nrf` helper**: `bootstrap`, `versions`, `probes`, and `doctor`
  commands for provisioning and diagnosing the environment.
- **Project initializer**: `nix run ...#init-project -- ./my-project` generates
  a consumer flake pinned to a concrete NCS release (never `latest`).
- **nRF5340 and nRF54L15 verification**: flashing flows proven on real
  hardware for both families.

## Quick start

Prerequisites: Nix with flake support on `x86_64-linux`. [direnv] is
recommended but optional.

### Method A — Automated (recommended)

```bash
mkdir my-project && cd my-project
nix run github:qarnet/nix-nrf-dev#init-project -- .
direnv allow        # or: nix develop
nix-nrf bootstrap   # installs NCS SDK + toolchain (several GiB; prompts first)
nix-nrf doctor      # verify environment and probe access
```

The initializer writes exactly `.envrc` and `flake.nix`, pinned to a
concrete NCS release (never `latest`), and never overwrites existing files.
First use builds openocd-master from source (~10 min) unless Cachix is
enabled (`cachix use qarnet`).

### Method B — Manual (existing project)

Add nix-nrf-dev to your project's `flake.nix`:

```nix
{
  inputs.nix-nrf-dev.url = "github:qarnet/nix-nrf-dev";

  outputs = { nix-nrf-dev, ... }: {
    devShells.x86_64-linux.default =
      nix-nrf-dev.lib.x86_64-linux.mkNrfShell {
        backend = "nrfutil";   # default; "west" is experimental
        ncsVersion = "v3.3.0"; # required — exact release, never "latest"
      };
  };
}
```

```bash
nix develop         # or: direnv allow
nix-nrf bootstrap
nix-nrf doctor
```

For the full step-by-step guide — prerequisites, what gets installed and
where, release-tag pinning, backend choice — see
[docs/install.md](docs/install.md).

[direnv]: https://direnv.net

## Everyday commands

```bash
nix-nrf bootstrap    # provision the NCS SDK/toolchain (prompts before multi-GiB downloads)
nix-nrf versions     # list available NCS versions
nix-nrf probes       # list attached debug probes and targets
nix-nrf doctor       # read-only environment and probe-access diagnostics
nix-nrf --version    # print the nix-nrf-dev project version (independent from NCS)
```

Backend-specific behavior and hardware setup live in
[docs/backends.md](docs/backends.md) and [docs/hardware.md](docs/hardware.md).

> [!NOTE]
> **SEGGER / J-Link caveat:** the packaged nrfutil includes J-Link and its
> unfree license even when you only use a CMSIS-DAP probe. The default flake
> handles this automatically, but custom nrfutil or Nixpkgs compositions may
> need license configuration — see
> [docs/backends.md#segger--j-link-caveat](docs/backends.md#segger--j-link-caveat).

## Hardware access

A Nix dev shell cannot install host udev policy, because probe access is 
a system configuration. The packaged `60-openocd.rules` is the
unmodified upstream OpenOCD contrib rule and needs an explicit `plugdev`
group with your user as a member. On NixOS, activate it with the direct
`services.udev.packages` form (primary, least intrusive) or import the
`nixosModules.udevRules` module as a convenience equivalent. Both only add
the rule, never the group or user. Other Linux distributions install the
packaged rule with their standard udev procedure. `nix-nrf doctor` reports
whether your probes are visible and accessible. Full instructions are in
[docs/hardware.md](docs/hardware.md).

## Documentation

- [docs/install.md](docs/install.md) — step-by-step install guide (prereqs, what gets installed, pinning, backends)
- [CHANGELOG.md](CHANGELOG.md) — release history (project SemVer, independent from NCS versions)
- [docs/backends.md](docs/backends.md) — backend choice, toolchain selection, bootstrap
- [docs/hardware.md](docs/hardware.md) — probe access, flashing, recovery safety
- [CONTRIBUTING.md](CONTRIBUTING.md) — contributing to nix-nrf-dev itself

## License

MIT. See [LICENSE](LICENSE).
