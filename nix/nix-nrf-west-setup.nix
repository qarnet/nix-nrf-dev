# nix-nrf-west-setup — internal west-workspace/venv setup module for the west
# backend prototype. Installs bin/nix-nrf-west-setup at
# $out/libexec/nix-nrf/west-setup and exposes it as
# $out/bin/nix-nrf-west-setup (the temporary prototype command).
#
# The wrapper pins the exact Nix Python interpreter and the metadata defaults
# (see nix/west-backend/versions.nix) as environment variables — never ambient
# PATH lookup — and unsets PYTHONHOME/PYTHONPATH like the other command
# modules, because NCS toolchain shells export them for their own python.
#
#   NIX_NRF_WEST_PYTHON              exact Nix Python executable (venv creator)
#   NIX_NRF_WEST_NCS_VERSION         NCS release key
#   NIX_NRF_WEST_TESTED_WEST_VERSION west pinned before workspace creation
#   NIX_NRF_WEST_REQUIREMENTS        newline-separated requirement paths,
#                                    relative to the workspace
#   NIX_NRF_WEST_PIP_CONSTRAINTS     newline-separated pip constraint lines
#                                    applied via `pip install -c` (release-
#                                    specific pins, e.g. cbor2==5.9.0)
#
# No builder file below hardcodes any release-specific value: everything comes
# from the metadata attrset passed in.
{
  pkgs,
  # Exact Nix Python used to create the version-local venv.
  python,
  # Version metadata entry (versions.nix), keyed by NCS release.
  metadata,
}:
pkgs.runCommand "nix-nrf-west-setup"
{
  nativeBuildInputs = [
    pkgs.makeWrapper
    pkgs.python3
  ];
}
''
  install -Dm755 ${../bin/nix-nrf-west-setup} $out/libexec/nix-nrf/west-setup
  patchShebangs $out/libexec/nix-nrf/west-setup
  # Metadata values are shell-escaped before interpolation so wrapProgram
  # arguments never break the generated build script.
  wrapProgram $out/libexec/nix-nrf/west-setup \
    --set NIX_NRF_WEST_PYTHON ${python}/bin/python3 \
    --set NIX_NRF_WEST_NCS_VERSION ${pkgs.lib.escapeShellArg metadata.ncsVersion} \
    --set NIX_NRF_WEST_TESTED_WEST_VERSION ${pkgs.lib.escapeShellArg metadata.testedWestVersion} \
    --set NIX_NRF_WEST_REQUIREMENTS ${pkgs.lib.escapeShellArg (pkgs.lib.concatStringsSep "\n" metadata.requirements)} \
    --set NIX_NRF_WEST_PIP_CONSTRAINTS ${
    pkgs.lib.escapeShellArg (pkgs.lib.concatStringsSep "\n" (metadata.pipConstraints or []))
  } \
    --unset PYTHONPATH \
    --unset PYTHONHOME
  mkdir -p $out/bin
  ln -s $out/libexec/nix-nrf/west-setup $out/bin/nix-nrf-west-setup
''
