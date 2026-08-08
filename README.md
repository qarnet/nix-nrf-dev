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

```bash
mkdir my-project && cd my-project
nix run github:qarnet/nix-nrf-dev#init-project -- .
direnv allow        # or: nix develop
```

The initializer writes exactly `.envrc` (containing `use flake`) and
`flake.nix` into the destination (`.` above, or any path), calling
`mkNrfShell` with the backend and NCS release you choose. By default it
resolves `latest`: for the `nrfutil` backend that asks the packaged
sdk-manager for the newest stable remotely installable release, and for the
`west` backend it selects the newest release supported by the repository's
west metadata — either way the generated flake contains one concrete pinned
NCS release, never `latest`. For a fully offline, reproducible generation
pass an exact release:

```bash
nix run github:qarnet/nix-nrf-dev#init-project -- ./my-project \
  --backend nrfutil --ncs-version v3.3.0 --non-interactive
```

The initializer never overwrites: an existing `flake.nix` or `.envrc`
collision, a symlink escape attempt, or an invalid backend/version aborts
with `init-project: ...` on stderr and leaves no generated output. See
[docs/backends.md](docs/backends.md) for backend selection and
`nix run ...#init-project -- --help` for the full CLI.

For reproducible consumer builds pin the project to an immutable release tag:

```bash
nix run github:qarnet/nix-nrf-dev/v0.1.0#init-project -- ./my-project
```

```nix
# flake.nix
inputs.nix-nrf-dev.url = "github:qarnet/nix-nrf-dev/v0.1.0";
```

Release tags (`v<version>`, e.g. `v0.1.0`) are created automatically from a
trusted push to `main` after all CI checks pass; see
[CONTRIBUTING.md](CONTRIBUTING.md#release-process) for the release process.

direnv itself is documented in the
[direnv project wiki](https://github.com/direnv/direnv/wiki); without direnv,
run `nix develop` in the project directory instead.

On first entry, provision the NCS SDK and toolchain:

```bash
nix-nrf bootstrap
```

It asks for confirmation before downloading several GiB.

[direnv]: https://direnv.net

## Choose a backend

`mkNrfShell` selects how the NCS toolchain is provided. The **nrfutil**
backend (the default and recommended choice) uses Nordic's sdk-manager to
manage a mutable SDK and toolchain under your home directory, and accepts
releases advertised by sdk-manager through `ncsVersion`.

The **west** backend (experimental) instead lets Nix own the exact Zephyr SDK,
host tools, and Python interpreter while a mutable west workspace holds the
NCS source.

A pure Nix-native `sdk-nrf` backend is not implemented and has no configuration.
Full backend behavior and bootstrap details are in
[docs/backends.md](docs/backends.md).

<details>
<summary>nrfutil (recommended)</summary>

```nix
# flake.nix
{
  inputs.nix-nrf-dev.url = "github:qarnet/nix-nrf-dev";

  outputs = { nix-nrf-dev, ... }: {
    devShells.x86_64-linux.default =
      nix-nrf-dev.lib.x86_64-linux.mkNrfShell {
        backend = "nrfutil";
        ncsVersion = "v3.3.0";
      };
  };
}
```

</details>

<details>
<summary>nrfutil with an exact toolchain bundle</summary>

```nix
# flake.nix
{
  inputs.nix-nrf-dev.url = "github:qarnet/nix-nrf-dev";

  outputs = { nix-nrf-dev, ... }: {
    devShells.x86_64-linux.default =
      nix-nrf-dev.lib.x86_64-linux.mkNrfShell {
        backend = "nrfutil";
        ncsVersion = "v3.3.0";
        toolchainBundleId = "<bundle-id>";
      };
  };
}
```

</details>

<details>
<summary>west (experimental)</summary>

```nix
# flake.nix
{
  inputs.nix-nrf-dev.url = "github:qarnet/nix-nrf-dev";

  outputs = { nix-nrf-dev, ... }: {
    devShells.x86_64-linux.default =
      nix-nrf-dev.lib.x86_64-linux.mkNrfShell {
        backend = "west";
        ncsVersion = "v3.3.0";
      };
  };
}
```

</details>

## Everyday commands

```bash
nix-nrf bootstrap    # provision the NCS SDK/toolchain (prompts before multi-GiB downloads)
nix-nrf versions     # list available NCS versions
nix-nrf probes       # list attached debug probes and targets
nix-nrf doctor       # read-only environment and probe-access diagnostics
nix-nrf --version    # print the nix-nrf-dev project version (independent from NCS)
```

Start a new project with `nix run ...#init-project -- ./my-project`; see
[docs/backends.md](docs/backends.md) for backend choice and how `latest`
resolution works.

Backend-specific behavior and hardware setup live in
[docs/backends.md](docs/backends.md) and [docs/hardware.md](docs/hardware.md).

> [!NOTE]
> **SEGGER / J-Link caveat:** the packaged nrfutil includes J-Link and its
> unfree license even when you only use a CMSIS-DAP probe. The default flake
> handles this automatically, but custom nrfutil or Nixpkgs compositions may
> need license configuration — see
> [docs/backends.md#segger--j-link-caveat](docs/backends.md#segger--j-link-caveat).

## Hardware access

A Nix dev shell cannot install host udev policy — probe access is a system
configuration, not part of the shell. The packaged `60-openocd.rules` is the
unmodified upstream OpenOCD contrib rule and needs an explicit `plugdev`
group with your user as a member. On NixOS, activate it with the direct
`services.udev.packages` form (primary, least intrusive) or import the
`nixosModules.udevRules` module as a convenience equivalent — both only add
the rule, never the group or user. Other Linux distributions install the
packaged rule with their standard udev procedure. `nix-nrf doctor` reports
whether your probes are visible and accessible. Full instructions are in
[docs/hardware.md](docs/hardware.md).

## Documentation

- [CHANGELOG.md](CHANGELOG.md) — release history (project SemVer, independent from NCS versions)
- [docs/backends.md](docs/backends.md) — backend choice, toolchain selection, bootstrap
- [docs/hardware.md](docs/hardware.md) — probe access, flashing, recovery safety
- [CONTRIBUTING.md](CONTRIBUTING.md) — contributing to nix-nrf-dev itself

## License

MIT. See [LICENSE](LICENSE).
