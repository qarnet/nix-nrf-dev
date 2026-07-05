# mkNrfShell — devShell factory for nRF Connect SDK projects.
#
# Provides: openocd-master (wrapped), nrf-probes, nrfutil-core, multilib GCC
# (for native_sim -m32 builds), the nrfutil sdk-manager toolchain environment
# for the requested NCS version, and ZEPHYR_BASE derivation.
#
# Usage from a consumer flake:
#   devShells.default = nix-nrf-dev.lib.${system}.mkNrfShell {
#     ncsVersion = "v3.3.0";
#   };
{
  pkgs,
  openocd-master,
  nrfutil-core,
  nrf-probes,
}:

{
  # NCS version as installed by nrfutil sdk-manager (e.g. "v3.3.0").
  ncsVersion ? "v3.3.0",
  name ? "nrf-dev",
  # Extra packages for the shell (project-specific tools).
  packages ? [ ],
  # Multilib GCC for Zephyr native_sim (-m32) host builds on x86_64-linux.
  withMultilib ? true,
  # Appended after the NCS environment setup.
  extraShellHook ? "",
}:

pkgs.mkShell {
  inherit name;

  packages = [
    openocd-master
    nrf-probes
  ]
  ++ pkgs.lib.optionals (nrfutil-core != null) [ nrfutil-core ]
  ++ pkgs.lib.optionals (pkgs.stdenv.isLinux && withMultilib) [ pkgs.gccMultiStdenv.cc ]
  ++ packages;

  shellHook = ''
    ${pkgs.lib.optionalString pkgs.stdenv.isLinux ''
      # ── NCS toolchain env ──────────────────────────────────────────
      # Dynamically loaded via nrfutil. All toolchain/SDK paths are
      # resolved at runtime — no hardcoded hashes.
      if command -v nrfutil >/dev/null 2>&1; then
        # Clear inherited NRFUTIL_HOME from parent shells so the
        # nrfutil-core binary uses its own default home (~/.nrfutil).
        unset NRFUTIL_HOME
        eval "$(nrfutil sdk-manager toolchain env --ncs-version ${ncsVersion} --as-script sh)"
      else
        printf 'nrfutil not found — NCS toolchain not loaded.\n' >&2
      fi

      # ── ZEPHYR_BASE derivation ─────────────────────────────────────
      if [ -z "''${ZEPHYR_BASE:-}" ]; then
        _zephyr_candidate=""
        # Strategy 1: derive from toolchain layout (nrfutil-managed)
        if [ -n "''${ZEPHYR_SDK_INSTALL_DIR:-}" ]; then
          _ncs_root="$(dirname "$(dirname "$(dirname "$(dirname "$ZEPHYR_SDK_INSTALL_DIR")")")")"
          _zephyr_candidate="$_ncs_root/${ncsVersion}/zephyr"
        fi
        # Strategy 2: well-known user-home path
        if [ ! -d "''${_zephyr_candidate:-}" ] && [ -d "$HOME/ncs/${ncsVersion}/zephyr" ]; then
          _zephyr_candidate="$HOME/ncs/${ncsVersion}/zephyr"
        fi
        if [ -n "''${_zephyr_candidate:-}" ] && [ -d "$_zephyr_candidate" ]; then
          export ZEPHYR_BASE="$_zephyr_candidate"
        else
          printf 'ZEPHYR_BASE could not be derived.\n' >&2
          printf 'Set it manually: export ZEPHYR_BASE=/path/to/ncs/${ncsVersion}/zephyr\n' >&2
        fi
      fi

      # Project-local helper scripts, if the project has them.
      if [ -d "$PWD/scripts/bin" ]; then
        export PATH="$PWD/scripts/bin:$PATH"
      fi
      ${pkgs.lib.optionalString withMultilib ''
        export PATH="${pkgs.gccMultiStdenv.cc}/bin:$PATH"
      ''}
    ''}
    echo "${name} shell (NCS ${ncsVersion})"
    ${pkgs.lib.optionalString pkgs.stdenv.isLinux ''
      if command -v west >/dev/null 2>&1; then
        echo "west: $(west --version 2>/dev/null | head -n 1)"
      fi
      if [ -n "''${ZEPHYR_BASE:-}" ]; then
        echo "ZEPHYR_BASE: $ZEPHYR_BASE"
      fi
    ''}
    ${extraShellHook}
  '';
}
