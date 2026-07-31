{
  description = "Reusable Nordic nRF development environment — NCS toolchain shell + openocd-master flashing tools";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
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
          config.allowUnfree = true; # nrfutil-core is unfree
        };

        openocd-master-unwrapped = import ./nix/openocd-master.nix {inherit pkgs;};

        # The from-source openocd build dlopens libudev at runtime; wrap it so
        # the binary works outside a NixOS system profile.
        openocd-master = pkgs.writeShellScriptBin "openocd" ''
          export LD_LIBRARY_PATH="${pkgs.systemd}/lib:''${LD_LIBRARY_PATH:-}"
          exec ${openocd-master-unwrapped}/bin/openocd "$@"
        '';

        nrfutil-core = import ./nix/nrfutil-core.nix {inherit pkgs system;};

        nrf-probes = import ./nix/nrf-probes.nix {
          inherit pkgs;
          openocd = openocd-master;
        };

        mkNrfShell = import ./nix/mk-nrf-shell.nix {
          inherit
            pkgs
            openocd-master
            nrfutil-core
            nrf-probes
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
        packages =
          {
            inherit openocd-master openocd-master-unwrapped nrf-probes;
          }
          // pkgs.lib.optionalAttrs (nrfutil-core != null) {inherit nrfutil-core;};

        lib = {
          inherit mkNrfShell;
        };

        formatter = treefmtEval.config.build.wrapper;

        checks = {
          formatting = treefmtEval.config.build.check self;
          inherit pre-commit;
        };

        # Dogfood shell for hacking on this repo / ad-hoc probe work.
        # Composes mkNrfShell with pre-commit hooks (packages + shellHook).
        devShells.default = mkNrfShell {
          name = "nix-nrf-dev";
          packages = pre-commit.enabledPackages;
          extraShellHook = pre-commit.shellHook;
        };

        # Clean-environment test shell: exercises shell-hook behavior to
        # prove Nordic sdk-manager variables do not poison external tools
        # (Node 24, Git, Python). The tools arrive via inputsFrom from the
        # internal cleanEnvFixture. Added for CI regression gating.
        devShells.clean-env-test = mkNrfShell {
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
