# Shared SDK-independent west layer. Only registration metadata is inspected;
# neither this helper nor doctor imports extension implementations.
{
  pkgs,
  ncsVersion,
  sourceConfig ? {
    command = null;
  },
}: let
  python = pkgs.python3.withPackages (ps: [ps.west]);
  mkCommand = import ../lib/mk-python-command.nix {
    pkgs =
      pkgs
      // {
        python3 = python;
      };
  };
in
  mkCommand {
    pname = "nix-nrf-west-core";
    script = ../../bin/commands/nix-nrf-west-core;
    destination = "west-core";
    wrapperArgs = [
      [
        "--unset"
        "PYTHONHOME"
      ]
      [
        "--unset"
        "PYTHONPATH"
      ]
      [
        "--set"
        "PYTHONDONTWRITEBYTECODE"
        "1"
      ]
      [
        "--prefix"
        "PATH"
        ":"
        "${pkgs.git}/bin"
      ]
      [
        "--set"
        "NIX_NRF_WEST_CORE_EXE"
        "${python}/bin/west"
      ]
      [
        "--set"
        "NIX_NRF_WEST_NCS_VERSION"
        ncsVersion
      ]
      [
        "--set"
        "NIX_NRF_WEST_SOURCE_MODE"
        (
          if sourceConfig.command == null
          then "managed"
          else "workspace"
        )
      ]
      [
        "--set-default"
        "NIX_NRF_WEST_WORKSPACE"
        (
          if sourceConfig.command == null
          then ""
          else sourceConfig.workspace or ""
        )
      ]
    ];
  }
