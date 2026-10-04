{
  pkgs,
  openocd,
  doctor,
}: let
  mkPythonCommand = import ../lib/mk-python-command.nix {inherit pkgs;};
in
  mkPythonCommand {
    pname = "nix-nrf-session";
    script = ../../bin/commands/nix-nrf-session;
    destination = "session";
    wrapperArgs = [
      [
        "--unset"
        "PYTHONPATH"
      ]
      [
        "--unset"
        "PYTHONHOME"
      ]
      [
        "--set"
        "NIX_NRF_SESSION_OPENOCD"
        "${openocd}/bin/openocd"
      ]
      [
        "--set"
        "NIX_NRF_SESSION_DOCTOR"
        "${doctor}/libexec/nix-nrf/doctor"
      ]
    ];
  }
