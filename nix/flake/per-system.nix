# Per-system flake construction: configured Nixpkgs, components,
# formatter/pre-commit, checks, and dev shells. Imported once per supported
# system by the root flake's eachSystem supportedSystems, so flake.nix stays
# a thin description of inputs plus the non-system outputs.
{
  self,
  system,
  nixpkgs,
  treefmt-nix,
  git-hooks,
}: let
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

  components = import ./components.nix {inherit pkgs;};
  inherit
    (components)
    openocd-master
    openocd-master-unwrapped
    nrfUdevRules
    nrfutil
    nix-nrf
    westBackendVersions
    westBackendEntry
    westZephyrSdk
    westBootstrapBuilder
    westVersionsCommandBuilder
    mkNrfShell
    initProject
    ;

  treefmtEval = treefmt-nix.lib.evalModule pkgs ../../treefmt.nix;

  pre-commit = git-hooks.lib.${system}.run {
    src = ../../.;
    hooks = {
      alejandra.enable = true;
      deadnix.enable = true;
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

  devShells = import ./dev-shells.nix {inherit pkgs mkNrfShell pre-commit;};

  checks = import ./checks/default.nix {
    backendSelector = import ./checks/backend-selector.nix {inherit pkgs mkNrfShell;};
    core = import ./checks/core.nix {
      inherit
        pkgs
        nix-nrf
        nrfUdevRules
        openocd-master-unwrapped
        self
        nixpkgs
        system
        ;
      defaultDevShell = devShells.default;
    };
    # Isolated module-system gate: proves `nixosModules.udevRules` sets only
    # the declared `services.udev.packages` boundary via `lib.evalModules`.
    udevModule = import ./checks/udev-module.nix {
      inherit
        pkgs
        nixpkgs
        self
        system
        nrfUdevRules
        ;
    };
    # Booted VM clean-room gate: direct `services.udev.packages` activation
    # of the packaged rule under real systemd-udevd with explicit plugdev.
    udevVm = import ./checks/udev-vm.nix {
      inherit
        pkgs
        nrfUdevRules
        ;
    };
    nrfutil = import ./checks/nrfutil.nix {inherit pkgs nrfutil mkNrfShell;};
    west = import ./checks/west.nix {
      inherit
        pkgs
        mkNrfShell
        westBackendVersions
        westBackendEntry
        westZephyrSdk
        westBootstrapBuilder
        westVersionsCommandBuilder
        openocd-master
        nrfutil
        nrfUdevRules
        ;
    };
    initProject = import ./checks/init-project.nix {
      inherit
        pkgs
        westBackendVersions
        ;
    };
    # Release/changelog consistency gate: real scripts/release.py check plus
    # the unit contract suite against copied release.json + CHANGELOG.md.
    release = import ./checks/release.nix {inherit pkgs;};
    formatting = treefmtEval.config.build.check self;
    inherit pre-commit;
  };
in {
  apps.init-project = {
    type = "app";
    program = "${initProject}/bin/nix-nrf-init-project";
  };

  packages = {
    inherit
      openocd-master
      openocd-master-unwrapped
      nrfutil
      nix-nrf
      ;
    default = nix-nrf;
    # Host configuration consumes udev-rules (via nixosModules.udevRules or
    # direct services.udev.packages); keep it separate from nix-nrf.
    udev-rules = nrfUdevRules;
    # West backend SDK package: exact Zephyr SDK from official release
    # assets (packaged output backing `backend = "west"` shells).
    west-zephyr-sdk-v3_3_0 = westZephyrSdk;
  };

  lib = {
    inherit mkNrfShell;
  };

  formatter = treefmtEval.config.build.wrapper;

  inherit checks devShells;
}
