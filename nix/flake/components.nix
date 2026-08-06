# Per-system component construction shared by the flake's packages,
# devShells, and checks: OpenOCD (wrapped/unwrapped), udev rules, nrfutil,
# the standalone `nix-nrf` facade, west backend metadata/builders, and the
# public `mkNrfShell` factory. Receives the configured Nixpkgs instance
# (per-system.nix) and returns every construction the flake delegates to.
{pkgs}: let
  openocd-master-unwrapped = import ../openocd-master.nix {inherit pkgs;};

  # The from-source openocd build dlopens libudev at runtime; wrap it so
  # the binary works outside a NixOS system profile.
  openocd-master = pkgs.writeShellScriptBin "openocd" ''
    export LD_LIBRARY_PATH="${pkgs.systemd}/lib:''${LD_LIBRARY_PATH:-}"
    exec ${openocd-master-unwrapped}/bin/openocd "$@"
  '';

  # Thin relocation package exposing OpenOCD's canonical
  # 60-openocd.rules under the udev layout NixOS imports
  # ($out/lib/udev/rules.d). Copied byte-for-byte from the pinned
  # openocd-master-unwrapped build — no repository VID/PID catalog.
  # Consumed by the NixOS module (host configuration) and reported by
  # `nix-nrf doctor` remediation.
  nrfUdevRules = import ../nrf-udev-rules.nix {
    inherit pkgs;
    openocd = openocd-master-unwrapped;
  };

  # Packaged nRF Util with the sdk-manager extension. Extension archives,
  # versions, and hashes are maintained by Nixpkgs; this repository does
  # not duplicate them.
  nrfutil = pkgs.nrfutil.withExtensions ["nrfutil-sdk-manager"];

  # Public project CLI facade: fixed dispatcher over the default
  # composed nrfutil (versions), the internal probe command module
  # (probes), and the internal bootstrap command module (bootstrap),
  # which nix-nrf owns via nix/nix-nrf-probes.nix and
  # nix/nix-nrf-bootstrap.nix, plus the internal doctor command module
  # (doctor) via nix/nix-nrf-doctor.nix. ncsVersion/toolchainBundleId
  # default to null here, so the standalone package requires an explicit
  # --ncs-version; mkNrfShell instantiates its own nix-nrf with the
  # shell's selector values as configured defaults (and the west backend
  # supplies its exact versions/bootstrap command modules instead).
  nix-nrf = import ../nix-nrf.nix {
    inherit pkgs;
    nrfutilPackage = nrfutil;
    openocd = openocd-master;
    udevRules = nrfUdevRules;
  };

  # ── West backend (experimental; public `backend = "west"`) ────────
  # Version metadata lives entirely in nix/west-backend/versions.nix;
  # the wiring below only selects the metadata key and hands the
  # builders to mkNrfShell, which constructs per-shell instances from
  # the selected metadata. Builders contain no release-specific
  # literals.
  westBackendVersions = import ../west-backend/versions.nix;
  # Metadata key used by this repository's shells and checks.
  westBackendNcsVersion = "v3.3.0";
  westBackendEntry = westBackendVersions.${westBackendNcsVersion};
  # Exact Zephyr SDK package output (also exposed as
  # packages.west-zephyr-sdk-v3_3_0).
  westZephyrSdkBuilder = import ../west-backend/zephyr-sdk.nix;
  westZephyrSdk = westZephyrSdkBuilder {
    inherit pkgs;
    sdk = westBackendEntry.zephyrSdk;
  };
  westEnvironmentBuilder = import ../west-backend/environment.nix;
  westBootstrapBuilder = import ../nix-nrf-west-bootstrap.nix;
  westVersionsCommandBuilder = import ../west-backend/versions-command.nix;

  mkNrfShell = import ../mk-nrf-shell.nix {
    inherit
      pkgs
      openocd-master
      nrfutil
      westZephyrSdkBuilder
      westEnvironmentBuilder
      westBootstrapBuilder
      westVersionsCommandBuilder
      ;
    # Internal closure wiring: the shell-specific `nix-nrf doctor`
    # reports the exact udev-rules store path in its remediation.
    # Not a public mkNrfShell consumer option.
    udevRules = nrfUdevRules;
    # West backend version metadata attrset (internal module wiring).
    westVersions = westBackendVersions;
  };
in {
  inherit
    openocd-master
    openocd-master-unwrapped
    nrfUdevRules
    nrfutil
    nix-nrf
    westBackendVersions
    westBackendEntry
    westZephyrSdk
    westZephyrSdkBuilder
    westEnvironmentBuilder
    westBootstrapBuilder
    westVersionsCommandBuilder
    mkNrfShell
    ;
}
