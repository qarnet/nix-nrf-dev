# nix/backends/west/versions-command.nix — packaged `nix-nrf versions` command
# module for the west backend. Installs bin/nix-nrf-west-versions at
# $out/libexec/nix-nrf/versions and exposes no standalone $out/bin command.
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
in
  pkgs.runCommand "nix-nrf-versions-west"
  {
    nativeBuildInputs = [
      pkgs.makeWrapper
      pkgs.python3
    ];
  }
  ''
    install -Dm755 ${../../../bin/nix-nrf-west-versions} $out/libexec/nix-nrf/versions
    patchShebangs $out/libexec/nix-nrf/versions
    # Values are shell-escaped before interpolation so wrapProgram arguments
    # never break the generated build script (version strings with spaces or
    # quotes would otherwise terminate the wrapper's argument list).
    wrapProgram $out/libexec/nix-nrf/versions \
      --set NIX_NRF_WEST_VERSIONS ${pkgs.lib.escapeShellArg (pkgs.lib.concatStringsSep "\n" sortedNames)} \
      --set NIX_NRF_WEST_VERSIONS_JSON ${pkgs.lib.escapeShellArg (builtins.toJSON sortedNames)} \
      --unset PYTHONPATH \
      --unset PYTHONHOME
  ''
