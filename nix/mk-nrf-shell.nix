# mkNrfShell — devShell factory for nRF Connect SDK projects.
#
# Provides: openocd-master (wrapped), nrf-probes, nrfutil-core, multilib GCC
# (for native_sim -m32 builds), a scoped-env `west` wrapper, and ZEPHYR_BASE
# derivation.
#
# Scoped toolchain env: Nordic's `nrfutil sdk-manager toolchain env` script
# exports PYTHONHOME, PYTHONPATH, LD_LIBRARY_PATH, GIT_EXEC_PATH, ... —
# variables that break any non-toolchain tool run from the same shell (nix
# itself fails to load shared libraries, nix-store pythons pick up the
# wrong stdlib, git may misbehave). Instead of eval'ing that script into
# the whole shell, the `west` wrapper evals it only inside west's process
# tree (~100 ms overhead per invocation). Builds still see the full
# toolchain because cmake/ninja/gcc are spawned by west.
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
}: {
  # NCS version as installed by nrfutil sdk-manager (e.g. "v3.3.0").
  ncsVersion ? "v3.3.0",
  name ? "nrf-dev",
  # Extra packages for the shell (project-specific tools).
  packages ? [],
  # Multilib GCC for Zephyr native_sim (-m32) host builds on x86_64-linux.
  withMultilib ? true,
  # Appended after the environment setup.
  extraShellHook ? "",
}: let
  nrfutilExe =
    if nrfutil-core != null
    then "${nrfutil-core}/bin/nrfutil"
    else "nrfutil";

  useMultilib = pkgs.stdenv.isLinux && withMultilib;

  # `west` wrapper: load the NCS toolchain env, then exec the real west
  # from the toolchain (its bin dirs are prepended to PATH by the env
  # script, so the first non-wrapper `west` on PATH is the real one).
  westWrapper = pkgs.writeShellScriptBin "west" ''
    unset NRFUTIL_HOME
    _env="$(${nrfutilExe} sdk-manager toolchain env --ncs-version ${ncsVersion} --as-script sh)" || {
      echo "west wrapper: 'nrfutil sdk-manager toolchain env --ncs-version ${ncsVersion}' failed" >&2
      echo "Is the NCS toolchain installed? (nrfutil sdk-manager toolchain install --ncs-version ${ncsVersion})" >&2
      exit 1
    }
    eval "$_env"
    ${pkgs.lib.optionalString useMultilib ''
      # Keep multilib GCC ahead of the toolchain's host gcc so native_sim
      # -m32 builds work.
      export PATH="${pkgs.gccMultiStdenv.cc}/bin:$PATH"
    ''}
    # Keep our openocd ahead of anything the toolchain bundle might ship —
    # the west openocd runner must use the openocd-master build.
    export PATH="${openocd-master}/bin:$PATH"

    self="$(readlink -f "$0")"
    while IFS= read -r cand; do
      if [ "$(readlink -f "$cand")" != "$self" ]; then
        exec "$cand" "$@"
      fi
    done < <(type -aP west)
    echo "west wrapper: real west not found in the NCS toolchain env" >&2
    exit 1
  '';
in
  pkgs.mkShell {
    inherit name;

    packages =
      [
        westWrapper
        openocd-master
        nrf-probes
      ]
      ++ pkgs.lib.optionals (nrfutil-core != null) [nrfutil-core]
      ++ pkgs.lib.optionals useMultilib [pkgs.gccMultiStdenv.cc]
      ++ packages;

    shellHook = ''
      ${pkgs.lib.optionalString pkgs.stdenv.isLinux ''
        # ── ZEPHYR_BASE derivation ─────────────────────────────────────
        # The toolchain env itself stays scoped inside the west wrapper;
        # only ZEPHYR_BASE is exported here (needed by helper scripts and
        # for orientation). Derive it from the toolchain layout without
        # polluting this shell, falling back to the well-known home path.
        if [ -z "''${ZEPHYR_BASE:-}" ]; then
          _zephyr_candidate=""
          _sdk_dir="$(
            unset NRFUTIL_HOME
            eval "$(${nrfutilExe} sdk-manager toolchain env --ncs-version ${ncsVersion} --as-script sh 2>/dev/null)" 2>/dev/null
            printf '%s' "''${ZEPHYR_SDK_INSTALL_DIR:-}"
          )"
          if [ -n "$_sdk_dir" ]; then
            _ncs_root="$(dirname "$(dirname "$(dirname "$(dirname "$_sdk_dir")")")")"
            _zephyr_candidate="$_ncs_root/${ncsVersion}/zephyr"
          fi
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
      ''}
      echo "${name} shell (NCS ${ncsVersion}, toolchain env scoped to west)"
      ${pkgs.lib.optionalString pkgs.stdenv.isLinux ''
        if [ -n "''${ZEPHYR_BASE:-}" ]; then
          echo "ZEPHYR_BASE: $ZEPHYR_BASE"
        fi
      ''}
      ${extraShellHook}
    '';
  }
