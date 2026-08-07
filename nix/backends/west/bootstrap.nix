# nix/backends/west/bootstrap.nix — west backend west-workspace/venv bootstrap
# module. Installs bin/backends/west/nix-nrf-west-bootstrap at
# $out/libexec/nix-nrf/bootstrap and exposes no standalone $out/bin command:
# public invocation is only `nix-nrf bootstrap` (via the shell-specific
# backend-aware nix-nrf facade).
#
# The wrapper pins the exact Nix Python interpreter (selected by the
# release-specific `pythonPackage` metadata name from
# nix/backends/west/versions.nix) and the metadata defaults as environment
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
  mkPythonCommand = import ../../lib/mk-python-command.nix {inherit pkgs;};
in
  mkPythonCommand {
    pname = "nix-nrf-west-bootstrap";
    script = ../../../bin/backends/west/nix-nrf-west-bootstrap;
    destination = "bootstrap";
    wrapperArgs = [
      [
        "--set"
        "NIX_NRF_WEST_PYTHON"
        "${python}/bin/python3"
      ]
      [
        "--set"
        "NIX_NRF_WEST_NCS_VERSION"
        metadata.ncsVersion
      ]
      [
        "--set"
        "NIX_NRF_WEST_TESTED_WEST_VERSION"
        metadata.testedWestVersion
      ]
      [
        "--set"
        "NIX_NRF_WEST_REQUIREMENTS"
        (builtins.concatStringsSep "\n" metadata.requirements)
      ]
      [
        "--set"
        "NIX_NRF_WEST_PIP_CONSTRAINTS"
        (builtins.concatStringsSep "\n" (metadata.pipConstraints or []))
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
