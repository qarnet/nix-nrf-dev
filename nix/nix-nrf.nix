# nix-nrf — the project CLI facade for the nix-nrf-dev tools.
#
# Fixed dispatcher with four subcommands:
#   nix-nrf versions   — by default delegates to `nrfutil sdk-manager search`
#     (NCS version list; sdk-manager remains the runtime authority for
#     available versions). The west backend supplies an exact `versionsCommand`
#     store path instead, which lists repository-supported west backend
#     metadata versions and never invokes nrfutil.
#   nix-nrf probes     — delegate to the internal probe command module
#     (`./nix-nrf-probes.nix`, installed at $out/libexec/nix-nrf/probes; read-only
#     CMSIS-DAP probe/target identification).
#   nix-nrf bootstrap  — by default delegates to the internal nrfutil-backed
#     bootstrap command module (`./nix-nrf-bootstrap.nix`, installed at
#     $out/libexec/nix-nrf/bootstrap; ensures the configured NCS SDK source
#     and selected toolchain exist). The west backend supplies an exact
#     `bootstrapCommand` store path instead (its west-workspace/venv bootstrap
#     module). `ncsVersion`/`toolchainBundleId` defaults are null here
#     (explicit `--ncs-version` required at runtime), so `nix run .# --
#     bootstrap --ncs-version v3.3.0 --check` works; `mkNrfShell` passes its
#     selected values so the shell's `nix-nrf bootstrap` works with no
#     arguments.
#   nix-nrf doctor     — delegate to the internal doctor command module
#     (`./nix-nrf-doctor.nix`, installed at $out/libexec/nix-nrf/doctor;
#     read-only SDK/toolchain and probe-access diagnostics). The base
#     `packages.nix-nrf` has no NCS default, so its doctor skips the SDK
#     selection but still diagnoses hardware; the shell-specific nix-nrf
#     passes the configured selector and, via mkNrfShell's internal udevRules
#     closure wiring, the exact udev-rules package path. The doctor always
#     receives the selected exact bootstrap command and runs only its
#     read-only `--check --quiet --print-sdk-path` path; the west backend
#     additionally passes `doctorEnvironmentLabel` for its human messages.
#
# Delegation uses exact Nix store executable paths derived from the selected
# packages — never ambient PATH lookup — and `exec`, so delegated stdout,
# stderr, options, and exit status are preserved unchanged. `nix-nrf` owns its
# project command modules; there is no standalone `nrf-bootstrap`/`nrf-probes`/
# `nrf-doctor` binary or package. No dynamic plugin discovery in this phase.
{
  pkgs,
  openocd,
  ncsVersion ? null,
  toolchainBundleId ? null,
  # The udev-rules package (see ./nrf-udev-rules.nix) whose exact store path
  # the doctor wrapper reports in its remediation (NIX_NRF_DOCTOR_UDEV_RULES).
  # flake.nix and mkNrfShell (internal `udevRules` closure wiring) always pass
  # the real package, so both the standalone and the shell-specific doctor
  # name the exact packaged rule file. The null default exists only as a
  # safety net for direct external instantiation; a null doctor is fully
  # functional but omits the exact packaged-rule-path line.
  udevRules ? null,
  # Exact west backend command module store paths (optional). When both are
  # provided, `versions` and `bootstrap` dispatch to these exact store paths
  # and the nrfutil-backed versions/bootstrap modules are not constructed (no
  # runtime nrfutil/sdk-manager use); the standalone package passes neither
  # and keeps today's nrfutil behavior. `nrfutilPackage` may be null only
  # when both west command modules are provided.
  versionsCommand ? null,
  bootstrapCommand ? null,
  # Optional human environment label for `doctor` (default "SDK/toolchain"
  # for compatibility). Only human message strings reflect the label; JSON
  # field names/schema and exit semantics never change.
  doctorEnvironmentLabel ? null,
  # Packaged nrfutil used for the default versions/bootstrap modules.
  nrfutilPackage ? null,
}:
assert versionsCommand
!= null
|| nrfutilPackage != null
|| throw "nix-nrf: versionsCommand or nrfutilPackage is required (west backend must pass its exact versions command; the default needs the packaged nrfutil)";
assert bootstrapCommand
!= null
|| nrfutilPackage != null
|| throw "nix-nrf: bootstrapCommand or nrfutilPackage is required (west backend must pass its exact bootstrap command; the default needs the packaged nrfutil)"; let
  nrfProbes = import ./nix-nrf-probes.nix {
    inherit pkgs openocd;
  };
  # One shared bootstrap module value: the dispatcher and the doctor use the
  # exact same store path (the doctor only ever runs its read-only --check
  # path). The west backend supplies its exact bootstrap module; otherwise the
  # nrfutil-backed module is constructed here (current behavior).
  bootstrapExe =
    if bootstrapCommand != null
    then bootstrapCommand
    else "${
      import ./nix-nrf-bootstrap.nix {
        inherit
          pkgs
          nrfutilPackage
          ncsVersion
          toolchainBundleId
          ;
      }
    }/libexec/nix-nrf/bootstrap";
  nrfDoctor = import ./nix-nrf-doctor.nix {
    inherit
      pkgs
      ncsVersion
      udevRules
      ;
    bootstrapCommand = bootstrapExe;
    environmentLabel =
      if doctorEnvironmentLabel != null
      then doctorEnvironmentLabel
      else "SDK/toolchain";
  };
  # Human help lines: `versions`/`bootstrap`/`doctor` descriptions differ per
  # backend. The west shell names its `west workspace/Zephyr SDK`; the
  # nrfutil/standalone wording stays byte-for-byte current. `bootstrapCommand`
  # being provided marks the west mode (its exact module is what bootstrap and
  # doctor operate on).
  versionsDesc =
    if versionsCommand != null
    then "versions   List NCS releases supported by the west backend metadata"
    else "versions   List NCS releases advertised by Nordic sdk-manager";
  bootstrapDesc =
    if bootstrapCommand != null
    then "bootstrap  Ensure the west workspace and version-local venv exist"
    else "bootstrap  Ensure the selected NCS SDK source and toolchain exist";
  doctorDesc =
    if bootstrapCommand != null
    then "doctor     Diagnose west workspace/Zephyr SDK and probe access (read-only)"
    else "doctor     Diagnose SDK/toolchain and probe access (read-only)";
  versionsHelp =
    if versionsCommand != null
    then "exec \"$nrf_versions_exe\" --help"
    else "exec \"$nrfutil_exe\" sdk-manager search --help";
  versionsExec =
    if versionsCommand != null
    then "exec \"$nrf_versions_exe\" \"$@\""
    else "exec \"$nrfutil_exe\" sdk-manager search \"$@\"";
in
  pkgs.writeShellApplication {
    name = "nix-nrf";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      ${pkgs.lib.optionalString (nrfutilPackage != null) "nrfutil_exe=${nrfutilPackage}/bin/nrfutil"}
      ${pkgs.lib.optionalString (versionsCommand != null) "nrf_versions_exe=${versionsCommand}"}
      nrf_probes_exe=${nrfProbes}/libexec/nix-nrf/probes
      nrf_bootstrap_exe=${bootstrapExe}
      nrf_doctor_exe=${nrfDoctor}/libexec/nix-nrf/doctor

      usage() {
        cat <<'EOF'
      Usage: nix-nrf <command> [options]

        Commands:
          ${versionsDesc}
          probes     Identify CMSIS-DAP probes and targets (read-only)
          ${bootstrapDesc}
          ${doctorDesc}

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
              ${versionsHelp}
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
          ${versionsExec}
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
