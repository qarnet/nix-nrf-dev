# nix-nrf-probes — internal probe/target identification module for the
# `nix-nrf probes` subcommand. Not a public package: no `$out/bin` binary is
# installed. `nix/nix-nrf.nix` resolves the exact store path of the wrapped
# command below and execs it.
{
  pkgs,
  openocd,
}:
pkgs.runCommand "nix-nrf-probes"
{
  nativeBuildInputs = [
    pkgs.makeWrapper
    pkgs.python3
  ];
}
''
  install -Dm755 ${../bin/nix-nrf-probes} $out/libexec/nix-nrf/probes
  patchShebangs $out/libexec/nix-nrf/probes
  # NCS toolchain shells export PYTHONPATH/PYTHONHOME for their own
  # python; unset them so the wrapped store python uses its stdlib.
  wrapProgram $out/libexec/nix-nrf/probes \
    --unset PYTHONPATH \
    --unset PYTHONHOME \
    --prefix PATH : ${openocd}/bin \
    --prefix PATH : ${pkgs.coreutils}/bin
''
