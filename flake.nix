{
  description = "Reusable Nordic nRF development environment — NCS toolchain shell + openocd-master flashing tools";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true; # nrfutil-core is unfree
        };

        openocd-master-unwrapped = import ./nix/openocd-master.nix { inherit pkgs; };

        # The from-source openocd build dlopens libudev at runtime; wrap it so
        # the binary works outside a NixOS system profile.
        openocd-master = pkgs.writeShellScriptBin "openocd" ''
          export LD_LIBRARY_PATH="${pkgs.systemd}/lib:''${LD_LIBRARY_PATH:-}"
          exec ${openocd-master-unwrapped}/bin/openocd "$@"
        '';

        nrfutil-core = import ./nix/nrfutil-core.nix { inherit pkgs system; };

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
      in
      {
        packages = {
          inherit openocd-master openocd-master-unwrapped nrf-probes;
        }
        // pkgs.lib.optionalAttrs (nrfutil-core != null) { inherit nrfutil-core; };

        lib = {
          inherit mkNrfShell;
        };

        # Dogfood shell for hacking on this repo / ad-hoc probe work.
        devShells.default = mkNrfShell { name = "nix-nrf-dev"; };
      }
    )
    // {
      templates.default = {
        path = ./templates/default;
        description = "nRF firmware project with NCS toolchain shell and openocd-master flashing";
      };
    };
}
