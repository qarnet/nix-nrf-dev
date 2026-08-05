# nix-nrf-udev-rules — thin relocation package exposing OpenOCD's canonical
# 60-openocd.rules under the udev layout NixOS imports
# ($out/lib/udev/rules.d, see `services.udev.packages` in the pinned Nixpkgs
# `nixos/modules/services/hardware/udev.nix`).
#
# The rule file is copied byte-for-byte from the pinned OpenOCD build's
# $out/share/openocd/contrib/60-openocd.rules — upstream SPDX header and
# content preserved, no repository VID/PID catalog, no custom rules. The
# build fails when the source rule is absent. OpenOCD's contrib rule covers
# generic `*CMSIS-DAP*` products plus SEGGER J-Link VID/PIDs and applies to
# the usb, tty, and hidraw subsystems with MODE="660", GROUP="plugdev",
# TAG+="uaccess".
{
  pkgs,
  openocd,
}:
pkgs.runCommand "nix-nrf-udev-rules"
{
  srcRule = "${openocd}/share/openocd/contrib/60-openocd.rules";
}
''
  if [ ! -f "$srcRule" ]; then
    echo "nix-nrf-udev-rules: source rule not found: $srcRule" >&2
    exit 1
  fi
  install -Dm644 "$srcRule" "$out/lib/udev/rules.d/60-openocd.rules"
''
