{
  description = "nRF firmware project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # The follows directive makes this project's Nixpkgs revision (and with
    # it the packaged nrfutil/sdk-manager versions) replace the one
    # nix-nrf-dev pins in its flake.lock.
    nix-nrf-dev = {
      url = "github:qarnet/nix-nrf-dev";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    nix-nrf-dev,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: {
      devShells.default = nix-nrf-dev.lib.${system}.mkNrfShell {
        backend = "nrfutil";
        ncsVersion = "v3.3.0";
        # autoBootstrap = true; # lazy: first `west` installs a missing SDK/toolchain
        # packages = [ ];          # extra project tools
        # extraShellHook = "";     # project-specific env
      };
    });
}
