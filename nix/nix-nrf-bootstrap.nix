# nix-nrf-bootstrap — internal SDK/toolchain bootstrap module for the
# `nix-nrf bootstrap` subcommand. Not a public package: no `$out/bin` binary
# is installed. `nix/nix-nrf.nix` resolves the exact store path of the wrapped
# command below and execs it.
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
}:
pkgs.runCommand "nix-nrf-bootstrap"
{
  nativeBuildInputs = [
    pkgs.makeWrapper
    pkgs.python3
  ];
}
''
  install -Dm755 ${../bin/nix-nrf-bootstrap} $out/libexec/nix-nrf/bootstrap
  patchShebangs $out/libexec/nix-nrf/bootstrap
  # NCS toolchain shells export PYTHONPATH/PYTHONHOME for their own
  # python; unset them so the wrapped store python uses its stdlib.
  wrapProgram $out/libexec/nix-nrf/bootstrap \
    --set NIX_NRF_NRFUTIL ${nrfutilPackage}/bin/nrfutil \
    --unset PYTHONPATH \
    --unset PYTHONHOME \
    ${pkgs.lib.optionalString (ncsVersion != null) "--set NIX_NRF_NCS_VERSION ${ncsVersion}"} \
    ${pkgs.lib.optionalString (
    toolchainBundleId != null
  ) "--set NIX_NRF_TOOLCHAIN_BUNDLE_ID ${toolchainBundleId}"}
''
