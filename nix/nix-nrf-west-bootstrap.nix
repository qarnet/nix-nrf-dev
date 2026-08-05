# nix-nrf-west-bootstrap — internal west-workspace/venv bootstrap module for
# the west backend. Installs bin/nix-nrf-west-bootstrap at
# $out/libexec/nix-nrf/bootstrap and exposes no standalone $out/bin command:
# public invocation is only `nix-nrf bootstrap` (via the shell-specific
# backend-aware nix-nrf facade).
#
# The wrapper pins the exact Nix Python interpreter (selected by the
# release-specific `pythonPackage` metadata name from
# nix/west-backend/versions.nix) and the metadata defaults as environment
# variables — never ambient PATH lookup — and unsets PYTHONHOME/PYTHONPATH
# like the other command modules, because NCS toolchain shells export them
# for their own python.
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
  # Nixpkgs package attribute name for the exact Nix Python used to create
  # the version-local venv (e.g. "python312" from versions.nix metadata).
  pythonPackage,
  # Version metadata entry (versions.nix), keyed by NCS release.
  metadata,
}: let
  python =
    pkgs.${pythonPackage}
      or (throw "nix-nrf-west-bootstrap: unknown Python package '${pythonPackage}' for NCS ${metadata.ncsVersion}");
in
  pkgs.runCommand "nix-nrf-west-bootstrap"
  {
    nativeBuildInputs = [
      pkgs.makeWrapper
      pkgs.python3
    ];
  }
  ''
    install -Dm755 ${../bin/nix-nrf-west-bootstrap} $out/libexec/nix-nrf/bootstrap
    patchShebangs $out/libexec/nix-nrf/bootstrap
    # Metadata values are shell-escaped before interpolation so wrapProgram
    # arguments never break the generated build script.
    wrapProgram $out/libexec/nix-nrf/bootstrap \
      --set NIX_NRF_WEST_PYTHON ${python}/bin/python3 \
      --set NIX_NRF_WEST_NCS_VERSION ${pkgs.lib.escapeShellArg metadata.ncsVersion} \
      --set NIX_NRF_WEST_TESTED_WEST_VERSION ${pkgs.lib.escapeShellArg metadata.testedWestVersion} \
      --set NIX_NRF_WEST_REQUIREMENTS ${pkgs.lib.escapeShellArg (pkgs.lib.concatStringsSep "\n" metadata.requirements)} \
      --set NIX_NRF_WEST_PIP_CONSTRAINTS ${
      pkgs.lib.escapeShellArg (pkgs.lib.concatStringsSep "\n" (metadata.pipConstraints or []))
    } \
      --unset PYTHONPATH \
      --unset PYTHONHOME
  ''
