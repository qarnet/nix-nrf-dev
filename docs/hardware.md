# Hardware access

## Verified hardware

This repository verifies its flashing flows on real hardware with CMSIS-DAP
probes and its pinned openocd-master build:

- **nRF5340** — dual-core (app + net) flash recipe.
- **nRF54L15** — RRAM flash recipe, including FLPR bundles.

Other nRF families are not claimed: the recipes and recovery guidance below
apply only to these two devices/families.

The hardware workflow (`tests/hardware/run.sh`) additionally asserts the
doctor contract before any build or flash: the exact XIAO serial must be
usable through the explicit CMSIS-DAP v2 bulk USB transport
(`tests/hardware/preflight_xiao.py` over `nix-nrf doctor --json`).

## Host permissions

A Nix dev shell cannot activate host udev policy — probe access is a system
configuration, not an environment variable. Two paths:

### NixOS

Adding the flake input alone changes nothing. The packaged rule is the
unmodified upstream OpenOCD `contrib/60-openocd.rules`, which assigns
`MODE="660", GROUP="plugdev", TAG+="uaccess"` to its matched nodes, and
NixOS does not create a `plugdev` group for you. The primary,
least-intrusive path is the direct `services.udev.packages` form with an
explicit `plugdev` group and user membership:

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
        ({ pkgs, ... }: {
          users.groups.plugdev = {};
          users.users.myuser.extraGroups = [ "plugdev" ];
          services.udev.packages = [
            nix-nrf-dev.packages.${pkgs.stdenv.hostPlatform.system}.udev-rules
          ];
        })
      ];
    };
  };
}
```

The named `nixosModules.udevRules` module is a convenience equivalent: it
sets only the same `services.udev.packages` and never creates the group or
modifies users, so the explicit `plugdev` setup is still required:

```nix
{
  users.groups.plugdev = {};
  users.users.myuser.extraGroups = [ "plugdev" ];
  imports = [ nix-nrf-dev.nixosModules.udevRules ];
}
```

The rule activates the packaged OpenOCD udev rules so CMSIS-DAP and J-Link
probe nodes are user-accessible. Then rebuild, log out/in (or reboot) so
the new group membership applies, replug the probe, and confirm with
`nix-nrf doctor`.

#### Upstream provenance

`packages.<system>.udev-rules` contains exactly one file:
`lib/udev/rules.d/60-openocd.rules`, copied byte-for-byte from the pinned
OpenOCD build's `contrib/60-openocd.rules`. The upstream source URL, exact
revision, and hash live in `nix/hardware/openocd.nix`; this repository
maintains no VID/PID catalog and does not edit the rule. The upstream file's
generic `*CMSIS-DAP*` match covers CMSIS-DAP probes (including the Seeed
XIAO and Raspberry Pi Debug Probe) on the usb, tty, and hidraw subsystems,
and the file also carries SEGGER J-Link entries; every relevant line uses
`MODE="660", GROUP="plugdev", TAG+="uaccess"`.

### Other Linux

Ensure the `plugdev` group exists and that your user is a member, using
your distribution's documented procedure:

```bash
nix build github:qarnet/nix-nrf-dev#udev-rules
```

Install `result/lib/udev/rules.d/60-openocd.rules` using your distribution's
documented udev procedure. If you changed group membership, log out/in or
reboot, reload the rules, and replug the probe. Confirm with
`nix-nrf doctor`. OpenOCD should never run as root.

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
- `tests/hardware/run.sh` — before any probe fingerprint, NCS build, or
  flash, the hardware workflow asserts the doctor v2 USB preflight: the
  exact XIAO serial usable through explicit CMSIS-DAP v2 bulk USB, run
  inside the dev shell (`NIX_NRF_DOCTOR_SKIP_SDK=1 nix-nrf doctor --json |
  python3 tests/hardware/preflight_xiao.py 8EE9B3FF`).

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
