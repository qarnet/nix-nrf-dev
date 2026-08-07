# nix/backends/nrfutil/default.nix — nrfutil backend entry point. Receives
# the internal dependencies (pkgs, OpenOCD, the default composed nrfutil, the
# udev-rules package, and the shared nix-nrf constructor) and returns the
# nrfutil shell constructor over normalized public shell options.
{
  pkgs,
  openocd-master,
  nrfutil,
  udevRules,
  nixNrf,
}:
import ./shell.nix {
  inherit
    pkgs
    openocd-master
    nrfutil
    udevRules
    ;
  nixNrfConstructor = nixNrf;
}
