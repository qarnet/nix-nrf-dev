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

        # Packaged nRF Util with the sdk-manager extension. Extension archives,
        # versions, and hashes are maintained by Nixpkgs; this repository does
        # not duplicate them.
        nrfutil = pkgs.nrfutil.withExtensions ["nrfutil-sdk-manager"];

        # Public project CLI facade: fixed dispatcher over the default
        # composed nrfutil (versions), the internal probe command module
        # (probes), and the internal bootstrap command module (bootstrap),
        # which nix-nrf owns via nix/nix-nrf-probes.nix and
        # nix/nix-nrf-bootstrap.nix. ncsVersion/toolchainBundleId default to
        # null here, so the standalone package requires an explicit
        # --ncs-version; mkNrfShell instantiates its own nix-nrf with the
        # shell's selector values as configured defaults.
        nix-nrf = import ./nix/nix-nrf.nix {
          inherit pkgs;
          nrfutilPackage = nrfutil;
          openocd = openocd-master;
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
        };

        lib = {
          inherit mkNrfShell;
        };

        formatter = treefmtEval.config.build.wrapper;

        checks = {
          formatting = treefmtEval.config.build.check self;
          backend-selector = backendSelectorCheck;
          bootstrap-tests = bootstrapTests;
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
    };
}
