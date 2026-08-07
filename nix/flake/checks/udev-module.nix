# Isolated NixOS module-system gate: proves `self.nixosModules.udevRules`
# contributes only the declared `services.udev.packages` config boundary and
# the exact expected udev-rules package, using `lib.evalModules` — no full
# NixOS system, no build, no VM, no network.
#
# The proof has three parts:
# 1. Exact public option AND config surfaces: after excluding the
#    module-system `_module` internal option, the public module's option tree
#    is exactly `services.udev.packages`; its observable config tree is
#    exactly the same three levels. A module that declares an extra option
#    and sets it — or that sneaks config under a freeform/internal path —
#    would widen either surface and fail here. `_module.check` alone cannot
#    catch a self-declared extra option, so the surface assertions are the
#    load-bearing part.
# 2. Undeclared-config rejection: with `_module.check` enabled (the default),
#    a synthetic test-only module that defines `users.groups.plugdev`
#    without declaring it is rejected under `builtins.tryEval`. This proves
#    the gate harness itself enforces declared-only config. The synthetic
#    module never touches the public module or real configuration.
# 3. Exact package contribution: with the module imported, the package list
#    is exactly one entry whose outPath equals the internal nrfUdevRules
#    package; without the module the list is exactly empty.
#
# The real public module (`self.nixosModules.udevRules`) needs only `pkgs`
# beyond the standard module args; `specialArgs.pkgs` is a fake attrset with
# exactly `stdenv.hostPlatform.system = system` so the module resolves the
# same `self.packages.${system}.udev-rules` derivation as the flake does.
{
  pkgs,
  nixpkgs,
  self,
  system,
  nrfUdevRules,
}: let
  inherit (nixpkgs) lib;

  # Declaration module: the ONLY option surface this gate's module system may
  # accept. Anything defined but not declared is rejected while
  # `_module.check` is enabled; anything extra declared widens the option
  # surface asserted below.
  declaration = {
    options.services.udev.packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
    };
  };

  # Fake pkgs: enough for the real public module, nothing more.
  fakePkgs = {
    stdenv.hostPlatform.system = system;
  };

  withModule = lib.evalModules {
    modules = [
      declaration
      self.nixosModules.udevRules
    ];
    specialArgs.pkgs = fakePkgs;
  };

  withoutModule = lib.evalModules {
    modules = [declaration];
    specialArgs.pkgs = fakePkgs;
  };

  withModulePackages = withModule.config.services.udev.packages;
  withoutModulePackages = withoutModule.config.services.udev.packages;

  # 1. Exact public option surface: `_module` is the module-system internal
  #    option; everything else the public module declares must be exactly
  #    services.udev.packages. `builtins.attrNames` is sorted; the && chain
  #    short-circuits so a widened surface is reported, not a missing-path
  #    abort.
  publicOptions = builtins.removeAttrs withModule.options ["_module"];
  publicOptionSurfaceIsExact =
    builtins.attrNames publicOptions
    == ["services"]
    && builtins.attrNames publicOptions.services == ["udev"]
    && builtins.attrNames publicOptions.services.udev == ["packages"];

  # 1b. Exact public config surface: observable config must be exactly the
  #    same three levels. `_module` is removed defensively if present; the
  #    same short-circuit guards apply. A module cannot smuggle host config
  #    under another path without widening this surface (or tripping
  #    `_module.check` below).
  publicConfig = builtins.removeAttrs withModule.config ["_module"];
  publicConfigSurfaceIsExact =
    builtins.attrNames publicConfig
    == ["services"]
    && builtins.attrNames publicConfig.services == ["udev"]
    && builtins.attrNames publicConfig.services.udev == ["packages"];

  # 2. Undeclared-config rejection: a synthetic test-only module defines an
  #    unrelated path without declaring it; the enabled `_module.check` must
  #    make evaluation fail, proven under tryEval/deepSeq.
  undeclaredConfigRejected = let
    synthetic = lib.evalModules {
      modules = [
        declaration
        {users.groups.plugdev = {};}
      ];
      specialArgs.pkgs = fakePkgs;
    };
    forced = builtins.tryEval (builtins.deepSeq synthetic.config.users.groups.plugdev "forced");
  in
    !forced.success;

  # 3. Exact package contribution; the outPath check is guarded so an
  #    empty-list regression is reported by the count diagnostic, not an
  #    unguarded `builtins.head` abort.
  withModuleCountIsOne = builtins.length withModulePackages == 1;
  withModuleOutPathMatches =
    withModuleCountIsOne && (builtins.head withModulePackages).outPath == nrfUdevRules.outPath;
  withoutModuleIsEmpty = builtins.length withoutModulePackages == 0;
in {
  # Public check attr: the isolated evalModules gate as a plain derivation.
  udev-module-eval =
    pkgs.runCommand "nix-nrf-udev-module-eval-check"
    {
      inherit
        publicOptionSurfaceIsExact
        publicConfigSurfaceIsExact
        undeclaredConfigRejected
        withModuleCountIsOne
        withModuleOutPathMatches
        withoutModuleIsEmpty
        nrfUdevRules
        ;
    }
    ''
      [ "$publicOptionSurfaceIsExact" = "1" ] || {
        echo "udev-module-eval check: public module option surface is not exactly services.udev.packages" >&2
        exit 1
      }
      [ "$publicConfigSurfaceIsExact" = "1" ] || {
        echo "udev-module-eval check: public module config surface is not exactly services.udev.packages" >&2
        exit 1
      }
      [ "$undeclaredConfigRejected" = "1" ] || {
        echo "udev-module-eval check: undeclared config definition was NOT rejected by the enabled _module.check" >&2
        exit 1
      }
      [ "$withModuleCountIsOne" = "1" ] || {
        echo "udev-module-eval check: services.udev.packages length is not exactly 1 with nixosModules.udevRules imported" >&2
        exit 1
      }
      [ "$withModuleOutPathMatches" = "1" ] || {
        echo "udev-module-eval check: sole services.udev.packages entry is not the expected udev-rules package ($nrfUdevRules)" >&2
        exit 1
      }
      [ "$withoutModuleIsEmpty" = "1" ] || {
        echo "udev-module-eval check: services.udev.packages is not empty in the isolated module system without the module" >&2
        exit 1
      }
      echo "udev-module-eval check passed: exact option and config surfaces services.udev.packages, undeclared config rejected, exactly $nrfUdevRules with module and empty without" >&2
      mkdir -p "$out"
    '';
}
