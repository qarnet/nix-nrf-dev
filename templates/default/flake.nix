{
  description = "nRF firmware project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
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
        ncsVersion = "v3.3.0";
        # packages = [ ];          # extra project tools
        # extraShellHook = "";     # project-specific env
      };
    });
}
