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
  }: let
    # Repository's implemented host platform only. Per-system construction
    # (configured Nixpkgs, components, formatter/pre-commit, checks, dev
    # shells) lives in nix/flake/per-system.nix. Future platform expansion
    # must add implementation, metadata, and proof before being listed here.
    supportedSystems = ["x86_64-linux"];
  in
    flake-utils.lib.eachSystem supportedSystems (
      # Per-system construction (configured Nixpkgs, components,
      # formatter/pre-commit, checks, dev shells) lives in
      # nix/flake/per-system.nix.
      system:
        import ./nix/flake/per-system.nix {
          inherit
            self
            system
            nixpkgs
            treefmt-nix
            git-hooks
            ;
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
