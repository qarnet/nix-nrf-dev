# nrfutil-backend regression gates: fake-boundary bootstrap lifecycle tests,
# the bootstrap wrapper quoting round-trip, the public nrfutil shell boundary
# gate, the deterministic `nix-nrf versions` delegation boundary (fake
# nrfutilPackage + real CLI), and the real packaged nrfutil forced-offline
# sdk-manager search gate.
{
  pkgs,
  nrfutil,
  mkNrfShell,
}: let
  # Fake-boundary bootstrap test gate: runs
  # tests/unit/test_nix_nrf_bootstrap.py against a temporary fake
  # nrfutil executable/state directory with sandboxed Python stdlib.
  # Covers every lifecycle branch: ready selection, --check, approval,
  # install matrix, exact-bundle behavior, malformed state, failed and
  # incomplete installs, missing version. It uses no network or real SDK,
  # and no real nrfutil state.
  bootstrapTests =
    pkgs.runCommand "nix-nrf-bootstrap-tests"
    {
      nativeBuildInputs = [pkgs.python3];
      bootstrapScript = ../../../bin/backends/nrfutil/nix-nrf-bootstrap;
      testFile = ../../../tests/unit/test_nix_nrf_bootstrap.py;
    }
    ''
      cp "$bootstrapScript" nix-nrf-bootstrap
      chmod +x nix-nrf-bootstrap
      cp "$testFile" test_nix_nrf_bootstrap.py
      NIX_NRF_BOOTSTRAP_SCRIPT="$PWD/nix-nrf-bootstrap" python3 test_nix_nrf_bootstrap.py
      echo "bootstrap tests passed" >&2
      mkdir -p "$out"
    '';

  # Shell-quoting regression for the internal bootstrap module:
  # instantiate and build nix/backends/nrfutil/bootstrap.nix with caller
  # selector values containing spaces and single/double quotes,
  # proving wrapProgram generation succeeds without shell injection
  # or syntax break, then round-trip the generated wrapper's exports
  # to check the exact values and selected nrfutil store
  # path survive.
  bootstrapQuotingCheck = let
    nastyNcsVersion = "v3.3.0 with space 'and quote'";
    nastyBundleId = "bundle \"with\" 'quotes' and spaces";
    module = import ../../backends/nrfutil/bootstrap.nix {
      inherit pkgs;
      nrfutilPackage = nrfutil;
      ncsVersion = nastyNcsVersion;
      toolchainBundleId = nastyBundleId;
    };
  in
    pkgs.runCommand "nix-nrf-bootstrap-quoting-check"
    {
      inherit module;
      expectedNcsVersion = nastyNcsVersion;
      expectedBundleId = nastyBundleId;
      expectedNrfutil = "${nrfutil}/bin/nrfutil";
    }
    ''
        wrapper="$module/libexec/nix-nrf/bootstrap"
        eval "$(grep -E '^export NIX_NRF_(NRFUTIL|NCS_VERSION|TOOLCHAIN_BUNDLE_ID)=' "$wrapper")"
        [ "$NIX_NRF_NCS_VERSION" = "$expectedNcsVersion" ] || {
          echo "NCS_VERSION mismatch: '$NIX_NRF_NCS_VERSION' != '$expectedNcsVersion'" >&2
          exit 1
        }
        [ "$NIX_NRF_TOOLCHAIN_BUNDLE_ID" = "$expectedBundleId" ] || {
          echo "TOOLCHAIN_BUNDLE_ID mismatch: '$NIX_NRF_TOOLCHAIN_BUNDLE_ID' != '$expectedBundleId'" >&2
          exit 1
        }
        [ "$NIX_NRF_NRFUTIL" = "$expectedNrfutil" ] || {
          echo "NRFUTIL mismatch: '$NIX_NRF_NRFUTIL' != '$expectedNrfutil'" >&2
          exit 1
        }
      "$wrapper" --help >/dev/null
      echo "bootstrap quoting check passed" >&2
      mkdir -p "$out"
    '';

  # ── Fake boundary derivations (test-only; never part of the shell API) ──
  # Test-only fake nrfutil: a Python stdlib sdk-manager stand-in driven
  # entirely by environment variables and state files under the check build
  # directory. It logs every argv as one JSON line to commands.log, records
  # mutating install argv to installs.log, emulates the sdk-ready /
  # toolchain-ready state files, counts toolchain env calls in env-count
  # (for the on-demand env-failure scenario), and emits a shell-safe
  # toolchain env script that prepends a fake real-west bin dir and sets the
  # FAKE_TOOLCHAIN_ENV / PYTHONHOME / GIT_EXEC_PATH markers. Unexpected argv
  # clears stderr and exits nonzero.
  fakeNrfutil = pkgs.writeTextFile {
    name = "fake-nrfutil";
    destination = "/bin/nrfutil";
    executable = true;
    text = ''
      #!${pkgs.python3}/bin/python3
      # SPDX-License-Identifier: MIT
      #
      # Test-only sdk-manager stand-in for the nrfutil shell boundary gate
      # (nix/flake/checks/nrfutil.nix). See the check's fake-boundary design
      # comment above for the full contract.
      import json
      import os
      import sys
      from pathlib import Path

      STATE = os.environ.get("FAKE_NRFUTIL_STATE", "")
      SDK = os.environ.get("FAKE_NRFUTIL_SDK_PATH", "")
      WEST_BIN = os.environ.get("FAKE_NRFUTIL_REAL_WEST_BIN", "")
      FAIL_ENV_CALL = os.environ.get("FAKE_NRFUTIL_FAIL_ENV_CALL", "")
      NCS_VERSION = os.environ.get("NIX_NRF_NCS_VERSION", "v3.3.0")


      def state_path(name):
          return os.path.join(STATE, name) if STATE else ""


      def log_command(argv):
          if not STATE:
              return
          Path(STATE).mkdir(parents=True, exist_ok=True)
          with open(state_path("commands.log"), "a") as fh:
              fh.write(json.dumps(argv) + "\n")


      def log_install(argv):
          if not STATE:
              return
          Path(STATE).mkdir(parents=True, exist_ok=True)
          with open(state_path("installs.log"), "a") as fh:
              fh.write(json.dumps(argv) + "\n")


      def env_call_count():
          try:
              with open(state_path("env-count")) as fh:
                  return int(fh.read().strip() or "0")
          except OSError:
              return 0


      def set_env_call_count(n):
          with open(state_path("env-count"), "w") as fh:
              fh.write(str(n) + "\n")


      def sdk_ready():
          return bool(STATE) and os.path.exists(state_path("sdk-ready"))


      def toolchain_ready():
          return bool(STATE) and os.path.exists(state_path("toolchain-ready"))


      def make_sdk():
          if SDK:
              (Path(SDK) / "zephyr").mkdir(parents=True, exist_ok=True)


      def touch(name):
          Path(state_path(name)).parent.mkdir(parents=True, exist_ok=True)
          open(state_path(name), "w").close()


      def unexpected(argv):
          print("fake nrfutil: unexpected argv: " + json.dumps(argv), file=sys.stderr)
          return 1


      def do_list():
          # Emit the installed-version JSON only when sdk-ready exists;
          # otherwise empty stdout, matching a fresh sdk-manager state. The
          # reported version always comes from NIX_NRF_NCS_VERSION (the
          # shell's exported wrapper environment), never from argv.
          if sdk_ready() and SDK:
              payload = {
                  "versions": [
                      {
                          "version": NCS_VERSION,
                          "sdkStatus": "installed",
                          "dirNames": [SDK],
                      }
                  ]
              }
              print(json.dumps(payload))
          return 0


      def do_config():
          # Valid default install root derived from the SDK path parent.
          install_dir = os.path.dirname(SDK) if SDK else None
          print(json.dumps({"default": {"install_dir": install_dir}}))
          return 0


      def do_env():
          n = env_call_count() + 1
          set_env_call_count(n)
          if FAIL_ENV_CALL and n == int(FAIL_ENV_CALL):
              print(
                  "fake nrfutil: toolchain env call %d failed on demand" % n,
                  file=sys.stderr,
              )
              return 1
          if not toolchain_ready():
              print("fake nrfutil: selected toolchain not ready", file=sys.stderr)
              return 1
          # Shell-safe exports: prepend the fake real-west bin dir and set the
          # markers the boundary asserts on the real-west side.
          print('export PATH="%s:$PATH"' % WEST_BIN)
          print("export FAKE_TOOLCHAIN_ENV=1")
          print("export PYTHONHOME=fake-toolchain-pythonhome")
          print("export GIT_EXEC_PATH=fake-toolchain-git")
          return 0


      def main():
          argv = sys.argv[1:]
          if not argv or argv[0] != "sdk-manager":
              return unexpected(argv)
          log_command(argv)
          rest = argv[1:]
          cmd = rest[0]
          if cmd == "list" and rest[1:] == ["--json", "--skip-overhead"]:
              return do_list()
          if cmd == "config" and rest[1:] == ["show", "--json", "--skip-overhead"]:
              return do_config()
          if (
              cmd == "toolchain"
              and rest[1:2] == ["env"]
              and rest[-2:] == ["--as-script", "sh"]
          ):
              return do_env()
          if cmd == "install" and len(rest) == 2:
              # Combined SDK + newest compatible toolchain install.
              log_install(argv)
              make_sdk()
              touch("sdk-ready")
              touch("toolchain-ready")
              return 0
          if cmd == "sdk" and rest[1:2] == ["install"] and len(rest) == 3:
              log_install(argv)
              make_sdk()
              touch("sdk-ready")
              return 0
          if cmd == "toolchain" and rest[1:2] == ["install"] and len(rest) == 4:
              log_install(argv)
              touch("toolchain-ready")
              return 0
          return unexpected(argv)


      if __name__ == "__main__":
          sys.exit(main())
    '';
  };

  # Test-only fake real west logs one JSON line per invocation. It records exact
  # argv plus the toolchain-scoped ZEPHYR_BASE / FAKE_TOOLCHAIN_ENV /
  # PYTHONHOME / GIT_EXEC_PATH / PATH under $FAKE_NRFUTIL_STATE/west.log,
  # then exits 0. A sh launcher is required because this binary runs INSIDE
  # the scoped toolchain env, where PYTHONHOME carries the fake marker value
  # that breaks the Nix python3 interpreter (encodings import failure); the
  # JSON-encoding python therefore runs with PYTHONHOME/PYTHONPATH cleared
  # while the captured values still flow through its argv.
  fakeWest = pkgs.writeTextFile {
    name = "fake-real-west";
    destination = "/bin/west";
    executable = true;
    text = ''
      #!/bin/sh
      PYTHONHOME= PYTHONPATH= ${pkgs.python3}/bin/python3 - \
        "$ZEPHYR_BASE" "$FAKE_TOOLCHAIN_ENV" "$PYTHONHOME" "$GIT_EXEC_PATH" "$PATH" "$@" <<'PYEOF'
      import json
      import os
      import sys

      argv = sys.argv[1:]
      entry = {
          "argv": argv[5:],
          "env": dict(
              zip(
                  ["ZEPHYR_BASE", "FAKE_TOOLCHAIN_ENV", "PYTHONHOME", "GIT_EXEC_PATH", "PATH"],
                  argv[:5],
              )
          ),
      }
      state = os.environ.get("FAKE_NRFUTIL_STATE", "")
      if state:
          os.makedirs(state, exist_ok=True)
          with open(os.path.join(state, "west.log"), "a") as fh:
              fh.write(json.dumps(entry) + "\n")
      sys.exit(0)
      PYEOF
    '';
  };

  # Public nrfutil shell boundary gate: instantiates the PUBLIC `mkNrfShell`
  # (`backend = "nrfutil"`) with caller name/packages/inputsFrom/
  # extraShellHook/withMultilib and a test-only fake `nrfutilPackage`, then
  # runs the real generated shell hook and the real scoped `west` wrapper as
  # subprocess boundaries against fake sdk-manager state and a fake real
  # west. No network, real Nordic downloads, or real sdk-manager state,
  # no mutable developer HOME. Proves: the shell hook is read-only (list +
  # toolchain-env probes only), derives the exact ZEPHYR_BASE, never evals
  # the toolchain script into the parent shell, runs the extra hook marker,
  # and propagates caller packages/inputsFrom; the scoped wrapper reaches the
  # fake real west with the exact SDK-derived ZEPHYR_BASE and the scoped
  # toolchain markers, with the project OpenOCD first on PATH; lazy bootstrap
  # from an empty state runs the combined fake `install` under approval and
  # creates the SDK/readiness markers; `autoBootstrap = false` refuses a
  # missing state without mutation; a failing toolchain env load and a
  # missing real west keep the existing wrapper errors and exit nonzero; and
  # exact-bundle selectors (values with spaces and both quote kinds) survive
  # as single argv elements, with no quote artifacts or shell injection.
  nrfutilShellBoundaryCheck = let
    boundaryFixture = pkgs.mkShell {
      packages = [pkgs.ripgrep];
    };
    nastyNcsVersion = "v3.3.0 with 'quotes' and \"spaces\"";
    nastyBundleId = "bundle \"with\" 'quotes' and spaces";
    readyShell = mkNrfShell {
      backend = "nrfutil";
      ncsVersion = "v3.3.0";
      name = "nrfutil-boundary-ready";
      packages = [pkgs.hello];
      extraShellHook = "export NIX_NRF_BOUNDARY_MARKER=set";
      withMultilib = false;
      inputsFrom = [boundaryFixture];
      nrfutilPackage = fakeNrfutil;
    };
    noAutoShell = mkNrfShell {
      backend = "nrfutil";
      ncsVersion = "v3.3.0";
      name = "nrfutil-boundary-no-auto";
      autoBootstrap = false;
      withMultilib = false;
      nrfutilPackage = fakeNrfutil;
    };
    bundleShell = mkNrfShell {
      backend = "nrfutil";
      ncsVersion = nastyNcsVersion;
      toolchainBundleId = nastyBundleId;
      name = "nrfutil-boundary-bundle";
      withMultilib = false;
      nrfutilPackage = fakeNrfutil;
    };
    # The shell's packages land in nativeBuildInputs; membership checks are
    # pure Nix (no build), while the realized command modules below are the
    # ones the boundary script actually executes.
    shellPackages = readyShell.nativeBuildInputs or [];
    noAutoPackages = noAutoShell.nativeBuildInputs or [];
    bundlePackages = bundleShell.nativeBuildInputs or [];
    nixNrfPkg = builtins.head (builtins.filter (p: p.name == "nix-nrf") shellPackages);
    westPkg = builtins.head (builtins.filter (p: p.name == "west") shellPackages);
    noAutoWest = builtins.head (builtins.filter (p: p.name == "west") noAutoPackages);
    bundleWest = builtins.head (builtins.filter (p: p.name == "west") bundlePackages);
    multilibOutPath = pkgs.gccMultiStdenv.cc.outPath;
    hasOut = p: p ? outPath;
    hasHello = builtins.any (p: p ? pname && p.pname == "hello") shellPackages;
    hasRipgrep = builtins.any (p: p ? pname && p.pname == "ripgrep") shellPackages;
    boundaryHasMultilib = builtins.any (p: hasOut p && p.outPath == multilibOutPath) shellPackages;
    noAutoHasMultilib = builtins.any (p: hasOut p && p.outPath == multilibOutPath) noAutoPackages;
    bundleHasMultilib = builtins.any (p: hasOut p && p.outPath == multilibOutPath) bundlePackages;
    hasFakeNrfutil = ps: builtins.any (p: hasOut p && p.outPath == fakeNrfutil.outPath) ps;
    noDefaultNrfutil = ps: builtins.all (p: !(hasOut p) || p.outPath != nrfutil.outPath) ps;
    readyHasFakeNrfutil = hasFakeNrfutil shellPackages;
    noAutoHasFakeNrfutil = hasFakeNrfutil noAutoPackages;
    bundleHasFakeNrfutil = hasFakeNrfutil bundlePackages;
    readyNoDefaultNrfutil = noDefaultNrfutil shellPackages;
    noAutoNoDefaultNrfutil = noDefaultNrfutil noAutoPackages;
    bundleNoDefaultNrfutil = noDefaultNrfutil bundlePackages;
    # Exact bootstrap command modules the shell's backend-aware nix-nrf
    # dispatches to (identical construction args as mkNrfShell uses, so
    # identical store paths); realized so the dispatcher and the scoped
    # wrapper can exec them against the fake nrfutil.
    readyBootstrapModule = import ../../backends/nrfutil/bootstrap.nix {
      inherit pkgs;
      nrfutilPackage = fakeNrfutil;
      ncsVersion = "v3.3.0";
    };
    bundleBootstrapModule = import ../../backends/nrfutil/bootstrap.nix {
      inherit pkgs;
      nrfutilPackage = fakeNrfutil;
      ncsVersion = nastyNcsVersion;
      toolchainBundleId = nastyBundleId;
    };
  in
    pkgs.runCommand "nrfutil-shell-boundary-check"
    {
      nativeBuildInputs = [pkgs.python3];
      inherit (readyShell) shellHook;
      inherit
        nixNrfPkg
        westPkg
        noAutoWest
        bundleWest
        readyBootstrapModule
        bundleBootstrapModule
        fakeNrfutil
        nastyNcsVersion
        nastyBundleId
        ;
      fakeRealWestBin = "${fakeWest}/bin";
      inherit
        hasHello
        hasRipgrep
        boundaryHasMultilib
        noAutoHasMultilib
        bundleHasMultilib
        readyHasFakeNrfutil
        noAutoHasFakeNrfutil
        bundleHasFakeNrfutil
        readyNoDefaultNrfutil
        noAutoNoDefaultNrfutil
        bundleNoDefaultNrfutil
        ;
    }
    ''
      set -eu

      export HOME="$PWD/home"
      mkdir -p "$HOME"

      # Isolated fake boundary locations, per scenario. reset_env exports the
      # fake nrfutil runtime contract for the next scenario; every scenario
      # keeps its state and SDK root under the check build directory.
      reset_env() {
        export FAKE_NRFUTIL_STATE="$1"
        export FAKE_NRFUTIL_SDK_PATH="$2"
        export FAKE_NRFUTIL_REAL_WEST_BIN="$fakeRealWestBin"
        unset FAKE_NRFUTIL_FAIL_ENV_CALL 2>/dev/null || true
        unset NIX_NRF_BOOTSTRAP_YES 2>/dev/null || true
        unset ZEPHYR_BASE 2>/dev/null || true
      }

      ready_state="$PWD/state-ready"
      ready_sdk="$PWD/sdk-ready"

      # ── Ready shell hook: read-only, exact ZEPHYR_BASE, caller options ──
      reset_env "$ready_state" "$ready_sdk"
      mkdir -p "$ready_sdk/zephyr" "$ready_state"
      touch "$ready_state/sdk-ready" "$ready_state/toolchain-ready"

      printf '%s\n' "$shellHook" > hook.sh
      hook_out="$(bash -c '
      set -eu
      source "$1"
      [ "$ZEPHYR_BASE" = "$2/zephyr" ] || { echo "FAIL: ZEPHYR_BASE mismatch: $ZEPHYR_BASE" >&2; exit 1; }
      [ "$NIX_NRF_BOUNDARY_MARKER" = "set" ] || { echo "FAIL: extraShellHook marker not set" >&2; exit 1; }
      [ -z "''${PYTHONHOME:-}" ] || { echo "FAIL: PYTHONHOME leaked into parent shell" >&2; exit 1; }
      [ -z "''${GIT_EXEC_PATH:-}" ] || { echo "FAIL: GIT_EXEC_PATH leaked into parent shell" >&2; exit 1; }
      [ -z "''${FAKE_TOOLCHAIN_ENV:-}" ] || { echo "FAIL: FAKE_TOOLCHAIN_ENV leaked into parent shell" >&2; exit 1; }
      echo "shell hook boundary check OK" >&2
      ' bash hook.sh "$ready_sdk" 2>&1)"
      printf '%s\n' "$hook_out" | grep -F "nrfutil-boundary-ready shell (backend nrfutil" >/dev/null || {
        echo "FAIL: shell banner missing caller name and backend" >&2
        printf '%s\n' "$hook_out" >&2
        exit 1
      }
      printf '%s\n' "$hook_out" | grep -F "ZEPHYR_BASE: $ready_sdk/zephyr" >/dev/null || {
        echo "FAIL: hook did not print the derived ZEPHYR_BASE" >&2
        printf '%s\n' "$hook_out" >&2
        exit 1
      }
      # The hook ran only the read-only probes: list + toolchain env, never
      # install, and installs.log stays absent.
      python3 - <<'PYEOF'
      import json
      import os

      state = os.environ["FAKE_NRFUTIL_STATE"]
      lines = [json.loads(l) for l in open(os.path.join(state, "commands.log"))]
      assert lines, "no nrfutil calls recorded"
      for a in lines:
          assert a[:2] == ["sdk-manager", "list"] or a[:3] == ["sdk-manager", "toolchain", "env"], a
      assert not os.path.exists(os.path.join(state, "installs.log")), "shell hook mutated state"
      PYEOF

      # ── Ready scoped west wrapper: exact argv/env, scoped markers, PATH ──
      "$westPkg/bin/west" list --format=json > ready-wrapper.out
      python3 - <<'PYEOF'
      import json
      import os

      state = os.environ["FAKE_NRFUTIL_STATE"]
      sdk = os.environ["FAKE_NRFUTIL_SDK_PATH"]
      lines = [json.loads(l) for l in open(os.path.join(state, "commands.log"))]
      env_calls = [a for a in lines if a[:3] == ["sdk-manager", "toolchain", "env"]]
      assert env_calls, "no toolchain env calls recorded"
      for a in env_calls:
          assert a[3:5] == ["--ncs-version", "v3.3.0"], a
          assert a[-2:] == ["--as-script", "sh"], a
      entry = [json.loads(l) for l in open(os.path.join(state, "west.log"))][-1]
      assert entry["argv"] == ["list", "--format=json"], entry
      env = entry["env"]
      assert env["ZEPHYR_BASE"] == sdk + "/zephyr", env
      assert env["FAKE_TOOLCHAIN_ENV"] == "1", env
      assert env["PYTHONHOME"] == "fake-toolchain-pythonhome", env
      assert env["GIT_EXEC_PATH"] == "fake-toolchain-git", env
      path_entries = env["PATH"].split(":")
      assert path_entries[0].endswith("openocd/bin"), path_entries[0]
      assert os.environ["FAKE_NRFUTIL_REAL_WEST_BIN"] in path_entries, path_entries
      assert not os.path.exists(os.path.join(state, "installs.log")), "ready wrapper mutated state"
      PYEOF

      # ── Lazy bootstrap: empty state, approval, combined install ─────────
      empty_state="$PWD/state-empty"
      empty_sdk="$PWD/sdk-empty"
      reset_env "$empty_state" "$empty_sdk"
      export NIX_NRF_BOOTSTRAP_YES=1
      "$westPkg/bin/west" list --format=json > lazy.out
      [ -e "$empty_state/sdk-ready" ] || { echo "FAIL: lazy bootstrap did not create sdk-ready" >&2; exit 1; }
      [ -e "$empty_state/toolchain-ready" ] || { echo "FAIL: lazy bootstrap did not create toolchain-ready" >&2; exit 1; }
      [ -d "$empty_sdk/zephyr" ] || { echo "FAIL: lazy bootstrap did not create the SDK source" >&2; exit 1; }
      python3 - <<'PYEOF'
      import json
      import os

      state = os.environ["FAKE_NRFUTIL_STATE"]
      installs = [json.loads(l) for l in open(os.path.join(state, "installs.log"))]
      assert installs == [["sdk-manager", "install", "v3.3.0"]], installs
      entry = [json.loads(l) for l in open(os.path.join(state, "west.log"))][-1]
      assert entry["argv"] == ["list", "--format=json"], entry
      assert entry["env"]["ZEPHYR_BASE"] == os.environ["FAKE_NRFUTIL_SDK_PATH"] + "/zephyr", entry["env"]
      PYEOF

      # ── autoBootstrap = false ───────────────────────────────────────────
      noauto_state="$PWD/state-noauto"
      noauto_sdk="$PWD/sdk-noauto"
      reset_env "$noauto_state" "$noauto_sdk"
      mkdir -p "$noauto_sdk/zephyr" "$noauto_state"
      touch "$noauto_state/sdk-ready" "$noauto_state/toolchain-ready"
      "$noAutoWest/bin/west" list > noauto-ready.out
      [ -e "$noauto_state/west.log" ] || { echo "FAIL: no-auto ready state did not reach fake west" >&2; exit 1; }

      missing_state="$PWD/state-noauto-missing"
      missing_sdk="$PWD/sdk-noauto-missing"
      reset_env "$missing_state" "$missing_sdk"
      set +e
      "$noAutoWest/bin/west" list > noauto-missing.out 2> noauto-missing.err
      rc=$?
      set -e
      [ "$rc" -ne 0 ] || { echo "FAIL: no-auto missing state exited 0" >&2; cat noauto-missing.err >&2; exit 1; }
      grep -F "automatic bootstrap is disabled (autoBootstrap = false)" noauto-missing.err >/dev/null || {
        echo "FAIL: no-auto wrapper did not report disabled bootstrap" >&2
        cat noauto-missing.err >&2
        exit 1
      }
      grep -F "Run: nix-nrf bootstrap" noauto-missing.err >/dev/null || {
        echo "FAIL: no-auto wrapper missing remediation" >&2
        cat noauto-missing.err >&2
        exit 1
      }
      [ ! -e "$missing_state/installs.log" ] || { echo "FAIL: no-auto missing state mutated" >&2; exit 1; }
      [ ! -e "$missing_state/sdk-ready" ] || { echo "FAIL: no-auto missing state created sdk-ready" >&2; exit 1; }
      [ ! -e "$missing_state/toolchain-ready" ] || { echo "FAIL: no-auto missing state created toolchain-ready" >&2; exit 1; }
      [ ! -e "$missing_sdk" ] || { echo "FAIL: no-auto missing state created the SDK" >&2; exit 1; }

      # ── Wrapper failures ────────────────────────────────────────────────
      # Toolchain env call 2 (the wrapper's own env load) fails on demand:
      # bootstrap readiness call 1 succeeds, the wrapper reports the exact
      # existing error with the selected-toolchain context and remediation,
      # and fake west is never invoked.
      failenv_state="$PWD/state-fail-env"
      failenv_sdk="$PWD/sdk-fail-env"
      reset_env "$failenv_state" "$failenv_sdk"
      mkdir -p "$failenv_sdk/zephyr" "$failenv_state"
      touch "$failenv_state/sdk-ready" "$failenv_state/toolchain-ready"
      export FAKE_NRFUTIL_FAIL_ENV_CALL=2
      set +e
      "$westPkg/bin/west" list > fail-env.out 2> fail-env.err
      rc=$?
      set -e
      [ "$rc" -ne 0 ] || { echo "FAIL: env-failure scenario exited 0" >&2; cat fail-env.err >&2; exit 1; }
      grep -F "sdk-manager toolchain env" fail-env.err >/dev/null || {
        echo "FAIL: env-failure error message missing" >&2
        cat fail-env.err >&2
        exit 1
      }
      grep -F "failed" fail-env.err >/dev/null || {
        echo "FAIL: env-failure 'failed' marker missing" >&2
        cat fail-env.err >&2
        exit 1
      }
      grep -F "Selected toolchain" fail-env.err >/dev/null || {
        echo "FAIL: env-failure selector context missing" >&2
        cat fail-env.err >&2
        exit 1
      }
      grep -F "Run: nix-nrf bootstrap" fail-env.err >/dev/null || {
        echo "FAIL: env-failure remediation missing" >&2
        cat fail-env.err >&2
        exit 1
      }
      [ ! -e "$failenv_state/west.log" ] || { echo "FAIL: fake west invoked despite env failure" >&2; exit 1; }

      # Ready toolchain env with an empty fake-real-west directory: the
      # wrapper reports the existing "real west not found" error and exits
      # nonzero.
      noreal_state="$PWD/state-no-real-west"
      noreal_sdk="$PWD/sdk-no-real-west"
      reset_env "$noreal_state" "$noreal_sdk"
      mkdir -p "$noreal_sdk/zephyr" "$noreal_state" "$PWD/empty-real-west"
      touch "$noreal_state/sdk-ready" "$noreal_state/toolchain-ready"
      export FAKE_NRFUTIL_REAL_WEST_BIN="$PWD/empty-real-west"
      set +e
      "$westPkg/bin/west" list > no-real-west.out 2> no-real-west.err
      rc=$?
      set -e
      [ "$rc" -ne 0 ] || { echo "FAIL: no-real-west scenario exited 0" >&2; cat no-real-west.err >&2; exit 1; }
      grep -F "real west not found in the NCS toolchain env" no-real-west.err >/dev/null || {
        echo "FAIL: real-west-not-found message missing" >&2
        cat no-real-west.err >&2
        exit 1
      }

      # ── Exact selector quoting: bundle shell from empty state ───────────
      # The exact-bundle shell lazily bootstraps with the exact sdk/toolchain
      # install actions, then completes its ready path to fake west. The
      # JSON argv log proves both the exact NCS version and the exact bundle
      # value (spaces + both quote kinds) survive as single argv elements.
      bundle_state="$PWD/state-bundle"
      bundle_sdk="$PWD/sdk-bundle"
      reset_env "$bundle_state" "$bundle_sdk"
      export NIX_NRF_BOOTSTRAP_YES=1
      "$bundleWest/bin/west" list --format=json > bundle.out
      python3 - <<'PYEOF'
      import json
      import os

      state = os.environ["FAKE_NRFUTIL_STATE"]
      sdk = os.environ["FAKE_NRFUTIL_SDK_PATH"]
      nasty_ncs = os.environ["nastyNcsVersion"]
      nasty_bundle = os.environ["nastyBundleId"]
      installs = [json.loads(l) for l in open(os.path.join(state, "installs.log"))]
      assert installs == [
          ["sdk-manager", "sdk", "install", nasty_ncs],
          ["sdk-manager", "toolchain", "install", "--toolchain-bundle-id", nasty_bundle],
      ], installs
      lines = [json.loads(l) for l in open(os.path.join(state, "commands.log"))]
      env_calls = [a for a in lines if a[:3] == ["sdk-manager", "toolchain", "env"]]
      assert env_calls, "no toolchain env calls recorded"
      for a in env_calls:
          assert "--ncs-version" not in a, a
          assert a[a.index("--toolchain-bundle-id") + 1] == nasty_bundle, a
          assert a[-2:] == ["--as-script", "sh"], a
      entry = [json.loads(l) for l in open(os.path.join(state, "west.log"))][-1]
      assert entry["argv"] == ["list", "--format=json"], entry
      assert entry["env"]["ZEPHYR_BASE"] == sdk + "/zephyr", entry["env"]
      PYEOF

      # ── Caller options, fake-package substitution gates (Nix-side) ──────
      [ -x "$nixNrfPkg/bin/nix-nrf" ] || { echo "FAIL: shell nix-nrf not executable" >&2; exit 1; }
      [ "$hasHello" = "1" ] || { echo "FAIL: caller packages did not propagate" >&2; exit 1; }
      [ "$hasRipgrep" = "1" ] || { echo "FAIL: inputsFrom did not propagate" >&2; exit 1; }
      [ -z "$boundaryHasMultilib" ] || { echo "FAIL: withMultilib = false still added multilib gcc" >&2; exit 1; }
      [ -z "$noAutoHasMultilib" ] || { echo "FAIL: no-auto withMultilib = false added multilib gcc" >&2; exit 1; }
      [ -z "$bundleHasMultilib" ] || { echo "FAIL: bundle withMultilib = false added multilib gcc" >&2; exit 1; }
      [ "$readyHasFakeNrfutil" = "1" ] || { echo "FAIL: fake nrfutil package not in ready shell" >&2; exit 1; }
      [ "$readyNoDefaultNrfutil" = "1" ] || { echo "FAIL: repository default nrfutil substituted into ready shell" >&2; exit 1; }
      [ "$noAutoHasFakeNrfutil" = "1" ] || { echo "FAIL: fake nrfutil package not in no-auto shell" >&2; exit 1; }
      [ "$noAutoNoDefaultNrfutil" = "1" ] || { echo "FAIL: repository default nrfutil substituted into no-auto shell" >&2; exit 1; }
      [ "$bundleHasFakeNrfutil" = "1" ] || { echo "FAIL: fake nrfutil package not in bundle shell" >&2; exit 1; }
      [ "$bundleNoDefaultNrfutil" = "1" ] || { echo "FAIL: repository default nrfutil substituted into bundle shell" >&2; exit 1; }

      echo "nrfutil shell boundary check passed" >&2
      mkdir -p "$out"
    '';

  # ── `nix-nrf versions` delegation boundary ─────────────────────────────
  # Purpose-specific fake nrfutil for the PUBLIC `nix-nrf versions` command
  # (nix/commands/default.nix). Unlike the lifecycle fake above, this one has
  # no install/toolchain/env state machine: the versions command only execs
  # `sdk-manager search` and must preserve argv, streams, and exit status
  # exactly. The fake therefore logs every argv as one JSON line to
  # commands.log, enforces the scenario's expected argv when
  # FAKE_VERSIONS_EXPECT_ARGV is set, and emits fixed deterministic
  # stdout/stderr/status per FAKE_VERSIONS_MODE. Modes: success (0),
  # remote-fail (1), cli-fail (2), status-37 (37), help (0, and the argv must
  # be exactly `sdk-manager search --help`). Any other argv shape exits 1
  # with the offending argv on stderr.
  fakeVersionsNrfutil = pkgs.writeTextFile {
    name = "fake-versions-nrfutil";
    destination = "/bin/nrfutil";
    executable = true;
    text = ''
      #!${pkgs.python3}/bin/python3
      # SPDX-License-Identifier: MIT
      #
      # Test-only nrfutil stand-in for the `nix-nrf versions` delegation
      # boundary gate (nix/flake/checks/nrfutil.nix). Contract: see the
      # check's design comment above.
      import json
      import os
      import sys
      from pathlib import Path

      STATE = os.environ.get("FAKE_VERSIONS_STATE", "")
      MODE = os.environ.get("FAKE_VERSIONS_MODE", "")
      EXPECT_ARGV = os.environ.get("FAKE_VERSIONS_EXPECT_ARGV", "")


      def fail(msg):
          print("fake versions nrfutil: " + msg, file=sys.stderr)
          return 1


      def log_command(argv):
          if not STATE:
              return
          Path(STATE).mkdir(parents=True, exist_ok=True)
          with open(os.path.join(STATE, "commands.log"), "a") as fh:
              fh.write(json.dumps(argv) + "\n")


      def main():
          argv = sys.argv[1:]
          if argv[:2] != ["sdk-manager", "search"]:
              return fail("unexpected argv: " + json.dumps(argv))
          log_command(argv)
          if EXPECT_ARGV:
              expected = json.loads(EXPECT_ARGV)
              # EXPECT_ARGV carries the caller args nix-nrf forwarded (after
              # the fixed `sdk-manager search` delegation prefix); the prefix
              # itself is enforced above.
              if argv[2:] != expected:
                  return fail(
                      "argv mismatch: got %s, expected %s"
                      % (json.dumps(argv), json.dumps(expected))
                  )
          if MODE == "help":
              if argv != ["sdk-manager", "search", "--help"]:
                  return fail(
                      "help delegation must be exactly sdk-manager search --help"
                  )
              print("fake versions help stdout")
              print("fake versions help stderr", file=sys.stderr)
              return 0
          if "--help" in argv:
              return fail("non-help scenario received --help: " + json.dumps(argv))
          if MODE == "success":
              print("fake versions success stdout")
              print("fake versions success stderr", file=sys.stderr)
              return 0
          if MODE == "remote-fail":
              print("fake versions remote-fail stdout")
              print("fake versions remote-fail stderr", file=sys.stderr)
              return 1
          if MODE == "cli-fail":
              print("fake versions cli-fail stdout")
              print("fake versions cli-fail stderr", file=sys.stderr)
              return 2
          if MODE == "status-37":
              print("fake versions status-37 stdout")
              print("fake versions status-37 stderr", file=sys.stderr)
              return 37
          return fail("unknown mode: " + MODE)


      if __name__ == "__main__":
          sys.exit(main())
    '';
  };

  # Test-only stand-in for the real OpenOCD package: the real
  # nix/commands/default.nix only uses `openocd` to prefix the probes
  # command's PATH (`${openocd}/bin`), which the versions boundary never
  # exercises. An empty package with the bin directory suffices; nothing
  # probes OpenOCD at runtime in this check.
  tinyTestOpenocd = pkgs.runCommand "tiny-test-openocd" {} ''
    mkdir -p "$out/bin"
  '';

  # Public `nix-nrf versions` delegation boundary gate: instantiates the REAL
  # nix/commands/default.nix with the purpose-specific fake nrfutil package
  # above (plus the tiny OpenOCD stand-in) and executes the packaged
  # `$cli/bin/nix-nrf` binary, never copied shell fragments. It checks against
  # deterministic fake output: `versions` delegates the exact argv
  # `sdk-manager search ...` with quoting preserved as single argv elements
  # (spaces, single quote, double quote, option-like values); stdout, stderr,
  # and status are preserved byte-for-byte for status 0, simulated
  # remote/index failure status 1, CLI failure status 2, and an arbitrary
  # nonstandard status 37 (never remapped); and both `versions --help` and
  # `help versions` delegate the exact argv `sdk-manager search --help` with
  # exact streams and status 0. The fake JSON argv log is parsed by Python
  # and asserted as one exact ordered invocation list. The fake/package seam
  # is test-only: no PATH or environment override is added to the production
  # command (nix/commands/default.nix is untouched).
  nrfutilVersionsBoundaryCheck = let
    versionsCli = import ../../commands/default.nix {
      inherit pkgs;
      nrfutilPackage = fakeVersionsNrfutil;
      openocd = tinyTestOpenocd;
    };
  in
    pkgs.runCommand "nrfutil-versions-boundary-check"
    {
      nativeBuildInputs = [pkgs.python3];
      inherit versionsCli fakeVersionsNrfutil;
    }
    ''
      set -eu

      export FAKE_VERSIONS_STATE="$PWD/state"
      mkdir -p "$FAKE_VERSIONS_STATE"

      # Expected stream content. The fake's deterministic stdout/stderr must
      # reach the caller unchanged through the real nix-nrf exec; these files
      # are the byte-for-byte contract and must match the fake's emitted
      # lines.
      printf 'fake versions success stdout\n' > expected.success.out
      printf 'fake versions success stderr\n' > expected.success.err
      printf 'fake versions remote-fail stdout\n' > expected.remote-fail.out
      printf 'fake versions remote-fail stderr\n' > expected.remote-fail.err
      printf 'fake versions cli-fail stdout\n' > expected.cli-fail.out
      printf 'fake versions cli-fail stderr\n' > expected.cli-fail.err
      printf 'fake versions status-37 stdout\n' > expected.status-37.out
      printf 'fake versions status-37 stderr\n' > expected.status-37.err
      printf 'fake versions help stdout\n' > expected.help.out
      printf 'fake versions help stderr\n' > expected.help.err

      # Build a JSON argv array from the given elements; the fake enforces it
      # exactly before emitting its scenario output.
      to_json() {
        python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@"
      }

      # run_scenario <label> <mode> <expected-json> <nix-nrf-args...>
      run_scenario() {
        label="$1"
        mode="$2"
        expected_json="$3"
        shift 3
        export FAKE_VERSIONS_MODE="$mode"
        export FAKE_VERSIONS_EXPECT_ARGV="$expected_json"
        set +e
        "$versionsCli/bin/nix-nrf" "$@" > "$label.out" 2> "$label.err"
        rc=$?
        set -e
        printf '%s\n' "$rc" > "$label.rc"
      }

      assert_exact() {
        # assert_exact <label> <expected-rc> <expected-out> <expected-err>
        label="$1"
        expected_rc="$2"
        expected_out="$3"
        expected_err="$4"
        actual_rc="$(cat "$label.rc")"
        [ "$actual_rc" = "$expected_rc" ] || {
          echo "FAIL: $label: status $actual_rc != $expected_rc" >&2
          cat "$label.err" >&2
          exit 1
        }
        cmp -s "$label.out" "$expected_out" || {
          echo "FAIL: $label: stdout differs" >&2
          diff -u "$expected_out" "$label.out" >&2 || true
          exit 1
        }
        cmp -s "$label.err" "$expected_err" || {
          echo "FAIL: $label: stderr differs" >&2
          diff -u "$expected_err" "$label.err" >&2 || true
          exit 1
        }
      }

      # Success: values with spaces, a single quote, a double quote, and an
      # option-like value must each stay one exact argv element.
      run_scenario success success \
        "$(to_json "v3.3.0 with spaces" "it's" 'say "hi"' "--option-like")" \
        versions "v3.3.0 with spaces" "it's" 'say "hi"' "--option-like"
      assert_exact success 0 expected.success.out expected.success.err

      # Simulated remote/index failure: status 1 preserved.
      run_scenario remote-fail remote-fail \
        "$(to_json v3.3.0)" versions v3.3.0
      assert_exact remote-fail 1 expected.remote-fail.out expected.remote-fail.err

      # CLI failure: status 2 preserved.
      run_scenario cli-fail cli-fail \
        "$(to_json --ncs-version v3.3.0)" versions --ncs-version v3.3.0
      assert_exact cli-fail 2 expected.cli-fail.out expected.cli-fail.err

      # Arbitrary nonstandard status: 37 preserved, not remapped.
      run_scenario status-37 status-37 \
        "$(to_json status-37)" versions status-37
      assert_exact status-37 37 expected.status-37.out expected.status-37.err

      # Both help forms delegate the exact argv `sdk-manager search --help`.
      run_scenario help-flag help "$(to_json --help)" versions --help
      assert_exact help-flag 0 expected.help.out expected.help.err

      run_scenario help-subcommand help "$(to_json --help)" help versions
      assert_exact help-subcommand 0 expected.help.out expected.help.err

      # The fake JSON argv log is the exact ordered invocation record.
      python3 - <<'PYEOF'
      import json
      import os

      lines = [
          json.loads(l)
          for l in open(os.path.join(os.environ["FAKE_VERSIONS_STATE"], "commands.log"))
      ]
      expected = [
          ["sdk-manager", "search", "v3.3.0 with spaces", "it's", 'say "hi"', "--option-like"],
          ["sdk-manager", "search", "v3.3.0"],
          ["sdk-manager", "search", "--ncs-version", "v3.3.0"],
          ["sdk-manager", "search", "status-37"],
          ["sdk-manager", "search", "--help"],
          ["sdk-manager", "search", "--help"],
      ]
      assert lines == expected, lines
      PYEOF

      echo "nrfutil versions boundary check passed" >&2
      mkdir -p "$out"
    '';

  # ── Real packaged nrfutil forced-offline gate ──────────────────────────
  # Runs the REAL packaged nrfutil (the same `nrfutil` the repository shells
  # carry) inside an isolated writable HOME and NRFUTIL_HOME with both
  # verified sdk-manager 1.15.0 index-override variables pointed at
  # unreachable loopback URLs. With a fresh NRFUTIL_HOME there is no local
  # config to fall back on, so sdk-manager must fetch the SDK remote config
  # and fails with its own diagnostic naming the URL. This proves the public
  # `nix-nrf versions` runtime authority (sdk-manager search) reports
  # non-success plus a real network/index diagnostic under offline conditions
  # It has no separate global connectivity probe and fails outright if
  # the command unexpectedly succeeds. (The fake boundary above proves argv
  # and status preservation deterministically; this real gate proves the
  # packaged binary's genuine offline failure mode.)
  nrfutilSearchOfflineCheck =
    pkgs.runCommand "nrfutil-search-offline"
    {
      inherit nrfutil;
    }
    ''
      set -eu

      export HOME="$PWD/home"
      export NRFUTIL_HOME="$PWD/nrfutil-home"
      mkdir -p "$HOME" "$NRFUTIL_HOME"

      export NRFUTIL_SDK_REMOTE_CONFIG_URL=http://127.0.0.1:9/sdk/config.json
      export NRFUTIL_TOOLCHAIN_REMOTE_CONFIG_URL=http://127.0.0.1:9/toolchain/config.json

      set +e
      timeout 120 "$nrfutil/bin/nrfutil" sdk-manager search > search.out 2> search.err
      rc=$?
      set -e

      [ "$rc" -ne 0 ] || {
        echo "FAIL: nrfutil sdk-manager search unexpectedly succeeded" >&2
        cat search.out >&2
        cat search.err >&2
        exit 1
      }
      [ "$rc" -ne 124 ] || {
        echo "FAIL: nrfutil sdk-manager search timed out after 120s" >&2
        cat search.out >&2
        cat search.err >&2
        exit 1
      }
      grep -F "Failed to download SDK remote config" search.err >/dev/null || {
        echo "FAIL: sdk-manager diagnostic 'Failed to download SDK remote config' missing" >&2
        cat search.out >&2
        cat search.err >&2
        exit 1
      }
      grep -F "127.0.0.1:9" search.err >/dev/null || {
        echo "FAIL: loopback index URL missing from the diagnostic" >&2
        cat search.out >&2
        cat search.err >&2
        exit 1
      }

      echo "nrfutil search offline check passed (status $rc)" >&2
      mkdir -p "$out"
    '';
in {
  bootstrap-tests = bootstrapTests;
  bootstrap-quoting = bootstrapQuotingCheck;
  nrfutil-shell-boundary = nrfutilShellBoundaryCheck;
  nrfutil-versions-boundary = nrfutilVersionsBoundaryCheck;
  nrfutil-search-offline = nrfutilSearchOfflineCheck;
}
