# Hardware access

## Tested hardware

Manual tests use CMSIS-DAP probes and pinned `openocd-master` on these boards:

- nRF5340 dual-core app and net flash recipe.
- nRF54L15 RRAM flash recipe, including FLPR bundles.

Other nRF families are not claimed: the recipes and recovery guidance below
apply only to these two devices/families.

Before build or flash, `tests/hardware/run.sh` requires the XIAO serial to be
usable through the explicit CMSIS-DAP v2 bulk USB transport
(`tests/hardware/preflight_xiao.py` over `nix-nrf doctor --json`).

## Host permissions

A Nix dev shell cannot activate host udev policy. Probe access is a system
configuration, not an environment variable. Use one of these paths.

### NixOS

Adding the flake input alone changes nothing. The packaged rule is the
unmodified upstream OpenOCD `contrib/60-openocd.rules`, which assigns
`MODE="660", GROUP="plugdev", TAG+="uaccess"` to its matched nodes, and
NixOS does not create a `plugdev` group. Set `services.udev.packages` with an
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

`nixosModules.udevRules` sets the same `services.udev.packages` value. It does
not create the group or modify users, so keep the explicit `plugdev` setup:

```nix
{
  users.groups.plugdev = {};
  users.users.myuser.extraGroups = [ "plugdev" ];
  imports = [ nix-nrf-dev.nixosModules.udevRules ];
}
```

Rebuild, log out and back in or reboot, replug the probe, then run
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

## Diagnose probe access

- `nix-nrf probes` lists attached CMSIS-DAP probes and targets without writing.
- `nix-nrf probes --find nrf53` prints the serial of the probe wired to an
  nRF5340.
- `nix-nrf probes --find nrf54l` prints the serial of the probe wired to an
  nRF54L15.
- `nix-nrf doctor` reports SDK state, visible probes, and access. It does not
  run `sudo`, change state, or reload udev rules.
- `tests/hardware/run.sh` checks the doctor v2 USB preflight before probe
  fingerprint, NCS build, or flash. It requires the exact XIAO serial to be
  usable through explicit CMSIS-DAP v2 bulk USB, run
  inside the dev shell (`NIX_NRF_DOCTOR_SKIP_SDK=1 nix-nrf doctor --json |
  python3 tests/hardware/preflight_xiao.py 8EE9B3FF`).

## Flash recipes

Repository includes two flash recipes:

- [`../tcl/nrf53_flash.tcl`](../tcl/nrf53_flash.tcl) handles nRF5340 dual-core
  flash (app + net cores) with APPROTECT handling and mandatory UICR.APPROTECT
  programming.
- [`../tcl/nrf54l_flash.tcl`](../tcl/nrf54l_flash.tcl) handles nRF54L RRAM
  (RRAMC write-enable plus load/verify; no OpenOCD flash driver needed).

## Recovery safety

> [!WARNING]
> `flash_both APP_HEX NET_HEX` recovery mass-erases nRF53. It recovers only
> when the app core is locked by APPROTECT and `allow_recovery` permits: the
> two-argument form allows recovery by default, while a third argument `0`
> refuses it and aborts with an error. The west integration path
> (`check_approtect`) is recovery-enabled when the core is locked. Both paths
> mass-erase via `nrf53_recover` and then program UICR.APPROTECT to its
> unprotected value so the chip stays debuggable across resets.
>
> No known-good OpenOCD recovery exists for nRF54L. If APPROTECT engages on an
> nRF54L15, use Nordic's `nrfutil device recover` with a J-Link. Upstream
> OpenOCD has no supported recovery path for this family.

## See also

- [README](../README.md) has quick start and project initialization.
- [backends.md](backends.md) explains toolchain backends and bootstrap.
