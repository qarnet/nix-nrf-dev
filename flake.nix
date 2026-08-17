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
      # Minimal NixOS module: activate the packaged upstream OpenOCD
      # udev rules (60-openocd.rules) for the current system, so CMSIS-DAP
      # and J-Link nodes get MODE="660", GROUP="plugdev", TAG+="uaccess"
      # without hand-written rules. The module exposes no options and sets
      # only `services.udev.packages`; it does NOT create the `plugdev`
      # group or modify users. Group creation and user membership are
      # explicit host policy the consumer must configure:
      #
      #   users.groups.plugdev = {};
      #   users.users.<username>.extraGroups = [ "plugdev" ];
      #
      # Direct `services.udev.packages` configuration (docs/hardware.md) is
      # the primary least-intrusive path; this named module is a convenience
      # equivalent that contributes no host policy beyond the package list.
      #
      # Consumer:
      #   imports = [ nix-nrf-dev.nixosModules.udevRules ];
      nixosModules.udevRules = {pkgs, ...}: {
        services.udev.packages = [
          self.packages.${pkgs.stdenv.hostPlatform.system}.udev-rules
        ];
      };
    };
}
