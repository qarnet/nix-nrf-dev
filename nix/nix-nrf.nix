# nix-nrf — the project CLI facade for the nix-nrf-dev tools.
#
# Fixed dispatcher with four subcommands:
#   nix-nrf versions   — delegate to `nrfutil sdk-manager search` (NCS version
#     list; sdk-manager remains the runtime authority for available versions).
#   nix-nrf probes     — delegate to the internal probe command module
#     (`./nix-nrf-probes.nix`, installed at $out/libexec/nix-nrf/probes; read-only
#     CMSIS-DAP probe/target identification).
#   nix-nrf bootstrap  — delegate to the internal bootstrap command module
#     (`./nix-nrf-bootstrap.nix`, installed at $out/libexec/nix-nrf/bootstrap;
#     ensures the configured NCS SDK source and selected toolchain exist).
#     `ncsVersion`/`toolchainBundleId` defaults are null here (explicit
#     `--ncs-version` required at runtime), so `nix run .# -- bootstrap
#     --ncs-version v3.3.0 --check` works; `mkNrfShell` passes its selected
#     values so the shell's `nix-nrf bootstrap` works with no arguments.
#   nix-nrf doctor     — delegate to the internal doctor command module
#     (`./nix-nrf-doctor.nix`, installed at $out/libexec/nix-nrf/doctor;
#     read-only SDK/toolchain and probe-access diagnostics). The base
#     `packages.nix-nrf` has no NCS default, so its doctor skips the SDK
#     selection but still diagnoses hardware; the shell-specific nix-nrf
#     passes the configured selector.
#
# Delegation uses exact Nix store executable paths derived from the selected
# packages — never ambient PATH lookup — and `exec`, so delegated stdout,
# stderr, options, and exit status are preserved unchanged. `nix-nrf` owns its
# project command modules; there is no standalone `nrf-bootstrap`/`nrf-probes`/
# `nrf-doctor` binary or package. No dynamic plugin discovery in this phase.
{
  pkgs,
  nrfutilPackage,
  openocd,
  ncsVersion ? null,
  toolchainBundleId ? null,
  # The udev-rules package (see ./nrf-udev-rules.nix) whose exact store path
  # the doctor reports in its remediation. null keeps the doctor fully
  # functional but omits the exact packaged-rule-path line.
  udevRules ? null,
}: let
  nrfProbes = import ./nix-nrf-probes.nix {
    inherit pkgs openocd;
  };
  # One shared bootstrap module value: the dispatcher and the doctor use the
  # exact same store path (the doctor only ever runs its read-only --check
  # path).
  nrfBootstrap = import ./nix-nrf-bootstrap.nix {
    inherit
      pkgs
      nrfutilPackage
      ncsVersion
      toolchainBundleId
      ;
  };
  nrfDoctor = import ./nix-nrf-doctor.nix {
    inherit
      pkgs
      ncsVersion
      udevRules
      ;
    bootstrapCommand = "${nrfBootstrap}/libexec/nix-nrf/bootstrap";
  };
in
  pkgs.writeShellApplication {
    name = "nix-nrf";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      nrfutil_exe=${nrfutilPackage}/bin/nrfutil
      nrf_probes_exe=${nrfProbes}/libexec/nix-nrf/probes
      nrf_bootstrap_exe=${nrfBootstrap}/libexec/nix-nrf/bootstrap
      nrf_doctor_exe=${nrfDoctor}/libexec/nix-nrf/doctor

      usage() {
        cat <<'EOF'
      Usage: nix-nrf <command> [options]

      Commands:
        versions   List NCS releases advertised by Nordic sdk-manager
        probes     Identify CMSIS-DAP probes and targets (read-only)
        bootstrap  Ensure the selected NCS SDK source and toolchain exist
        doctor     Diagnose SDK/toolchain and probe access (read-only)

      Run `nix-nrf help <command>` for command-specific help.
      EOF
      }

      cmd="''${1:-}"
      case "$cmd" in
        ""|-h|--help)
          usage
          exit 0
          ;;
        help)
          case "''${2:-}" in
            "")
              usage
              exit 0
              ;;
            versions)
              exec "$nrfutil_exe" sdk-manager search --help
              ;;
            probes)
              exec "$nrf_probes_exe" --help
              ;;
            bootstrap)
              exec "$nrf_bootstrap_exe" --help
              ;;
            doctor)
              exec "$nrf_doctor_exe" --help
              ;;
            *)
              echo "nix-nrf: unknown help topic '$2'" >&2
              usage >&2
              exit 2
              ;;
          esac
          ;;
        versions)
          shift
          exec "$nrfutil_exe" sdk-manager search "$@"
          ;;
        probes)
          shift
          exec "$nrf_probes_exe" "$@"
          ;;
        bootstrap)
          shift
          exec "$nrf_bootstrap_exe" "$@"
          ;;
        doctor)
          shift
          exec "$nrf_doctor_exe" "$@"
          ;;
        *)
          echo "nix-nrf: unknown command '$cmd'" >&2
          usage >&2
          exit 2
          ;;
      esac
    '';
  }
