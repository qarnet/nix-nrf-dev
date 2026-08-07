# nix-nrf-dev

Nordic nRF Connect SDK (NCS) toolchain environments are awkward to compose
safely with Nix: sdk-manager-managed SDKs and toolchains live outside the Nix
store, their environment scripts can interfere with unrelated tools, and
CMSIS-DAP probes need extra setup for reliable flashing and probe access on
nRF5340 and nRF54L15. This project packages all of that into one ready-to-use,
project-scoped Nix environment for building and flashing modern Nordic
firmware, tested on NCS v3.3.0 with `x86_64-linux`.

## What you get

- **NCS shell** — project-scoped `nix develop` environment with `west`, the
  Zephyr toolchain, and `ZEPHYR_BASE`, without contaminating your host tools.
- **CMSIS-DAP / OpenOCD support** — a pinned openocd-master build plus the
  host udev policy needed for reliable probe access.
- **`nix-nrf` helper** — `bootstrap`, `versions`, `probes`, and `doctor`
  commands for provisioning and diagnosing the environment.
- **nRF5340 and nRF54L15 verification** — flashing flows proven on real
  hardware for both families.

## Quick start

Prerequisites: Nix with flake support on `x86_64-linux`. [direnv] is
recommended but optional.

```bash
mkdir my-project && cd my-project
nix flake init -t github:qarnet/nix-nrf-dev
direnv allow        # or: nix develop
```

The generated `.envrc` contains `use flake`, which enters the flake's
`devShells.default` when you `cd` into the project. direnv itself is
documented in the [direnv project wiki](https://github.com/direnv/direnv/wiki);
without direnv, run `nix develop` in the project directory instead.

On first entry, provision the NCS SDK and toolchain:

```bash
nix-nrf bootstrap
```

It asks for confirmation before downloading several GiB — nothing is
downloaded without explicit approval.

[direnv]: https://direnv.net

## Choose a backend

`mkNrfShell` selects how the NCS toolchain is provided. The **nrfutil**
backend — the default and recommended choice — uses Nordic's sdk-manager to
manage a mutable SDK and toolchain under your home directory, and accepts
releases advertised by sdk-manager through `ncsVersion` (tested baseline
v3.3.0).

The **west** backend (experimental) instead lets Nix own the exact Zephyr SDK,
host tools, and Python interpreter while a mutable west workspace holds the
NCS source; it currently supports only NCS v3.3.0 on `x86_64-linux`. A pure
Nix-native `sdk-nrf` backend is not implemented and has no configuration.
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

A Nix dev shell cannot install host udev policy — probe access is a system
configuration, not part of the shell. NixOS users can activate the packaged
rules with the `nixosModules.default` module; other Linux distributions
install the packaged `60-openocd.rules` with their standard udev procedure.
`nix-nrf doctor` reports whether your probes are visible and accessible.
Full instructions are in [docs/hardware.md](docs/hardware.md).

## Documentation

- [docs/backends.md](docs/backends.md) — backend choice, toolchain selection, bootstrap
- [docs/hardware.md](docs/hardware.md) — probe access, flashing, recovery safety
- [CONTRIBUTING.md](CONTRIBUTING.md) — contributing to nix-nrf-dev itself

## License

MIT. See [LICENSE](LICENSE).
