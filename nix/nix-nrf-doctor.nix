# nix-nrf-doctor — internal read-only environment/probe-access diagnostics
# module for the `nix-nrf doctor` subcommand. Not a public package: no
# `$out/bin` binary is installed. `nix/nix-nrf.nix` resolves the exact store
# path of the wrapped command below and execs it.
#
# The wrapper pins:
#   - the exact bootstrap module executable in NIX_NRF_DOCTOR_BOOTSTRAP
#     (never ambient PATH lookup);
#   - the configured NCS version in NIX_NRF_DOCTOR_NCS_VERSION when non-null;
#   - the exact udev-rules package store path in NIX_NRF_DOCTOR_UDEV_RULES
#     when provided (doctor then names the exact packaged rule file in its
#     remediation);
#   - PYTHONHOME/PYTHONPATH unset, like the other command modules, because
#     NCS toolchain shells export them for their own python.
#
# The test roots (NIX_NRF_DOCTOR_SYSFS_ROOT, NIX_NRF_DOCTOR_DEV_ROOT,
# NIX_NRF_DOCTOR_SKIP_SDK) are read by the script with their own defaults and
# are never forced here.
{
  pkgs,
  bootstrapCommand,
  ncsVersion ? null,
  udevRules ? null,
}:
pkgs.runCommand "nix-nrf-doctor"
{
  nativeBuildInputs = [
    pkgs.makeWrapper
    pkgs.python3
  ];
}
''
  install -Dm755 ${../bin/nix-nrf-doctor} $out/libexec/nix-nrf/doctor
  patchShebangs $out/libexec/nix-nrf/doctor
  # Caller-controlled selector values are shell-escaped before interpolation
  # so wrapProgram arguments never break the generated build script.
  wrapProgram $out/libexec/nix-nrf/doctor \
    --set NIX_NRF_DOCTOR_BOOTSTRAP ${bootstrapCommand} \
    --unset PYTHONPATH \
    --unset PYTHONHOME \
    ${pkgs.lib.optionalString (udevRules != null) "--set NIX_NRF_DOCTOR_UDEV_RULES ${udevRules}"} \
    ${pkgs.lib.optionalString (
    ncsVersion != null
  ) "--set NIX_NRF_DOCTOR_NCS_VERSION ${pkgs.lib.escapeShellArg ncsVersion}"}
''
