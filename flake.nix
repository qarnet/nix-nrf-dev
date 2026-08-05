{
  description = "Reusable Nordic nRF development environment — NCS toolchain shell + openocd-master flashing tools";

  inputs = {
    # nixos-unstable: Nixpkgs packages nRF Util and its extensions (see
    # pkgs/by-name/nr/nrfutil); flake.lock pins the exact revision.
    # Consumers can replace this revision via
    # `inputs.nix-nrf-dev.inputs.nixpkgs.follows = "nixpkgs"`, which also
    # selects the packaged nrfutil/sdk-manager versions.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    treefmt-nix,
    git-hooks,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          # nrfutil and its extensions are unfree. The packaged nrfutil
          # derivation also unconditionally depends on segger-jlink-headless
          # and sets NRF_JLINK_DLL_PATH — including when only the sdk-manager
          # extension is composed — so SEGGER license acceptance is required
          # (no sdk-manager-only composition avoids J-Link).
          config = {
            allowUnfree = true;
            segger-jlink.acceptLicense = true;
          };
        };

        openocd-master-unwrapped = import ./nix/openocd-master.nix {inherit pkgs;};

        # The from-source openocd build dlopens libudev at runtime; wrap it so
        # the binary works outside a NixOS system profile.
        openocd-master = pkgs.writeShellScriptBin "openocd" ''
          export LD_LIBRARY_PATH="${pkgs.systemd}/lib:''${LD_LIBRARY_PATH:-}"
          exec ${openocd-master-unwrapped}/bin/openocd "$@"
        '';

        # Thin relocation package exposing OpenOCD's canonical
        # 60-openocd.rules under the udev layout NixOS imports
        # ($out/lib/udev/rules.d). Copied byte-for-byte from the pinned
        # openocd-master-unwrapped build — no repository VID/PID catalog.
        # Consumed by the NixOS module (host configuration) and reported by
        # `nix-nrf doctor` remediation.
        nrfUdevRules = import ./nix/nrf-udev-rules.nix {
          inherit pkgs;
          openocd = openocd-master-unwrapped;
        };

        # Packaged nRF Util with the sdk-manager extension. Extension archives,
        # versions, and hashes are maintained by Nixpkgs; this repository does
        # not duplicate them.
        nrfutil = pkgs.nrfutil.withExtensions ["nrfutil-sdk-manager"];

        # Public project CLI facade: fixed dispatcher over the default
        # composed nrfutil (versions), the internal probe command module
        # (probes), and the internal bootstrap command module (bootstrap),
        # which nix-nrf owns via nix/nix-nrf-probes.nix and
        # nix/nix-nrf-bootstrap.nix, plus the internal doctor command module
        # (doctor) via nix/nix-nrf-doctor.nix. ncsVersion/toolchainBundleId
        # default to null here, so the standalone package requires an explicit
        # --ncs-version; mkNrfShell instantiates its own nix-nrf with the
        # shell's selector values as configured defaults (and the west backend
        # supplies its exact versions/bootstrap command modules instead).
        nix-nrf = import ./nix/nix-nrf.nix {
          inherit pkgs;
          nrfutilPackage = nrfutil;
          openocd = openocd-master;
          udevRules = nrfUdevRules;
        };

        # ── West backend (experimental; public `backend = "west"`) ────────
        # Version metadata lives entirely in nix/west-backend/versions.nix;
        # the wiring below only selects the metadata key and hands the
        # builders to mkNrfShell, which constructs per-shell instances from
        # the selected metadata. Builders contain no release-specific
        # literals.
        westBackendVersions = import ./nix/west-backend/versions.nix;
        # Metadata key used by this repository's shells and checks.
        westBackendNcsVersion = "v3.3.0";
        westBackendEntry = westBackendVersions.${westBackendNcsVersion};
        # Exact Zephyr SDK package output (also exposed as
        # packages.west-zephyr-sdk-v3_3_0).
        westZephyrSdk = import ./nix/west-backend/zephyr-sdk.nix {
          inherit pkgs;
          sdk = westBackendEntry.zephyrSdk;
        };
        westZephyrSdkBuilder = import ./nix/west-backend/zephyr-sdk.nix;
        westEnvironmentBuilder = import ./nix/west-backend/environment.nix;
        westBootstrapBuilder = import ./nix/nix-nrf-west-bootstrap.nix;
        westVersionsCommandBuilder = import ./nix/west-backend/versions-command.nix;

        mkNrfShell = import ./nix/mk-nrf-shell.nix {
          inherit
            pkgs
            openocd-master
            nrfutil
            westZephyrSdkBuilder
            westEnvironmentBuilder
            westBootstrapBuilder
            westVersionsCommandBuilder
            ;
          # Internal closure wiring: the shell-specific `nix-nrf doctor`
          # reports the exact udev-rules store path in its remediation.
          # Not a public mkNrfShell consumer option.
          udevRules = nrfUdevRules;
          # West backend version metadata attrset (internal module wiring).
          westVersions = westBackendVersions;
        };

        # Internal hybrid-input fixture: plain mkShell whose packages provide
        # the regression tools (Node 24, Git, Python). clean-env-test pulls
        # them in via inputsFrom so CI's tool execution proves inputsFrom
        # propagation through mkNrfShell (regression for the reproduced Node 24
        # dynamic-link failure) instead of a direct packages list.
        cleanEnvFixture = pkgs.mkShell {
          packages = [
            pkgs.nodejs_24
            pkgs.git
            pkgs.python3
          ];
        };

        # Evaluation-level regression gate for the backend selector:
        # - omitted backend still equals the explicit nrfutil shell
        #   (identical derivations),
        # - omitted backend plus explicit ncsVersion evaluates,
        # - explicit "nrfutil" plus explicit ncsVersion evaluates,
        # - west + v3.3.0 evaluates,
        # - west + unknown release does not evaluate,
        # - missing ncsVersion fails evaluation (ncsVersion is required),
        # - unsupported "sdk-nrf" does not evaluate,
        # - west + non-null toolchainBundleId does not evaluate,
        # - west + non-default nrfutilPackage does not evaluate,
        # - an explicit non-null toolchainBundleId evaluates (nrfutil),
        # - omitted/explicit autoBootstrap (true/false) values evaluate for
        #   both backends,
        # - exact toolchainBundleId evaluates in either bootstrap mode.
        # Pure Nix evaluation via builtins.tryEval — builds no SDK, runs no
        # network bootstrap. Note: builtins.tryEval cannot catch "called
        # without required argument" errors, so required-ness is proven with
        # builtins.functionArgs, which marks arguments *with* a default
        # `true` (so a required argument reads `false`).
        backendSelectorCheck = let
          evaluates = expr: (builtins.tryEval (builtins.seq expr true)).success;
          ncsVersionRequired = (builtins.functionArgs mkNrfShell).ncsVersion == false;
          omittedEqualsNrfutil = let
            s1 = mkNrfShell {
              name = "backend-check-eq";
              ncsVersion = "v3.3.0";
            };
            s2 = mkNrfShell {
              name = "backend-check-eq";
              backend = "nrfutil";
              ncsVersion = "v3.3.0";
            };
          in
            s1.drvPath == s2.drvPath;
          omittedOk = evaluates (mkNrfShell {
            name = "backend-check-omitted";
            ncsVersion = "v3.3.0";
          });
          explicitOk = evaluates (mkNrfShell {
            name = "backend-check-explicit";
            backend = "nrfutil";
            ncsVersion = "v3.3.0";
          });
          westOk = evaluates (mkNrfShell {
            name = "backend-check-west";
            backend = "west";
            ncsVersion = "v3.3.0";
          });
          westUnknownRejected =
            !evaluates (mkNrfShell {
              name = "backend-check-west-unknown";
              backend = "west";
              ncsVersion = "not-a-release";
            });
          unsupportedRejected =
            !evaluates (mkNrfShell {
              name = "backend-check-unsupported";
              backend = "sdk-nrf";
              ncsVersion = "v3.3.0";
            });
          westBundleIdRejected =
            !evaluates (mkNrfShell {
              name = "backend-check-west-bundle-id";
              backend = "west";
              ncsVersion = "v3.3.0";
              toolchainBundleId = "bundle-id-check";
            });
          westNrfutilPackageRejected =
            !evaluates (mkNrfShell {
              name = "backend-check-west-nrfutil";
              backend = "west";
              ncsVersion = "v3.3.0";
              nrfutilPackage = pkgs.hello;
            });
          # Explicit `nrfutilPackage = null` must be rejected with the
          # backend-specific message (guarded before any outPath access), not
          # a null attribute/type error.
          westNullNrfutilPackageRejected =
            !evaluates (mkNrfShell {
              name = "backend-check-west-nrfutil-null";
              backend = "west";
              ncsVersion = "v3.3.0";
              nrfutilPackage = null;
            });
          westAutoOmittedOk = evaluates (mkNrfShell {
            name = "backend-check-west-auto-omitted";
            backend = "west";
            ncsVersion = "v3.3.0";
          });
          westAutoTrueOk = evaluates (mkNrfShell {
            name = "backend-check-west-auto-true";
            backend = "west";
            ncsVersion = "v3.3.0";
            autoBootstrap = true;
          });
          westAutoFalseOk = evaluates (mkNrfShell {
            name = "backend-check-west-auto-false";
            backend = "west";
            ncsVersion = "v3.3.0";
            autoBootstrap = false;
          });
          bundleIdOk = evaluates (mkNrfShell {
            name = "backend-check-bundle-id";
            ncsVersion = "v3.3.0";
            toolchainBundleId = "bundle-id-check";
          });
          autoBootstrapOmittedOk = evaluates (mkNrfShell {
            name = "bootstrap-check-omitted";
            ncsVersion = "v3.3.0";
          });
          autoBootstrapTrueOk = evaluates (mkNrfShell {
            name = "bootstrap-check-true";
            ncsVersion = "v3.3.0";
            autoBootstrap = true;
          });
          autoBootstrapFalseOk = evaluates (mkNrfShell {
            name = "bootstrap-check-false";
            ncsVersion = "v3.3.0";
            autoBootstrap = false;
          });
          bundleIdAutoTrueOk = evaluates (mkNrfShell {
            name = "bootstrap-check-bundle-true";
            ncsVersion = "v3.3.0";
            toolchainBundleId = "bundle-id-check";
            autoBootstrap = true;
          });
          bundleIdAutoFalseOk = evaluates (mkNrfShell {
            name = "bootstrap-check-bundle-false";
            ncsVersion = "v3.3.0";
            toolchainBundleId = "bundle-id-check";
            autoBootstrap = false;
          });
          pass =
            ncsVersionRequired
            && omittedEqualsNrfutil
            && omittedOk
            && explicitOk
            && westOk
            && westUnknownRejected
            && unsupportedRejected
            && westBundleIdRejected
            && westNrfutilPackageRejected
            && westNullNrfutilPackageRejected
            && westAutoOmittedOk
            && westAutoTrueOk
            && westAutoFalseOk
            && bundleIdOk
            && autoBootstrapOmittedOk
            && autoBootstrapTrueOk
            && autoBootstrapFalseOk
            && bundleIdAutoTrueOk
            && bundleIdAutoFalseOk;
        in
          pkgs.runCommand "backend-selector-check"
          {
            inherit
              ncsVersionRequired
              omittedEqualsNrfutil
              omittedOk
              explicitOk
              westOk
              westUnknownRejected
              unsupportedRejected
              westBundleIdRejected
              westNrfutilPackageRejected
              westNullNrfutilPackageRejected
              westAutoOmittedOk
              westAutoTrueOk
              westAutoFalseOk
              bundleIdOk
              autoBootstrapOmittedOk
              autoBootstrapTrueOk
              autoBootstrapFalseOk
              bundleIdAutoTrueOk
              bundleIdAutoFalseOk
              ;
          }
          (
            if pass
            then ''
              echo "backend selector check: ncsVersion required, omitted equals nrfutil, omitted+ncsVersion evaluates, nrfutil+ncsVersion evaluates, west+v3.3.0 evaluates, west unknown release rejected, sdk-nrf rejected, west toolchainBundleId rejected, west nrfutilPackage override (incl. explicit null) rejected, west autoBootstrap omitted/true/false evaluates, toolchainBundleId evaluates, autoBootstrap omitted/true/false evaluates, exact bundle in either bootstrap mode evaluates"
              mkdir -p "$out"
            ''
            else ''
              echo "backend selector check FAILED" >&2
              echo "ncsVersionRequired=$ncsVersionRequired omittedEqualsNrfutil=$omittedEqualsNrfutil omittedOk=$omittedOk explicitOk=$explicitOk westOk=$westOk westUnknownRejected=$westUnknownRejected unsupportedRejected=$unsupportedRejected westBundleIdRejected=$westBundleIdRejected westNrfutilPackageRejected=$westNrfutilPackageRejected westNullNrfutilPackageRejected=$westNullNrfutilPackageRejected westAutoOmittedOk=$westAutoOmittedOk westAutoTrueOk=$westAutoTrueOk westAutoFalseOk=$westAutoFalseOk bundleIdOk=$bundleIdOk autoBootstrapOmittedOk=$autoBootstrapOmittedOk autoBootstrapTrueOk=$autoBootstrapTrueOk autoBootstrapFalseOk=$autoBootstrapFalseOk bundleIdAutoTrueOk=$bundleIdAutoTrueOk bundleIdAutoFalseOk=$bundleIdAutoFalseOk" >&2
              exit 1
            ''
          );

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
        # (no standalone $out/bin/nix-nrf-west-* command).
        westBootstrapTests = let
          module = import ./nix/nix-nrf-west-bootstrap.nix {
            inherit pkgs;
            inherit (westBackendEntry) pythonPackage;
            metadata = westBackendEntry;
          };
        in
          pkgs.runCommand "nix-nrf-west-bootstrap-tests"
          {
            nativeBuildInputs = [pkgs.python3];
            inherit module;
            setupScript = ./bin/nix-nrf-west-bootstrap;
            testFile = ./tests/unit/test_nix_nrf_west_bootstrap.py;
          }
          ''
            cp "$setupScript" nix-nrf-west-bootstrap
            chmod +x nix-nrf-west-bootstrap
            cp "$testFile" test_nix_nrf_west_bootstrap.py
            NIX_NRF_WEST_BOOTSTRAP_SCRIPT="$PWD/nix-nrf-west-bootstrap" python3 test_nix_nrf_west_bootstrap.py
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
            testFile = ./tests/unit/test_nix_nrf_west_versions.py;
          }
          ''
            cp "$testFile" test_nix_nrf_west_versions.py
            NIX_NRF_WEST_VERSIONS_COMMAND="$versionsCommand/libexec/nix-nrf/versions" python3 test_nix_nrf_west_versions.py
            echo "west versions command tests passed" >&2
            mkdir -p "$out"
          '';

        # Cheap metadata schema gate: asserts every nix/west-backend
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
          nastyModule = import ./nix/mk-nrf-shell.nix {
            inherit
              pkgs
              openocd-master
              nrfutil
              westEnvironmentBuilder
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
            ws="home/ncs/$nastyNcsVersion"
            mkdir -p "$ws/.west" "$ws/nrf/scripts" "$ws/zephyr/scripts" "$ws/bootloader/mcuboot/scripts" "$ws/.venv/bin"
            printf '[manifest]\npath = nrf\nfile = west.yml\n' > "$ws/.west/config"
            printf 'manifest:\n' > "$ws/nrf/west.yml"
            printf '#!/bin/sh\n' > "$ws/zephyr/zephyr-env.sh"
            printf -- '-r requirements-base.txt\n' > "$ws/zephyr/scripts/requirements.txt"
            printf 'west>=0.14.0\n' > "$ws/zephyr/scripts/requirements-base.txt"
            printf -- '-r requirements-base.txt\n' > "$ws/nrf/scripts/requirements.txt"
            printf 'west>=1.4.0\n' > "$ws/nrf/scripts/requirements-base.txt"
            printf 'pyelftools>=0.29\n' > "$ws/bootloader/mcuboot/scripts/requirements.txt"
            for n in python pip; do
              printf '#!/bin/sh\nexit 0\n' > "$ws/.venv/bin/$n"
              chmod +x "$ws/.venv/bin/$n"
            done
            cat > "$ws/.venv/bin/west" <<'FAKEWEST'
            #!/bin/sh
            if [ "$1" = "--version" ]; then
              echo "West version: v1.4.0"
              exit 0
            fi
            echo "FAKE_WEST argv=$* ZEPHYR_BASE=$ZEPHYR_BASE"
            FAKEWEST
            chmod +x "$ws/.venv/bin/west"

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
          westDoctorModule = import ./nix/nix-nrf-doctor.nix {
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
            ws="$HOME/ncs/v3.3.0"
            mkdir -p "$ws/.west" "$ws/nrf/scripts" "$ws/zephyr/scripts" "$ws/bootloader/mcuboot/scripts" "$ws/.venv/bin"
            printf '[manifest]\npath = nrf\nfile = west.yml\n' > "$ws/.west/config"
            printf 'manifest:\n' > "$ws/nrf/west.yml"
            printf '#!/bin/sh\n' > "$ws/zephyr/zephyr-env.sh"
            printf -- '-r requirements-base.txt\n' > "$ws/zephyr/scripts/requirements.txt"
            printf 'west>=0.14.0\n' > "$ws/zephyr/scripts/requirements-base.txt"
            printf -- '-r requirements-base.txt\n' > "$ws/nrf/scripts/requirements.txt"
            printf 'west>=1.4.0\n' > "$ws/nrf/scripts/requirements-base.txt"
            printf 'pyelftools>=0.29\n' > "$ws/bootloader/mcuboot/scripts/requirements.txt"
            cat > "$ws/.venv/bin/python" <<'FAKEPY'
            #!/bin/sh
            echo "python argv=$*" >> "$HOME/venv.log"
            exit 0
            FAKEPY
            cat > "$ws/.venv/bin/pip" <<'FAKEPIP'
            #!/bin/sh
            echo "pip argv=$*" >> "$HOME/venv.log"
            exit 0
            FAKEPIP
            cat > "$ws/.venv/bin/west" <<'FAKEWEST'
            #!/bin/sh
            echo "west argv=$* ZEPHYR_BASE=''${ZEPHYR_BASE:-} ZEPHYR_TOOLCHAIN_VARIANT=''${ZEPHYR_TOOLCHAIN_VARIANT:-} ZEPHYR_SDK_INSTALL_DIR=''${ZEPHYR_SDK_INSTALL_DIR:-} PATH=$PATH" >> "$HOME/venv.log"
            if [ "$1" = "--version" ]; then
            echo "West version: v1.4.0"
            exit 0
            fi
            exit 0
            FAKEWEST
            chmod +x "$ws/.venv/bin/python" "$ws/.venv/bin/pip" "$ws/.venv/bin/west"

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
            NIX_NRF_BOOTSTRAP_YES=1 "$westPkg/bin/west" list --format=json > wrapper.out
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

        # Fake-boundary bootstrap test gate: runs
        # tests/unit/test_nix_nrf_bootstrap.py against a temporary fake
        # nrfutil executable/state directory with sandboxed Python stdlib.
        # Proves every lifecycle branch — ready selection, --check, approval,
        # install matrix, exact-bundle behavior, malformed state, failed and
        # incomplete installs, missing version — with no network, no real SDK,
        # and no real nrfutil state.
        bootstrapTests =
          pkgs.runCommand "nix-nrf-bootstrap-tests"
          {
            nativeBuildInputs = [pkgs.python3];
            bootstrapScript = ./bin/nix-nrf-bootstrap;
            testFile = ./tests/unit/test_nix_nrf_bootstrap.py;
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
        # instantiate and build nix/nix-nrf-bootstrap.nix with caller
        # selector values containing spaces and single/double quotes,
        # proving wrapProgram generation succeeds without shell injection
        # or syntax break, then round-trip the generated wrapper's exports
        # to prove the exact values — and the exact selected nrfutil store
        # path — survive.
        bootstrapQuotingCheck = let
          nastyNcsVersion = "v3.3.0 with space 'and quote'";
          nastyBundleId = "bundle \"with\" 'quotes' and spaces";
          module = import ./nix/nix-nrf-bootstrap.nix {
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
            doctorScript = ./bin/nix-nrf-doctor;
            testFile = ./tests/unit/test_nix_nrf_doctor.py;
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
          devShell = self.devShells.${system}.default;
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

        treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;

        pre-commit = git-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            alejandra.enable = true;
            deadnix = {
              enable = true;
              # templates/default/flake.nix is a consumer skeleton; its
              # conventional `self`/`nixpkgs` destructuring is idiomatic even
              # when unused.
              excludes = ["^templates/"];
            };
            statix.enable = true;
            black.enable = true;
            shellcheck = {
              enable = true;
              # .envrc is a direnv config, not a shell script — no shebang.
              excludes = ["\\.envrc$"];
            };
            typos.enable = true;
            end-of-file-fixer.enable = true;
            trim-trailing-whitespace.enable = true;
            check-added-large-files.enable = true;
            ripsecrets.enable = true;
            detect-private-keys.enable = true;
            actionlint.enable = true;
            convco = {
              enable = true;
              stages = ["commit-msg"];
            };
          };
        };
      in {
        packages = {
          inherit
            openocd-master
            openocd-master-unwrapped
            nrfutil
            nix-nrf
            ;
          default = nix-nrf;
          # Host configuration consumes udev-rules (via nixosModules.default);
          # keep it separate from nix-nrf.
          udev-rules = nrfUdevRules;
          # West backend SDK package: exact Zephyr SDK from official release
          # assets (packaged output backing `backend = "west"` shells).
          west-zephyr-sdk-v3_3_0 = westZephyrSdk;
        };

        lib = {
          inherit mkNrfShell;
        };

        formatter = treefmtEval.config.build.wrapper;

        checks = {
          formatting = treefmtEval.config.build.check self;
          backend-selector = backendSelectorCheck;
          bootstrap-tests = bootstrapTests;
          bootstrap-quoting = bootstrapQuotingCheck;
          doctor-tests = doctorTests;
          doctor-udev-wiring = doctorUdevWiringCheck;
          nix-nrf-help = nixNrfHelpCheck;
          udev-rules = udevRulesCheck;
          west-bootstrap-tests = westBootstrapTests;
          west-versions-tests = westVersionsTests;
          west-backend-metadata = westBackendMetadataCheck;
          west-backend-quoting = westBackendQuotingCheck;
          west-shell-boundary = westShellBoundaryCheck;
          inherit pre-commit;
        };

        devShells = {
          # Dogfood shell for hacking on this repo / ad-hoc probe work.
          # Composes mkNrfShell with pre-commit hooks (packages + shellHook).
          # autoBootstrap defaults to true: lazy SDK/toolchain bootstrap on
          # the first `west` invocation.
          default = mkNrfShell {
            backend = "nrfutil";
            ncsVersion = "v3.3.0";
            name = "nix-nrf-dev";
            packages = pre-commit.enabledPackages;
            extraShellHook = pre-commit.shellHook;
          };

          # Clean-environment test shell: exercises shell-hook behavior to
          # prove Nordic sdk-manager variables do not poison external tools
          # (Node 24, Git, Python). The tools arrive via inputsFrom from the
          # internal cleanEnvFixture. Added for CI regression gating.
          clean-env-test = mkNrfShell {
            backend = "nrfutil";
            ncsVersion = "v3.3.0";
            name = "nix-nrf-dev-clean-env-test";
            withMultilib = false;
            inputsFrom = [cleanEnvFixture];
          };
        };
      }
    )
    // {
      templates.default = {
        path = ./templates/default;
        description = "nRF firmware project with NCS toolchain shell and openocd-master flashing";
      };

      # Minimal NixOS module: activate the packaged upstream OpenOCD
      # udev rules (60-openocd.rules) for the current system, so CMSIS-DAP
      # and J-Link nodes get MODE="660", GROUP="plugdev", TAG+="uaccess"
      # without hand-written rules. No options in this version.
      #
      # Consumer:
      #   imports = [ nix-nrf-dev.nixosModules.default ];
      nixosModules.default = {pkgs, ...}: let
        system = pkgs.stdenv.hostPlatform.system;
      in {
        services.udev.packages = [
          self.packages.${system}.udev-rules
        ];
      };
    };
}
