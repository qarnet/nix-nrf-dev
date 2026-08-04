# nrf-sdk-versions — list NCS releases advertised by Nordic sdk-manager.
#
# Delegates to `nrfutil sdk-manager search` without parsing or maintaining a
# local version list: sdk-manager is the runtime authority for available NCS
# versions. Native output, options, network behavior, and exit status are
# preserved.
{
  pkgs,
  nrfutilPackage,
}:
pkgs.writeShellApplication {
  name = "nrf-sdk-versions";
  runtimeInputs = [nrfutilPackage];
  text = ''
    exec nrfutil sdk-manager search "$@"
  '';
}
