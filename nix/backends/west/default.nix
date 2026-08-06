# nix/backends/west/default.nix — west backend construction. Receives the
# west version metadata and internal builders (validated/selected by the
# public dispatcher) and owns all current west branch construction: the
# metadata-selected Python package, the exact Zephyr SDK package, the west
# bootstrap and versions command modules, the shell-specific backend-aware
# nix-nrf facade with the west doctor label, and the call to west shell.nix.
{
  pkgs,
  openocd-master,
  udevRules,
  westVersions,
  westZephyrSdkBuilder,
  westBootstrapBuilder,
  westVersionsCommandBuilder,
}: {
  ncsVersion,
  autoBootstrap ? true,
  name ? "nrf-dev",
  packages ? [],
  withMultilib ? true,
  extraShellHook ? "",
  inputsFrom ? [],
}: let
  # ── west backend shell ─────────────────────────────────────────────────────
  westShell = let
    metadata = westVersions.${ncsVersion};
    pythonPackage =
      metadata.pythonPackage
          or (throw "mkNrfShell: west backend metadata for '${ncsVersion}' has no pythonPackage attribute");
    sdkPackage = westZephyrSdkBuilder {
      inherit pkgs;
      sdk = metadata.zephyrSdk;
    };
    # West workspace/venv bootstrap module; reached only through the
    # shell-specific `nix-nrf bootstrap`, never exposed on PATH.
    westBootstrap = westBootstrapBuilder {
      inherit pkgs;
      inherit pythonPackage;
      inherit metadata;
    };
    # Exact `nix-nrf versions` command module for the west backend.
    versionsCommand = westVersionsCommandBuilder {
      inherit pkgs;
      versions = westVersions;
    };
    # Shell-specific backend-aware nix-nrf: versions/bootstrap dispatch to
    # the exact west command modules and no nrfutil participates; doctor gets
    # the west bootstrap command plus the west environment label.
    westNixNrf = import ../../nix-nrf.nix {
      inherit
        pkgs
        udevRules
        ;
      openocd = openocd-master;
      nrfutilPackage = null;
      inherit (metadata) ncsVersion;
      versionsCommand = "${versionsCommand}/libexec/nix-nrf/versions";
      bootstrapCommand = "${westBootstrap}/libexec/nix-nrf/bootstrap";
      doctorEnvironmentLabel = "west workspace/Zephyr SDK";
    };
  in
    import ./shell.nix {
      inherit
        pkgs
        metadata
        pythonPackage
        sdkPackage
        westBootstrap
        autoBootstrap
        name
        packages
        withMultilib
        extraShellHook
        inputsFrom
        ;
      openocd = openocd-master;
      nixNrf = westNixNrf;
    };
in
  westShell
