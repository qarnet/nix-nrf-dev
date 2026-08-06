# nix/commands/doctor.nix — internal read-only environment/probe-access
# diagnostics module for the `nix-nrf doctor` subcommand. Not a public
# package: no `$out/bin` binary is installed. `nix/commands/default.nix`
# resolves the exact store path of the wrapped command below and execs it.
#
# The wrapper pins:
#   - the exact bootstrap module executable in NIX_NRF_DOCTOR_BOOTSTRAP
#     (never ambient PATH lookup);
#   - the configured NCS version in NIX_NRF_DOCTOR_NCS_VERSION when non-null;
#   - the human environment label in NIX_NRF_DOCTOR_ENVIRONMENT_LABEL
#     (default "SDK/toolchain"; the west backend passes "west
#     workspace/Zephyr SDK"). Only human message strings use the label — JSON
#     field names/schema and exit semantics never change.
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
  # Human environment label for headings/status/remediation/help; default
  # "SDK/toolchain" keeps existing human output byte-identical.
  environmentLabel ? "SDK/toolchain",
}: let
  mkPythonCommand = import ../lib/mk-python-command.nix {inherit pkgs;};
in
  mkPythonCommand {
    pname = "nix-nrf-doctor";
    script = ../../bin/commands/nix-nrf-doctor;
    destination = "doctor";
    wrapperArgs =
      [
        [
          "--set"
          "NIX_NRF_DOCTOR_BOOTSTRAP"
          bootstrapCommand
        ]
        [
          "--set"
          "NIX_NRF_DOCTOR_ENVIRONMENT_LABEL"
          environmentLabel
        ]
        [
          "--unset"
          "PYTHONPATH"
        ]
        [
          "--unset"
          "PYTHONHOME"
        ]
      ]
      ++ pkgs.lib.optionals (udevRules != null) [
        [
          "--set"
          "NIX_NRF_DOCTOR_UDEV_RULES"
          udevRules
        ]
      ]
      ++ pkgs.lib.optionals (ncsVersion != null) [
        [
          "--set"
          "NIX_NRF_DOCTOR_NCS_VERSION"
          ncsVersion
        ]
      ];
  }
