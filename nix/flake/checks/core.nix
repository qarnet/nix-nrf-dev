# Shared core gates: standalone `nix-nrf --help` wording, fake-boundary
# doctor tests, XIAO doctor preflight parser tests, udev-rule byte-identity,
# shell-doctor udev wiring, and fake-OpenOCD flash-recipe semantic tests.
# `defaultDevShell` is the flake's devShells.default (constructed by
# dev-shells.nix), passed explicitly; the check pulls the exact packaged
# nix-nrf from it, same derivation as self.devShells.${system}.default.
{
  pkgs,
  nix-nrf,
  nrfUdevRules,
  openocd-master-unwrapped,
  defaultDevShell,
  self,
  nixpkgs,
  system,
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
      "$nixNrf/bin/nix-nrf" help probes > probes-help.txt
      grep -F "Identify chips attached to CMSIS-DAP probes (read-only)" probes-help.txt >/dev/null || { echo "FAIL: `nix-nrf help probes` did not reach the packaged probe command help" >&2; cat probes-help.txt >&2; exit 1; }
      echo "nix-nrf help wording check passed" >&2
      mkdir -p "$out"
    '';

  # Fake-boundary probes test gate: runs
  # tests/unit/test_nix_nrf_probes.py against a temporary fake
  # sysfs tree and a fake `openocd` executable first on PATH, with
  # sandboxed Python stdlib. Proves enumeration filtering, table
  # parsing, serial filtering, --find exit semantics, missing-OpenOCD
  # and timeout handling, and the exact read-only OpenOCD argument
  # vector — no hardware, no real /sys or USB, no network.
  probesTests =
    pkgs.runCommand "nix-nrf-probes-tests"
    {
      nativeBuildInputs = [pkgs.python3];
      probesScript = ../../../bin/commands/nix-nrf-probes;
      testFile = ../../../tests/unit/test_nix_nrf_probes.py;
    }
    ''
      cp "$probesScript" nix-nrf-probes
      chmod +x nix-nrf-probes
      cp "$testFile" test_nix_nrf_probes.py
      NIX_NRF_PROBES_SCRIPT="$PWD/nix-nrf-probes" python3 test_nix_nrf_probes.py
      echo "probes tests passed" >&2
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

  # XIAO doctor preflight parser gate: runs
  # tests/unit/test_preflight_xiao.py against the copied
  # tests/hardware/preflight_xiao.py, with sandboxed Python stdlib. Proves
  # the hardware harness's own consumer contract of `nix-nrf doctor --json`
  # (exactly one candidate with the requested serial, explicit CMSIS-DAP v2
  # bulk USB: type cmsis-dap, accessible, access_method usb, no fallback,
  # and an accessible USB node) plus exit-class handling for malformed
  # input and remediation forwarding — no hardware, no real /sys or /dev,
  # no doctor or OpenOCD invocation, no network. The parser is the same
  # file tests/hardware/run.sh pipes doctor output into; the physical proof
  # stays in the manual hardware workflow.
  preflightXiaoTests =
    pkgs.runCommand "nix-nrf-preflight-xiao-tests"
    {
      nativeBuildInputs = [pkgs.python3];
      preflightScript = ../../../tests/hardware/preflight_xiao.py;
      testFile = ../../../tests/unit/test_preflight_xiao.py;
    }
    ''
      cp "$preflightScript" preflight_xiao.py
      chmod +x preflight_xiao.py
      cp "$testFile" test_preflight_xiao.py
      NIX_NRF_PREFLIGHT_XIAO_SCRIPT="$PWD/preflight_xiao.py" python3 test_preflight_xiao.py
      echo "preflight-xiao tests passed" >&2
      mkdir -p "$out"
    '';

  # Fake-OpenOCD flash-recipe semantic regression gate: sources the REAL
  # tcl/nrf53_flash.tcl and tcl/nrf54l_flash.tcl under tclsh (pinned pkgs.tcl)
  # with fake OpenOCD commands that record command + args, then proves
  # command order, single-argument preservation (incl. paths with spaces),
  # conditionals, and UICR safety branches — no hardware, no real OpenOCD.
  # Proc semantics live here; the real-OpenOCD hosted-CI steps only gate
  # source/syntax compatibility. Recipe paths come from env vars set to the
  # copied recipe files; the script fails clearly when they are unset.
  flashRecipeTests =
    pkgs.runCommand "nix-nrf-flash-recipe-tests"
    {
      nativeBuildInputs = [pkgs.tcl];
      testFile = ../../../tests/tcl/test_flash_recipes.tcl;
      nrf53Recipe = ../../../tcl/nrf53_flash.tcl;
      nrf54lRecipe = ../../../tcl/nrf54l_flash.tcl;
    }
    ''
      NIX_NRF_NRF53_FLASH_TCL="$nrf53Recipe" \
      NIX_NRF_NRF54L_FLASH_TCL="$nrf54lRecipe" \
        tclsh "$testFile"
      echo "flash recipe tests passed" >&2
      mkdir -p "$out"
    '';

  # Udev-rule gate: builds the relocation package, verifies the destination
  # exists, proves the installed rule is byte-for-byte identical to the pinned
  # OpenOCD contrib file, and pins the package to exactly one payload file:
  # $out/lib/udev/rules.d/60-openocd.rules. No bin, service, hook, or second
  # rule can pass. Also proves the rule carries the generic `*CMSIS-DAP*`
  # match and the explicit `GROUP="plugdev"` contract (NixOS does not create
  # `plugdev`; consumer host policy must). Never builds a whole NixOS system.
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
      # Exactly one payload path (regular files AND symlinks count), and it
      # must be the single rule file. Directories are not payload.
      payload_count=$(find "$nrfUdevRules" -not -type d | wc -l)
      [ "$payload_count" -eq 1 ] || {
        echo "udev-rules check: expected exactly 1 payload file in $nrfUdevRules, got $payload_count" >&2
        find "$nrfUdevRules" | sort >&2
        exit 1
      }
      payload=$(find "$nrfUdevRules" -not -type d)
      [ "$payload" = "$installed" ] || {
        echo "udev-rules check: unexpected payload path $payload (expected exactly $installed)" >&2
        exit 1
      }
      grep -F 'ATTRS{product}=="*CMSIS-DAP*"' "$installed" >/dev/null || {
        echo "udev-rules check: generic *CMSIS-DAP* match missing from installed rule" >&2
        exit 1
      }
      grep -F 'GROUP="plugdev"' "$installed" >/dev/null || {
        echo "udev-rules check: GROUP=\"plugdev\" assignment missing from installed rule" >&2
        exit 1
      }
      echo "udev-rules check passed: one file ($installed) byte-identical to pinned OpenOCD contrib rule with *CMSIS-DAP* and GROUP=\"plugdev\" contract" >&2
      mkdir -p "$out"
    '';

  # Shell doctor udev-rules wiring gate: proves the shell-instantiated
  # `nix-nrf doctor` (from devShells.default, built through mkNrfShell's
  # internal udevRules closure wiring) reports the exact packaged udev
  # rule path in its remediation. Runs the real shell `nix-nrf doctor`
  # against a temporary fake sysfs/dev root with one blocked candidate —
  # no host USB, no network, no SDK. The gate prevents a shell-specific
  # doctor from losing the exact packaged-rule-path line (mkNrfShell must
  # keep passing the internal udevRules package through the closure).
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

  # Public NixOS module evaluation gate: evaluates two otherwise identical
  # pinned `lib.nixosSystem` configurations (no build, no VM) — one importing
  # the real `self.nixosModules.udevRules`, one using the direct
  # `services.udev.packages` form — and requires the resulting udev package
  # lists to be exactly equal by outPath. This proves the named module is a
  # convenience equivalent of the documented least-intrusive direct form. It
  # also asserts the nix-nrf-owned udev-rules derivation appears exactly once
  # and that the public `self.packages.${system}.udev-rules` output path
  # equals the internal one. Only evaluated booleans/count/store paths cross
  # the derivation boundary — never a full NixOS system. The total list
  # length is NOT asserted: NixOS contributes its own generated udev/hwdb
  # packages.
  nixosModuleCheck = let
    namedSystem = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        self.nixosModules.udevRules
        {system.stateVersion = "26.11";}
      ];
    };
    directSystem = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        {services.udev.packages = [self.packages.${system}.udev-rules];}
        {system.stateVersion = "26.11";}
      ];
    };
    namedOutPaths = map (p: p.outPath) namedSystem.config.services.udev.packages;
    directOutPaths = map (p: p.outPath) directSystem.config.services.udev.packages;
    listsEqual = namedOutPaths == directOutPaths;
    matchingUdevRules =
      builtins.filter (
        p: p.outPath == nrfUdevRules.outPath
      )
      namedSystem.config.services.udev.packages;
    matchingCount = builtins.length matchingUdevRules;
    publicUdevRules = self.packages.${system}.udev-rules;
  in
    pkgs.runCommand "nix-nrf-nixos-module-check"
    {
      inherit listsEqual matchingCount;
      expectedUdevRules = nrfUdevRules;
      inherit publicUdevRules;
    }
    ''
      [ "$listsEqual" = "1" ] || {
        echo "nixos-module check: named-module services.udev.packages outPaths differ from direct-configuration outPaths" >&2
        exit 1
      }
      [ "$matchingCount" -eq 1 ] || {
        echo "nixos-module check: expected exactly 1 matching udev-rules package in services.udev.packages, got $matchingCount" >&2
        exit 1
      }
      [ "$expectedUdevRules" = "$publicUdevRules" ] || {
        echo "nixos-module check: public udev-rules package ($publicUdevRules) differs from internal package ($expectedUdevRules)" >&2
        exit 1
      }
      echo "nixos-module check passed: named module and direct configuration contribute equivalent udev package lists with exactly one $expectedUdevRules" >&2
      mkdir -p "$out"
    '';
in {
  nix-nrf-help = nixNrfHelpCheck;
  doctor-tests = doctorTests;
  probes-tests = probesTests;
  flash-recipe-tests = flashRecipeTests;
  udev-rules = udevRulesCheck;
  doctor-udev-wiring = doctorUdevWiringCheck;
  nixos-module = nixosModuleCheck;
  preflight-xiao-tests = preflightXiaoTests;
}
