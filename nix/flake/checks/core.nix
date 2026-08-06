# Shared core gates: standalone `nix-nrf --help` wording, fake-boundary
# doctor tests, udev-rule byte-identity, and shell-doctor udev wiring.
# `defaultDevShell` is the flake's devShells.default (constructed by
# dev-shells.nix), passed explicitly; the check pulls the exact packaged
# nix-nrf from it, same derivation as self.devShells.${system}.default.
# Comments moved verbatim with the implementations.
{
  pkgs,
  nix-nrf,
  nrfUdevRules,
  openocd-master-unwrapped,
  defaultDevShell,
}: let
  # Public `nix-nrf --help` wording gate: the standalone (nrfutil)
  # facade must keep today's byte-for-byte command descriptions
  # (versions via sdk-manager, bootstrap/doctor on SDK/toolchain).
  # The west shell's backend-aware descriptions are asserted in
  # checks.west-shell-boundary.
  nixNrfHelpCheck =
    pkgs.runCommand "nix-nrf-help-check"
    {
      # Aliased: a `nix-nrf` env var name (with dash) is not usable
      # from bash.
      nixNrf = nix-nrf;
    }
    ''
        "$nixNrf/bin/nix-nrf" --help > help.txt
      grep -F "versions   List NCS releases advertised by Nordic sdk-manager" help.txt >/dev/null || { echo "FAIL: standalone versions wording changed" >&2; cat help.txt >&2; exit 1; }
      grep -F "bootstrap  Ensure the selected NCS SDK source and toolchain exist" help.txt >/dev/null || { echo "FAIL: standalone bootstrap wording changed" >&2; cat help.txt >&2; exit 1; }
      grep -F "doctor     Diagnose SDK/toolchain and probe access (read-only)" help.txt >/dev/null || { echo "FAIL: standalone doctor wording changed" >&2; cat help.txt >&2; exit 1; }
      echo "nix-nrf help wording check passed" >&2
      mkdir -p "$out"
    '';

  # Fake-boundary doctor test gate: runs
  # tests/unit/test_nix_nrf_doctor.py against temporary fake
  # sysfs/dev roots and a fake bootstrap command, with sandboxed
  # Python stdlib. Proves candidate discovery, node mapping, access
  # classification (hidraw/USB fallback), SDK check boundaries,
  # remediation, JSON schema, and exit codes — no hardware, no real
  # /sys or /dev, no network, no SDK.
  doctorTests =
    pkgs.runCommand "nix-nrf-doctor-tests"
    {
      nativeBuildInputs = [pkgs.python3];
      doctorScript = ../../../bin/commands/nix-nrf-doctor;
      testFile = ../../../tests/unit/test_nix_nrf_doctor.py;
    }
    ''
      cp "$doctorScript" nix-nrf-doctor
      chmod +x nix-nrf-doctor
      cp "$testFile" test_nix_nrf_doctor.py
      NIX_NRF_DOCTOR_SCRIPT="$PWD/nix-nrf-doctor" python3 test_nix_nrf_doctor.py
      echo "doctor tests passed" >&2
      mkdir -p "$out"
    '';

  # Udev-rule gate: builds the relocation package, verifies the
  # destination exists, and proves the installed rule is byte-for-byte
  # identical to the pinned OpenOCD contrib file. Never builds a whole
  # NixOS system.
  udevRulesCheck =
    pkgs.runCommand "nix-nrf-udev-rules-check"
    {
      inherit nrfUdevRules;
      contribRule = "${openocd-master-unwrapped}/share/openocd/contrib/60-openocd.rules";
    }
    ''
      installed="$nrfUdevRules/lib/udev/rules.d/60-openocd.rules"
      [ -f "$installed" ] || {
        echo "udev-rules check: missing installed rule $installed" >&2
        exit 1
      }
      cmp "$installed" "$contribRule" || {
        echo "udev-rules check: installed rule differs byte-for-byte from the pinned OpenOCD contrib rule" >&2
        exit 1
      }
      echo "udev-rules check passed: installed rule is byte-identical to the pinned OpenOCD contrib rule" >&2
      mkdir -p "$out"
    '';

  # Shell doctor udev-rules wiring gate: proves the shell-instantiated
  # `nix-nrf doctor` (from devShells.default, built through mkNrfShell's
  # internal udevRules closure wiring) reports the exact packaged udev
  # rule path in its remediation. Runs the real shell `nix-nrf doctor`
  # against a temporary fake sysfs/dev root with one blocked candidate —
  # no host USB, no network, no SDK. Regresses the pre-fix state where
  # mkNrfShell omitted udevRules and the shell doctor dropped the exact
  # packaged-rule-path line.
  doctorUdevWiringCheck = let
    devShell = defaultDevShell;
    nixNrf = let
      matches = builtins.filter (p: p.name == "nix-nrf") (devShell.nativeBuildInputs or []);
    in
      if matches == []
      then null
      else builtins.head matches;
  in
    pkgs.runCommand "nix-nrf-doctor-udev-wiring-check"
    {
      inherit nixNrf;
      expectedUdevRules = nrfUdevRules;
    }
    ''
      [ -n "$nixNrf" ] || {
        echo "doctor udev-rules wiring check: nix-nrf not found in devShell inputs" >&2
        exit 1
      }
      mkdir -p sysfs/1-9 dev/bus/usb/001
      echo "Fake CMSIS-DAP" > sysfs/1-9/product
      echo 1 > sysfs/1-9/busnum
      echo 2 > sysfs/1-9/devnum
      NIX_NRF_DOCTOR_SYSFS_ROOT="$PWD/sysfs" \
      NIX_NRF_DOCTOR_DEV_ROOT="$PWD/dev" \
      NIX_NRF_DOCTOR_SKIP_SDK=1 \
      "$nixNrf"/bin/nix-nrf doctor > doctor.out 2>&1 || true
      grep -q "Packaged udev rule: $expectedUdevRules/lib/udev/rules.d/60-openocd.rules" doctor.out || {
        echo "doctor udev-rules wiring check: exact packaged udev rule path missing from shell doctor output" >&2
        cat doctor.out >&2
        exit 1
      }
      echo "doctor udev-rules wiring check passed: shell doctor reports $expectedUdevRules" >&2
      mkdir -p "$out"
    '';
in {
  nix-nrf-help = nixNrfHelpCheck;
  doctor-tests = doctorTests;
  udev-rules = udevRulesCheck;
  doctor-udev-wiring = doctorUdevWiringCheck;
}
