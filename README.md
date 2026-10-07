# nix-nrf-dev

[![Release](https://img.shields.io/github/v/release/qarnet/nix-nrf-dev?sort=semver)](https://github.com/qarnet/nix-nrf-dev/releases)

Default Nordic-managed SDKs and toolchains live outside the Nix store. The
experimental west backend provides its compiler SDK through Nix while keeping
sources in a mutable workspace. Nordic environment scripts can affect host tools.
CMSIS-DAP probes need host udev rules before they can
flash nRF5340 and nRF54L15 boards.

nix-nrf-dev provides a project-scoped Nix shell for NCS builds and OpenOCD
flashing.

> The nix-nrf-dev project version is **independent from NCS versions**.
> `nix-nrf --version` reports the nix-nrf-dev project version from
> `release.json`, e.g. `0.1.0`, while `ncsVersion` (e.g. `v3.4.1`) is the
> upstream SDK selection. See [CHANGELOG.md](CHANGELOG.md).

## What it provides

- `nix develop` provides `west` and the selected NCS build environment, with
  toolchain setup scoped to build processes. Source selection is independent.
- `openocd-master` and udev guidance support CMSIS-DAP probe access.
- `nix-nrf` provides `bootstrap`, `versions`, `probes`, and `doctor`.
- `nix-nrf session` owns shared nRF54L15 OpenOCD observation/debug sessions.
- `init-project` writes `.envrc` and `flake.nix` pinned to one NCS release.
- Manual hardware tests cover nRF5340 and nRF54L15 flashing.

## Quick start

Requires Nix with flake support on `x86_64-linux` or `aarch64-linux`. [direnv] is optional.
Repository shells and the initializer select `nrfutil` on amd64 and experimental
`west` on ARM64. Active baseline is NCS `v3.4.1` on both hosts; Nordic-managed
toolchain installation is unavailable on ARM64. No backend falls back silently.

### Create a project

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

### Add nix-nrf-dev to an existing project

Add nix-nrf-dev to your project's `flake.nix`:

```nix
{
  inputs.nix-nrf-dev.url = "github:qarnet/nix-nrf-dev";

  outputs = { nix-nrf-dev, ... }: {
    devShells.x86_64-linux.default =
      nix-nrf-dev.lib.x86_64-linux.mkNrfShell {
        backend = "nrfutil";   # default; "west" is experimental
        ncsVersion = "v3.4.1"; # required, exact release, never "latest"
      };
  };
}
```

```bash
nix develop         # or: direnv allow
nix-nrf bootstrap
nix-nrf doctor
```

See [docs/install.md](docs/install.md) for prerequisites, install locations,
release pins, and backend selection.

For a portable amd64/ARM64 project, generate with `--backend west --ncs-version
v3.4.1`. Hand-written ARM64 shells must explicitly set `backend = "west"` and
use `lib.aarch64-linux.mkNrfShell`: the public factory retains its `nrfutil`
default and rejects it on ARM64.

Already have a project-owned west workspace? Select it with
`source = { mode = "workspace"; workspace = "."; };` and keep either toolchain
backend. See [application layouts and source selection](docs/application-types.md)
for examples, Python preparation, and ownership boundaries.

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

`west` core commands work before SDK setup. General help and `nix-nrf doctor`
distinguish **core available**, **extensions discovered**, and **command ready**;
discovering a command does not prove its Python/tools are ready. See
[three west command states](docs/backends.md#three-west-command-states).

> [!NOTE]
> Packaged nrfutil includes J-Link and its unfree license even when using a
> CMSIS-DAP probe. Default flake configuration accepts it. Custom nrfutil or
> Nixpkgs compositions may need the same license configuration. See
> [docs/backends.md#segger--j-link-caveat](docs/backends.md#segger--j-link-caveat).

## Hardware access

A Nix dev shell cannot set host udev policy. The packaged
`60-openocd.rules` is the unmodified OpenOCD contrib rule. It needs a
`plugdev` group with your user as a member. On NixOS, set
`services.udev.packages` directly or import `nixosModules.udevRules`. Both
add only the rule. Other Linux distributions install the packaged rule through
their normal udev procedure. `nix-nrf doctor` reports probe visibility and
access. See [docs/hardware.md](docs/hardware.md).

## Documentation

- [docs/install.md](docs/install.md) covers installation and release pins.
- [CHANGELOG.md](CHANGELOG.md) records project releases.
- [docs/backends.md](docs/backends.md) explains backends and bootstrap.
- [docs/support-matrix.md](docs/support-matrix.md) records qualified capabilities,
  known unavailable tools and precise SUIT/DFU/debug verification limits.
- [docs/application-types.md](docs/application-types.md) explains independent tool
  and source selection for repository, workspace, and freestanding applications.
- [docs/hardware.md](docs/hardware.md) covers probes, flashing, and recovery.
- [docs/debug.md](docs/debug.md) covers shared sessions and their hardware
  validation limits.
- [CONTRIBUTING.md](CONTRIBUTING.md) explains repository work.
- [docs/adr/README.md](docs/adr/README.md) records lasting architecture decisions.
- [docs/product/README.md](docs/product/README.md) defines the product backlog
  and its SDK-free contributor tooling.

## License

MIT. See [LICENSE](LICENSE).
