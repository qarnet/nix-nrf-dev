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
        # shell's selector values as configured defaults.
        nix-nrf = import ./nix/nix-nrf.nix {
          inherit pkgs;
          nrfutilPackage = nrfutil;
          openocd = openocd-master;
          udevRules = nrfUdevRules;
        };

        mkNrfShell = import ./nix/mk-nrf-shell.nix {
          inherit
            pkgs
            openocd-master
            nrfutil
            ;
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
        # - omitted backend plus explicit ncsVersion evaluates,
        # - explicit "nrfutil" plus explicit ncsVersion evaluates,
        # - missing ncsVersion fails evaluation (ncsVersion is required),
        # - unsupported "sdk-nrf" does not evaluate,
        # - an explicit non-null toolchainBundleId evaluates,
        # - omitted/explicit autoBootstrap (true/false) values evaluate,
        # - exact toolchainBundleId evaluates in either bootstrap mode.
        # Pure Nix evaluation via builtins.tryEval — builds no SDK, runs no
        # network bootstrap. Note: builtins.tryEval cannot catch "called
        # without required argument" errors, so required-ness is proven with
        # builtins.functionArgs, which marks arguments *with* a default
        # `true` (so a required argument reads `false`).
        backendSelectorCheck = let
          evaluates = expr: (builtins.tryEval (builtins.seq expr true)).success;
          ncsVersionRequired = (builtins.functionArgs mkNrfShell).ncsVersion == false;
          omittedOk = evaluates (mkNrfShell {
            name = "backend-check-omitted";
            ncsVersion = "v3.3.0";
          });
          explicitOk = evaluates (mkNrfShell {
            name = "backend-check-explicit";
            backend = "nrfutil";
            ncsVersion = "v3.3.0";
          });
          unsupportedRejected =
            !evaluates (mkNrfShell {
              name = "backend-check-unsupported";
              backend = "sdk-nrf";
              ncsVersion = "v3.3.0";
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
            && omittedOk
            && explicitOk
            && unsupportedRejected
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
              omittedOk
              explicitOk
              unsupportedRejected
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
              echo "backend selector check: ncsVersion required, omitted+ncsVersion evaluates, nrfutil+ncsVersion evaluates, sdk-nrf rejected, toolchainBundleId evaluates, autoBootstrap omitted/true/false evaluates, exact bundle in either bootstrap mode evaluates"
              mkdir -p "$out"
            ''
            else ''
              echo "backend selector check FAILED" >&2
              echo "ncsVersionRequired=$ncsVersionRequired omittedOk=$omittedOk explicitOk=$explicitOk unsupportedRejected=$unsupportedRejected bundleIdOk=$bundleIdOk autoBootstrapOmittedOk=$autoBootstrapOmittedOk autoBootstrapTrueOk=$autoBootstrapTrueOk autoBootstrapFalseOk=$autoBootstrapFalseOk bundleIdAutoTrueOk=$bundleIdAutoTrueOk bundleIdAutoFalseOk=$bundleIdAutoFalseOk" >&2
              exit 1
            ''
          );

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
          udev-rules = udevRulesCheck;
          inherit pre-commit;
        };

        # Dogfood shell for hacking on this repo / ad-hoc probe work.
        # Composes mkNrfShell with pre-commit hooks (packages + shellHook).
        # autoBootstrap defaults to true: lazy SDK/toolchain bootstrap on the
        # first `west` invocation.
        devShells.default = mkNrfShell {
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
        devShells.clean-env-test = mkNrfShell {
          backend = "nrfutil";
          ncsVersion = "v3.3.0";
          name = "nix-nrf-dev-clean-env-test";
          withMultilib = false;
          inputsFrom = [cleanEnvFixture];
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
