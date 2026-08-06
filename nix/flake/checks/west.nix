# west-backend regression gates: bootstrap/versions/metadata/quoting tests
# and the public west shell boundary gate. Comments moved verbatim with the
# implementations.
{
  pkgs,
  mkNrfShell,
  westBackendVersions,
  westBackendEntry,
  westZephyrSdk,
  westBootstrapBuilder,
  westVersionsCommandBuilder,
  openocd-master,
  nrfutil,
  nrfUdevRules,
}: let
  # Fake-boundary west bootstrap test gate: runs
  # tests/unit/test_nix_nrf_west_bootstrap.py against temporary fake
  # python/venv/west/pip boundaries with sandboxed Python stdlib.
  # Proves readiness, approval (--yes / NIX_NRF_BOOTSTRAP_YES, old
  # NIX_NRF_WEST_SETUP_YES ignored), command order, requirement order,
  # re-run behavior, incompatible-workspace rejection, failure
  # propagation, --check non-mutation, --print-sdk-path stdout, and
  # the public `nix-nrf bootstrap` program prefix — no network, no real
  # venv, no real west workspace. Also builds the packaged bootstrap
  # module and asserts it installs only $out/libexec/nix-nrf/bootstrap
  # (no standalone $out/bin/nix-nrf-west-* command), and runs the
  # shared fake-west-workspace fixture unit suite
  # (tests/unit/test_west_workspace_fixture.py) covering the
  # tests/fixtures/west-workspace.py safety contract: stdout/log mode
  # structure and executable behavior, plus filesystem-root, current-HOME,
  # existing-non-empty-directory (sentinel preserved), symlink-escape
  # (target preserved), and non-directory refusals via the public
  # subprocess CLI in temp roots.
  westBootstrapTests = let
    module = import ../../backends/west/bootstrap.nix {
      inherit pkgs;
      inherit (westBackendEntry) pythonPackage;
      metadata = westBackendEntry;
    };
  in
    pkgs.runCommand "nix-nrf-west-bootstrap-tests"
    {
      nativeBuildInputs = [pkgs.python3];
      inherit module;
      setupScript = ../../../bin/backends/west/nix-nrf-west-bootstrap;
      testFile = ../../../tests/unit/test_nix_nrf_west_bootstrap.py;
      fixture = ../../../tests/fixtures/west-workspace.py;
      fixtureTest = ../../../tests/unit/test_west_workspace_fixture.py;
    }
    ''
      cp "$setupScript" nix-nrf-west-bootstrap
      chmod +x nix-nrf-west-bootstrap
      cp "$testFile" test_nix_nrf_west_bootstrap.py
      NIX_NRF_WEST_BOOTSTRAP_SCRIPT="$PWD/nix-nrf-west-bootstrap" python3 test_nix_nrf_west_bootstrap.py
      cp "$fixtureTest" test_west_workspace_fixture.py
      NIX_NRF_WEST_FIXTURE="$fixture" python3 test_west_workspace_fixture.py
      [ -x "$module/libexec/nix-nrf/bootstrap" ] || {
        echo "west bootstrap module: missing $module/libexec/nix-nrf/bootstrap" >&2
        exit 1
      }
      if [ -e "$module/bin" ]; then
        echo "west bootstrap module: standalone $module/bin must not be installed" >&2
        exit 1
      fi
      echo "west bootstrap tests passed" >&2
      mkdir -p "$out"
    '';

  # Fake-boundary west versions command gate: runs
  # tests/unit/test_nix_nrf_west_versions.py against the packaged west
  # `nix-nrf versions` command module with sandboxed Python stdlib.
  # Proves text (one supported release per line), --json (parseable
  # sorted string array), --help (exit 0), unknown-option/too-many exit
  # 2, and that the packaged command reports exactly the metadata
  # release — no nrfutil, no network.
  westVersionsTests =
    pkgs.runCommand "nix-nrf-west-versions-tests"
    {
      nativeBuildInputs = [pkgs.python3];
      versionsCommand = westVersionsCommandBuilder {
        inherit pkgs;
        versions = westBackendVersions;
      };
      testFile = ../../../tests/unit/test_nix_nrf_west_versions.py;
    }
    ''
      cp "$testFile" test_nix_nrf_west_versions.py
      NIX_NRF_WEST_VERSIONS_COMMAND="$versionsCommand/libexec/nix-nrf/versions" python3 test_nix_nrf_west_versions.py
      echo "west versions command tests passed" >&2
      mkdir -p "$out"
    '';

  # Cheap metadata schema gate: asserts every nix/backends/west
  # versions.nix entry has the required shape (ncsVersion matches its
  # key, testedWestVersion/python/pythonPackage/requirements strings,
  # zephyrSdk version/targets/assets with x86_64-linux URLs + fixed
  # hashes, sorted attr names so the versions command output is
  # deterministic). Pure Nix evaluation — fetches and builds nothing.
  westBackendMetadataCheck = let
    isString = x: builtins.isString x;
    isStringList = xs: builtins.isList xs && builtins.all isString xs;
    entryOk = key: e:
      e.ncsVersion
      == key
      && isString e.testedWestVersion
      && isString e.python
      && isString e.pythonPackage
      && isString e.zephyrSdk.version
      && isStringList e.zephyrSdk.targets
      && builtins.length e.zephyrSdk.targets > 0
      && (e.zephyrSdk.assets ? "x86_64-linux")
      && isString e.zephyrSdk.assets."x86_64-linux".minimal.url
      && isString e.zephyrSdk.assets."x86_64-linux".minimal.sha256
      && builtins.isList e.zephyrSdk.assets."x86_64-linux".toolchains
      && builtins.length e.zephyrSdk.assets."x86_64-linux".toolchains > 0
      && builtins.all (
        t: isString t.target && isString t.url && isString t.sha256
      )
      e.zephyrSdk.assets."x86_64-linux".toolchains
      && isStringList e.requirements
      && builtins.length e.requirements > 0
      && isStringList (e.pipConstraints or []);
    results = map (k: {
      key = k;
      ok = entryOk k westBackendVersions.${k};
    }) (builtins.attrNames westBackendVersions);
    sortedNamesOk =
      builtins.sort builtins.lessThan (builtins.attrNames westBackendVersions)
      == builtins.attrNames westBackendVersions;
    pass = builtins.all (r: r.ok) results && sortedNamesOk;
    detail = builtins.concatStringsSep "\n" (
      map (r: "  ${r.key}: ${
        if r.ok
        then "ok"
        else "INVALID"
      }")
      results
    );
  in
    pkgs.runCommand "west-backend-metadata-check"
    {
      inherit detail sortedNamesOk;
    }
    (
      if pass
      then ''
        echo "west-backend metadata check: all entries valid (sorted names: $sortedNamesOk)" >&2
        echo "$detail" >&2
        mkdir -p "$out"
      ''
      else ''
        echo "west-backend metadata check FAILED" >&2
        echo "$detail" >&2
        exit 1
      ''
    );

  # Quote-embedding regression for the public west backend shell:
  # metadata values may contain shell metacharacters, so the shell hook
  # and the scoped west wrapper must assign escaped values to variables
  # OUTSIDE double quotes and compose paths/messages from those
  # variables — never interpolate an escapeShellArg output directly
  # inside double quotes (which would embed literal quote characters
  # into the value, e.g. `$HOME/ncs/'v3.3.0'`).
  #
  # The gate instantiates the PUBLIC `mkNrfShell` with `backend =
  # "west"` (the same module the flake exports). The nasty instance
  # feeds a test-only versions attrset whose entry carries single
  # quotes + spaces in the NCS, SDK, and Python values; a test-only
  # constant SDK builder stands in for the real zephyr-sdk builder so
  # the nasty `zephyrSdk.version` is exercised through the public
  # factory without fetching or building a bogus SDK (the real builder
  # validates sdk_version against the metadata and would fail). The
  # clean instance uses the real versions.nix. Both source the shell
  # hook with a fake HOME and run the real scoped wrapper against a
  # fake-ready workspace, asserting every composed value contains no
  # quote artifact and the default workspace path stays
  # `$HOME/ncs/v3.3.0`.
  westBackendQuotingCheck = let
    nastyNcsVersion = "v3.3.0 with 'quote' and spaces";
    nastySdkVersion = "0.17.0'sdk";
    nastyPython = "3.12'py";
    nastyMetadata =
      westBackendEntry
      // {
        ncsVersion = nastyNcsVersion;
        python = nastyPython;
        zephyrSdk =
          westBackendEntry.zephyrSdk
          // {
            version = nastySdkVersion;
          };
      };
    # Test-only SDK builder: constant derivation, no network, no
    # SDK validation. Only the quoting gate uses it; production
    # construction always passes the real zephyr-sdk builder.
    fakeSdkBuilder = {
      pkgs,
      sdk,
    }:
      pkgs.runCommand "fake-zephyr-sdk" {} ''
        mkdir -p $out
        printf '%s' ${pkgs.lib.escapeShellArg sdk.version} > $out/sdk_version
      '';
    nastyModule = import ../../backends/default.nix {
      inherit
        pkgs
        openocd-master
        nrfutil
        westBootstrapBuilder
        westVersionsCommandBuilder
        ;
      udevRules = nrfUdevRules;
      westVersions = {
        "${nastyNcsVersion}" = nastyMetadata;
      };
      westZephyrSdkBuilder = fakeSdkBuilder;
    };
    nastyShell = nastyModule {
      backend = "west";
      ncsVersion = nastyNcsVersion;
      name = "west-quoting-nasty";
      autoBootstrap = false;
    };
    cleanShell = mkNrfShell {
      backend = "west";
      ncsVersion = "v3.3.0";
      name = "west-quoting-clean";
      autoBootstrap = false;
    };
  in
    pkgs.runCommand "west-backend-quoting-check"
    {
      nativeBuildInputs = [pkgs.python3];
      fixture = ../../../tests/fixtures/west-workspace.py;
      inherit (nastyShell) shellHook;
      nastyWest = nastyShell.passthru.westWrapper;
      cleanShellHook = cleanShell.shellHook;
      inherit
        nastyNcsVersion
        nastySdkVersion
        nastyPython
        ;
    }
    ''
      set -eu

      # ── Shell hook with quote-containing metadata ───────────────────
      # Exact matches catch the defect directly: without the variable
      # composition, `$_workspace` would be `$HOME/ncs/'v3.3.0 with
      # 'quote' and spaces'` (literal escape quotes embedded) and fail
      # both the equality and the missing-value assertions below.
      printf '%s\n' "$shellHook" > hook.sh
      mkdir -p home
      HOME="$PWD/home" bash -c '
      set -eu
      source "$1"
      [ "$_workspace" = "$HOME/ncs/$2" ] || { echo "FAIL: workspace mismatch (quote artifact?): $_workspace" >&2; exit 1; }
      [ "$_sdk_version" = "$3" ] || { echo "FAIL: sdk version mismatch: $_sdk_version" >&2; exit 1; }
      [ "$_python_version" = "$4" ] || { echo "FAIL: python version mismatch: $_python_version" >&2; exit 1; }
      [ -n "$_workspace" ] || { echo "FAIL: workspace variable empty" >&2; exit 1; }
      echo "shell hook quoting check OK: $_workspace" >&2
      ' bash hook.sh "$nastyNcsVersion" "$nastySdkVersion" "$nastyPython"

      # ── Shell hook with clean (default) metadata ────────────────────
      printf '%s\n' "$cleanShellHook" > clean-hook.sh
      HOME="$PWD/home" bash -c '
      set -eu
      source "$1"
      [ "$_workspace" = "$HOME/ncs/v3.3.0" ] || { echo "FAIL: default workspace mismatch: $_workspace" >&2; exit 1; }
      echo "clean shell hook check OK: $_workspace" >&2
      ' bash clean-hook.sh

      # ── Scoped west wrapper against a fake-ready workspace ──────────
      # The shared stdlib-only fixture (tests/fixtures/west-workspace.py)
      # creates the ready workspace structure (manifest, requirement roots,
      # fake venv python/pip/west); stdout mode matches the quoting gate's
      # fake boundaries.
      python3 "$fixture" --workspace "$PWD/home/ncs/$nastyNcsVersion" --mode stdout

      HOME="$PWD/home" "$nastyWest/bin/west" list --format=json > wrapper.out
      grep -F "FAKE_WEST argv=list --format=json ZEPHYR_BASE=$PWD/home/ncs/$nastyNcsVersion/zephyr" wrapper.out >/dev/null || {
      echo "FAIL: wrapper did not reach the venv west with the correct ZEPHYR_BASE" >&2
      cat wrapper.out >&2
      exit 1
      }
      echo "west wrapper quoting check OK" >&2
      mkdir -p "$out"
    '';

  # Public west shell boundary gate: instantiates `mkNrfShell { backend
  # = "west"; ncsVersion = "v3.3.0"; }` (the public API) with caller
  # name/packages/extraShellHook/withMultilib/inputsFrom and runs its
  # public `nix-nrf` and scoped `west` against a fake-ready workspace
  # plus fake venv executables — no network, no west update/pip/workspace
  # downloads (the fake boundaries absorb the bootstrap's mutating
  # steps). Proves: the shell hook is read-only and free of quote
  # artifacts; `nix-nrf versions` reports v3.3.0 (text + parseable
  # JSON); `nix-nrf bootstrap --check --print-sdk-path` returns the
  # exact workspace; `nix-nrf doctor` checks the west bootstrap and
  # reports the ready SDK (fake sysfs/dev roots, no hardware); the
  # scoped `west` reaches the exact venv west with the expected
  # exports; `autoBootstrap = false` refuses a missing workspace
  # without mutation; nrfutil and nix-nrf-west-setup are absent; and
  # caller packages/inputsFrom/extraShellHook/name/multilib settings
  # propagate.
  westShellBoundaryCheck = let
    boundaryFixture = pkgs.mkShell {
      packages = [pkgs.ripgrep];
    };
    westShell = mkNrfShell {
      backend = "west";
      ncsVersion = "v3.3.0";
      name = "west-boundary-check";
      packages = [pkgs.hello];
      extraShellHook = "export NIX_NRF_BOUNDARY_MARKER=set";
      withMultilib = false;
      inputsFrom = [boundaryFixture];
    };
    westNoAutoShell = mkNrfShell {
      backend = "west";
      ncsVersion = "v3.3.0";
      name = "west-boundary-no-auto";
      autoBootstrap = false;
    };
    # The shell's packages land in nativeBuildInputs; membership checks
    # are pure Nix (no build), while the realized command modules below
    # are the ones the boundary script actually executes.
    shellPackages = westShell.nativeBuildInputs or [];
    noAutoPackages = westNoAutoShell.nativeBuildInputs or [];
    nixNrfPkg = builtins.head (builtins.filter (p: p.name == "nix-nrf") shellPackages);
    westPkg = builtins.head (builtins.filter (p: p.name == "west") shellPackages);
    noAutoWest = westNoAutoShell.passthru.westWrapper;
    multilibOutPath = pkgs.gccMultiStdenv.cc.outPath;
    boundaryHasMultilib = builtins.any (p: p ? outPath && p.outPath == multilibOutPath) shellPackages;
    noAutoHasMultilib = builtins.any (p: p ? outPath && p.outPath == multilibOutPath) noAutoPackages;
    hasHello = builtins.any (p: p ? pname && p.pname == "hello") shellPackages;
    hasRipgrep = builtins.any (p: p ? pname && p.pname == "ripgrep") shellPackages;
    noNrfutil = builtins.all (p: !(p ? pname) || p.pname != "nrfutil") shellPackages;
    noWestSetup = builtins.all (p: !(p ? pname) || p.pname != "nix-nrf-west-setup") shellPackages;
    # Exact west command modules the shell's backend-aware nix-nrf
    # dispatches to (identical construction args as mkNrfShell uses, so
    # identical store paths); realized so the dispatcher can exec them.
    westBootstrapModule = westBootstrapBuilder {
      inherit pkgs;
      inherit (westBackendEntry) pythonPackage;
      metadata = westBackendEntry;
    };
    westVersionsModule = westVersionsCommandBuilder {
      inherit pkgs;
      versions = westBackendVersions;
    };
    westDoctorModule = import ../../commands/doctor.nix {
      inherit pkgs;
      udevRules = nrfUdevRules;
      ncsVersion = "v3.3.0";
      bootstrapCommand = "${westBootstrapModule}/libexec/nix-nrf/bootstrap";
      environmentLabel = "west workspace/Zephyr SDK";
    };
  in
    pkgs.runCommand "west-shell-boundary-check"
    {
      nativeBuildInputs = [pkgs.python3];
      fixture = ../../../tests/fixtures/west-workspace.py;
      inherit (westShell) shellHook;
      inherit
        nixNrfPkg
        westPkg
        noAutoWest
        westBootstrapModule
        westVersionsModule
        westDoctorModule
        boundaryHasMultilib
        noAutoHasMultilib
        hasHello
        hasRipgrep
        noNrfutil
        noWestSetup
        ;
      expectedSdk = westZephyrSdk;
    }
    ''
      set -eu

      export HOME="$PWD/home"
      mkdir -p "$HOME"
      # The shared stdlib-only fixture (tests/fixtures/west-workspace.py)
      # creates the ready workspace structure (manifest, requirement roots,
      # fake venv python/pip/west); log mode matches the boundary gate's
      # venv.log boundaries.
      ws="$HOME/ncs/v3.3.0"
      python3 "$fixture" --workspace "$ws" --mode log

      # ── Shell hook: read-only, exact workspace, caller options ──────
      printf '%s\n' "$shellHook" > hook.sh
      hook_out="$(HOME="$HOME" bash -c '
      set -eu
      source "$1"
      [ "$_workspace" = "$HOME/ncs/v3.3.0" ] || { echo "FAIL: workspace quote artifact: $_workspace" >&2; exit 1; }
      [ "$ZEPHYR_BASE" = "$HOME/ncs/v3.3.0/zephyr" ] || { echo "FAIL: ZEPHYR_BASE not derived: $ZEPHYR_BASE" >&2; exit 1; }
      [ "$NIX_NRF_BOUNDARY_MARKER" = "set" ] || { echo "FAIL: extraShellHook did not propagate" >&2; exit 1; }
      echo "shell hook boundary check OK" >&2
      ' bash hook.sh 2>&1)"
      printf '%s\n' "$hook_out" | grep -F "west-boundary-check shell (backend west" >/dev/null || {
      echo "FAIL: shell banner missing the caller name" >&2
      printf '%s\n' "$hook_out" >&2
      exit 1
      }
      # The hook only ever ran the read-only --check path: no pip/west
      # mutation lines, only the venv import probe.
      if grep -E ' (init|update|install) ' "$HOME/venv.log" >/dev/null 2>&1; then
      echo "FAIL: shell hook ran a mutating command" >&2
      cat "$HOME/venv.log" >&2
      exit 1
      fi

      # ── nix-nrf versions: text, JSON, help ──────────────────────────
      "$nixNrfPkg/bin/nix-nrf" versions > versions.txt
      grep -qx "v3.3.0" versions.txt || { echo "FAIL: versions text missing v3.3.0" >&2; cat versions.txt >&2; exit 1; }
      "$nixNrfPkg/bin/nix-nrf" versions --json > versions.json
      python3 - <<'PYEOF'
      import json
      data = json.load(open("versions.json"))
      assert data == ["v3.3.0"], data
      PYEOF
      "$nixNrfPkg/bin/nix-nrf" versions --help >/dev/null

      # ── nix-nrf --help: backend-aware west descriptions ─────────────
      "$nixNrfPkg/bin/nix-nrf" --help > main-help.txt
      grep -F "versions   List NCS releases supported by the west backend metadata" main-help.txt >/dev/null || { echo "FAIL: west versions help wording missing" >&2; cat main-help.txt >&2; exit 1; }
      grep -F "bootstrap  Ensure the west workspace and version-local venv exist" main-help.txt >/dev/null || { echo "FAIL: west bootstrap help wording missing" >&2; cat main-help.txt >&2; exit 1; }
      grep -F "doctor     Diagnose west workspace/Zephyr SDK and probe access (read-only)" main-help.txt >/dev/null || { echo "FAIL: west doctor help wording missing" >&2; cat main-help.txt >&2; exit 1; }

      # ── nix-nrf bootstrap --check --print-sdk-path: exact workspace ─
      "$nixNrfPkg/bin/nix-nrf" bootstrap --check --quiet --print-sdk-path > sdk-path.txt
      [ "$(cat sdk-path.txt)" = "$HOME/ncs/v3.3.0" ] || {
      echo "FAIL: unexpected SDK path: $(cat sdk-path.txt)" >&2
      exit 1
      }

      # ── nix-nrf doctor: read-only west bootstrap check, no hardware ─
      mkdir -p sysfs dev
      NIX_NRF_DOCTOR_SYSFS_ROOT="$PWD/sysfs" \
      NIX_NRF_DOCTOR_DEV_ROOT="$PWD/dev" \
      "$nixNrfPkg/bin/nix-nrf" doctor --json > doctor.json || true
      python3 - <<'PYEOF'
      import json
      import os

      data = json.load(open("doctor.json"))
      sdk = data["sdk"]
      assert sdk["status"] == "pass", sdk
      assert sdk["path"] == os.environ["HOME"] + "/ncs/v3.3.0", sdk
      assert sdk["message"].startswith("NCS"), sdk
      assert data["hardware"]["status"] == "fail", data["hardware"]
      PYEOF

      # ── Scoped west: exact venv west, expected exports ──────────────
      # No approval needed: the ready workspace short-circuits the
      # bootstrap (nrfutil parity), exactly the regression the real
      # clean-room run exposed.
      "$westPkg/bin/west" list --format=json > wrapper.out
      grep -F "argv=list --format=json ZEPHYR_BASE=$HOME/ncs/v3.3.0/zephyr ZEPHYR_TOOLCHAIN_VARIANT=zephyr ZEPHYR_SDK_INSTALL_DIR=$expectedSdk PATH=" "$HOME/venv.log" >/dev/null || {
      echo "FAIL: scoped west did not reach the venv west with the expected environment" >&2
      cat "$HOME/venv.log" >&2
      exit 1
      }
      line="$(grep -F "argv=list --format=json" "$HOME/venv.log" | tail -1)"
      path_part="''${line##*PATH=}"
      first="''${path_part%%:*}"
      case "$first" in
      *openocd/bin) ;;
      *)
      echo "FAIL: project OpenOCD not first on west PATH: $first" >&2
      exit 1
      ;;
      esac
      case ":''${path_part}:" in
      *":$HOME/ncs/v3.3.0/.venv/bin:"*) ;;
      *)
      echo "FAIL: version-local venv not on west PATH: $path_part" >&2
      exit 1
      ;;
      esac
      echo "scoped west boundary check OK" >&2

      # ── autoBootstrap = false: missing state refuses, no mutation ──
      empty_home="$PWD/home-empty"
      mkdir -p "$empty_home"
      HOME="$empty_home" "$noAutoWest/bin/west" list > no-auto.out 2> no-auto.err || true
      grep -F "automatic bootstrap is disabled (autoBootstrap = false)" no-auto.err >/dev/null || {
      echo "FAIL: no-auto wrapper did not report disabled bootstrap" >&2
      cat no-auto.err >&2
      exit 1
      }
      grep -F "Run: nix-nrf bootstrap" no-auto.err >/dev/null || {
      echo "FAIL: no-auto wrapper missing remediation" >&2
      cat no-auto.err >&2
      exit 1
      }
      [ ! -e "$empty_home/ncs" ] || { echo "FAIL: no-auto bootstrap mutated state" >&2; exit 1; }

      # ── Absence + propagation gates (Nix-side) ──────────────────────
      [ -z "$boundaryHasMultilib" ] || { echo "FAIL: withMultilib = false still added multilib gcc" >&2; exit 1; }
      [ "$noAutoHasMultilib" = "1" ] || { echo "FAIL: default withMultilib did not add multilib gcc" >&2; exit 1; }
      [ "$hasHello" = "1" ] || { echo "FAIL: caller packages did not propagate" >&2; exit 1; }
      [ "$hasRipgrep" = "1" ] || { echo "FAIL: inputsFrom did not propagate" >&2; exit 1; }
      [ "$noNrfutil" = "1" ] || { echo "FAIL: nrfutil found in west shell packages" >&2; exit 1; }
      [ "$noWestSetup" = "1" ] || { echo "FAIL: nix-nrf-west-setup found in west shell packages" >&2; exit 1; }

      # ── Runtime absence on the composed shell PATH ───────────────────
      saved_path="$PATH"
      PATH="$nixNrfPkg/bin:$westPkg/bin"
      if command -v nrfutil >/dev/null 2>&1; then
      echo "FAIL: nrfutil on the west shell PATH" >&2
      exit 1
      fi
      if command -v nix-nrf-west-setup >/dev/null 2>&1; then
      echo "FAIL: nix-nrf-west-setup on the west shell PATH" >&2
      exit 1
      fi
      command -v west >/dev/null || { echo "FAIL: scoped west missing from shell PATH" >&2; exit 1; }
      PATH="$saved_path"

      echo "west shell boundary check passed" >&2
      mkdir -p "$out"
    '';
in {
  west-bootstrap-tests = westBootstrapTests;
  west-versions-tests = westVersionsTests;
  west-backend-metadata = westBackendMetadataCheck;
  west-backend-quoting = westBackendQuotingCheck;
  west-shell-boundary = westShellBoundaryCheck;
}
