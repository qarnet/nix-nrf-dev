# nix/backends/nrfutil/bootstrap.nix — nrfutil backend SDK/toolchain bootstrap
# module for the `nix-nrf bootstrap` subcommand. Not a public package: no
# `$out/bin` binary is installed. `nix/commands/default.nix` resolves the
# exact store path of the wrapped command below and execs it.
#
# The wrapper pins the exact selected nrfutil executable in NIX_NRF_NRFUTIL
# (never ambient PATH lookup) and, when non-null, the configured defaults in
# NIX_NRF_NCS_VERSION / NIX_NRF_TOOLCHAIN_BUNDLE_ID. PYTHONHOME/PYTHONPATH are
# unset like the probes module, because NCS toolchain shells export them for
# their own python.
{
  pkgs,
  nrfutilPackage,
  ncsVersion ? null,
  toolchainBundleId ? null,
}: let
  mkPythonCommand = import ../../lib/mk-python-command.nix {inherit pkgs;};
in
  mkPythonCommand {
    pname = "nix-nrf-bootstrap";
    script = ../../../bin/backends/nrfutil/nix-nrf-bootstrap;
    destination = "bootstrap";
    wrapperArgs =
      [
        [
          "--set"
          "NIX_NRF_NRFUTIL"
          "${nrfutilPackage}/bin/nrfutil"
        ]
        [
          "--unset"
          "PYTHONPATH"
        ]
        [
          "--unset"
          "PYTHONHOME"
        ]
      ]
      ++ pkgs.lib.optionals (ncsVersion != null) [
        [
          "--set"
          "NIX_NRF_NCS_VERSION"
          ncsVersion
        ]
      ]
      ++ pkgs.lib.optionals (toolchainBundleId != null) [
        [
          "--set"
          "NIX_NRF_TOOLCHAIN_BUNDLE_ID"
          toolchainBundleId
        ]
      ];
  }
