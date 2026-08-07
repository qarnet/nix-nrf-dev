# nix/commands/probes.nix — internal probe/target identification module for
# the `nix-nrf probes` subcommand. Not a public package: no `$out/bin` binary
# is installed. `nix/commands/default.nix` resolves the exact store path of
# the wrapped command below and execs it.
{
  pkgs,
  openocd,
}: let
  mkPythonCommand = import ../lib/mk-python-command.nix {inherit pkgs;};
in
  mkPythonCommand {
    pname = "nix-nrf-probes";
    script = ../../bin/commands/nix-nrf-probes;
    destination = "probes";
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
        "--prefix"
        "PATH"
        ":"
        "${openocd}/bin"
      ]
      [
        "--prefix"
        "PATH"
        ":"
        "${pkgs.coreutils}/bin"
      ]
    ];
  }
