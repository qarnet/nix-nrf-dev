# nix/backends/west/versions-command.nix — packaged `nix-nrf versions` command
# module for the west backend. Installs bin/backends/west/nix-nrf-west-versions
# at $out/libexec/nix-nrf/versions and exposes no standalone $out/bin command.
#
# The supported-release list comes ONLY from the sorted attr names of
# versions.nix (baked into the wrapper as NIX_NRF_WEST_VERSIONS /
# NIX_NRF_WEST_VERSIONS_JSON); the script source contains no release
# literals, so adding a release never requires touching command code.
#
# Contract:
#   nix-nrf versions          one supported west version per line, sorted
#   nix-nrf versions --json   JSON string array, sorted
#   nix-nrf versions --help   backend-specific help, exit 0
# Unknown options exit 2. The module never invokes nrfutil.
{
  pkgs,
  # versions.nix attrset keyed by NCS release (sorted attr names become the
  # supported-release list).
  versions,
}: let
  sortedNames = builtins.sort builtins.lessThan (builtins.attrNames versions);
  mkPythonCommand = import ../../lib/mk-python-command.nix {inherit pkgs;};
in
  mkPythonCommand {
    pname = "nix-nrf-versions-west";
    script = ../../../bin/backends/west/nix-nrf-west-versions;
    destination = "versions";
    wrapperArgs = [
      [
        "--set"
        "NIX_NRF_WEST_VERSIONS"
        (builtins.concatStringsSep "\n" sortedNames)
      ]
      [
        "--set"
        "NIX_NRF_WEST_VERSIONS_JSON"
        (builtins.toJSON sortedNames)
      ]
      [
        "--unset"
        "PYTHONPATH"
      ]
      [
        "--unset"
        "PYTHONHOME"
      ]
    ];
  }
