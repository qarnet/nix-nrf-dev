# nrf-probes — read-only CMSIS-DAP probe/target identification tool.
{
  pkgs,
  openocd,
}:
pkgs.runCommand "nrf-probes"
{
  nativeBuildInputs = [
    pkgs.makeWrapper
    pkgs.python3
  ];
}
''
  install -Dm755 ${../bin/nrf-probes} $out/bin/nrf-probes
  patchShebangs $out/bin/nrf-probes
  # NCS toolchain shells export PYTHONPATH/PYTHONHOME for their own
  # python; unset them so the wrapped store python uses its stdlib.
  wrapProgram $out/bin/nrf-probes \
    --unset PYTHONPATH \
    --unset PYTHONHOME \
    --prefix PATH : ${openocd}/bin
''
