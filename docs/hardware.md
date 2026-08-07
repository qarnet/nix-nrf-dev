# Hardware access

## Verified hardware

This repository verifies its flashing flows on real hardware with CMSIS-DAP
probes and its pinned openocd-master build:

- **nRF5340** — dual-core (app + net) flash recipe.
- **nRF54L15** — RRAM flash recipe, including FLPR bundles.

Other nRF families are not claimed: the recipes and recovery guidance below
apply only to these two devices/families.

## Host permissions

A Nix dev shell cannot activate host udev policy — probe access is a system
configuration, not an environment variable. Two paths:

### NixOS

Import the module in your `nixosSystem` configuration:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-nrf-dev.url = "github:qarnet/nix-nrf-dev";
  };

  outputs = { nixpkgs, nix-nrf-dev, ... }: {
    nixosConfigurations.myHost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        { imports = [ nix-nrf-dev.nixosModules.default ]; }
      ];
    };
  };
}
```

The module activates the packaged OpenOCD udev rules so CMSIS-DAP and J-Link
probe nodes are user-accessible.

### Other Linux

```bash
nix build github:qarnet/nix-nrf-dev#udev-rules
```

Install `result/lib/udev/rules.d/60-openocd.rules` using your distribution's
documented udev procedure, then reload the rules and replug the probe.
OpenOCD should never run as root.

## Diagnosing probe access

- `nix-nrf probes` — lists attached CMSIS-DAP probes and their targets
  (read-only).
- `nix-nrf probes --find nrf53` — prints the serial of the probe wired to an
  nRF5340.
- `nix-nrf probes --find nrf54l` — prints the serial of the probe wired to an
  nRF54L15.
- `nix-nrf doctor` — read-only environment and probe-access diagnostics; it
  reports ready/missing SDK state, visible probes, and access, and prints the
  exact remediation. It never runs mutating actions, `sudo`, or udev
  reloads.

## Flash recipes

The repository includes two canonical flash recipes:

- [`../tcl/nrf53_flash.tcl`](../tcl/nrf53_flash.tcl) — nRF5340 dual-core
  flash (app + net cores) with APPROTECT handling and mandatory UICR.APPROTECT
  programming.
- [`../tcl/nrf54l_flash.tcl`](../tcl/nrf54l_flash.tcl) — nRF54L RRAM flash
  (RRAMC write-enable plus load/verify; no OpenOCD flash driver needed).

## Recovery safety

> [!WARNING]
> **nRF53 recovery mass-erases.** `flash_both APP_HEX NET_HEX` recovers only
> when the app core is locked by APPROTECT and `allow_recovery` permits: the
> two-argument form allows recovery by default, while a third argument `0`
> refuses it and aborts with an error. The west integration path
> (`check_approtect`) is recovery-enabled when the core is locked. Both paths
> mass-erase via `nrf53_recover` and then program UICR.APPROTECT to its
> unprotected value so the chip stays debuggable across resets.
>
> **nRF54L has no known-good OpenOCD recovery.** If APPROTECT engages on an
> nRF54L15, fall back to Nordic's `nrfutil device recover` with a J-Link —
> upstream OpenOCD has no proven recovery path for this family.

## See also

- [README](../README.md) — quick start and template usage
- [backends.md](backends.md) — toolchain backends, selection, bootstrap
