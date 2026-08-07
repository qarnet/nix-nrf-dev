# nix/backends/nrfutil/shell.nix — nrfutil backend dev shell construction.
# Receives the internal dependencies plus the shared nix-nrf constructor and
# a normalized set of public shell options (already validated by the public
# dispatcher). Owns the nrfutil exact-executable/override selection, the
# shell-specific nix-nrf facade, toolchain selector handling, the scoped
# `west` wrapper (lazy bootstrap + `toolchain env` inside west's process
# tree), multilib/OpenOCD PATH ordering, and the non-mutating shell hook.
{
  pkgs,
  openocd-master,
  nrfutil,
  udevRules,
  # Shared nix-nrf constructor (nix/commands/default.nix), supplied by the nrfutil
  # backend entry point; applied here with this shell's selector values.
  nixNrfConstructor,
}: {
  ncsVersion,
  toolchainBundleId ? null,
  autoBootstrap ? true,
  name ? "nrf-dev",
  packages ? [],
  withMultilib ? true,
  extraShellHook ? "",
  inputsFrom ? [],
  nrfutilPackage ? nrfutil,
}: let
  useMultilib = pkgs.stdenv.isLinux && withMultilib;
  # ── nrfutil backend shell ───────────────────────────────────────────
  nrfutilShell = let
    nrfutilExe = "${nrfutilPackage}/bin/nrfutil";

    # Escaped values assigned to shell variables once per generated script, so
    # no raw caller value is ever interpolated into shell source. The selector
    # decision (which flag) is still made at Nix evaluation; the values flow
    # through the escaped shell variables.
    ncsVersionEsc = pkgs.lib.escapeShellArg ncsVersion;
    bundleIdEsc = pkgs.lib.optionalString (toolchainBundleId != null) (
      pkgs.lib.escapeShellArg toolchainBundleId
    );
    # Toolchain selector for `nrfutil sdk-manager toolchain env`: exact bundle
    # ID when configured, otherwise the NCS release (newest compatible patched
    # toolchain).
    toolchainSelectorArgs =
      if toolchainBundleId != null
      then "--toolchain-bundle-id \"$_toolchain_bundle_id\""
      else "--ncs-version \"$_ncs_version\"";
    # Human-readable selector description for diagnostics. Never silently
    # falls back to the newest compatible bundle when an exact bundle is set.
    toolchainSelectorDesc =
      if toolchainBundleId != null
      then "exact toolchain bundle \"$_toolchain_bundle_id\""
      else "newest compatible toolchain for NCS \"$_ncs_version\"";

    # Public CLI facade, instantiated from the selected nrfutil package, the
    # wrapped openocd-master, and this shell's selector values — so a caller
    # package override also controls `versions`, and the shell-specific
    # `nix-nrf bootstrap` runs with the configured defaults (no CLI args
    # needed). The probes module is owned internally by nix-nrf.
    nixNrf = nixNrfConstructor {
      inherit
        pkgs
        nrfutilPackage
        ncsVersion
        toolchainBundleId
        udevRules
        ;
      openocd = openocd-master;
    };

    # `west` wrapper: lazy bootstrap, export ZEPHYR_BASE inside west's process,
    # load the NCS toolchain env, then exec the real west from the toolchain
    # (its bin dirs are prepended to PATH by the env script, so the first
    # non-wrapper `west` on PATH is the real one).
    westWrapper = pkgs.writeShellScriptBin "west" ''
      _nix_nrf=${nixNrf}/bin/nix-nrf
      _ncs_version=${ncsVersionEsc}
      ${pkgs.lib.optionalString (toolchainBundleId != null) ''
        _toolchain_bundle_id=${bundleIdEsc}
      ''}
      # Lazy bootstrap: the shell-specific helper checks the configured NCS SDK
      # source and selected toolchain, installs only when something is missing
      # (with confirmation), and prints the absolute SDK root for ZEPHYR_BASE.
      ${
        if autoBootstrap
        then ''
          _sdk_path="$("$_nix_nrf" bootstrap --print-sdk-path)" || {
            echo "west wrapper: SDK/toolchain bootstrap failed" >&2
            echo "Run: nix-nrf bootstrap" >&2
            exit 1
          }
        ''
        else ''
          _sdk_path="$("$_nix_nrf" bootstrap --check --quiet --print-sdk-path)" || {
            echo "west wrapper: automatic bootstrap is disabled (autoBootstrap = false)" >&2
            echo "Run: nix-nrf bootstrap" >&2
            exit 1
          }
        ''
      }
      if [ -z "$_sdk_path" ] || [ ! -d "$_sdk_path" ]; then
        echo "west wrapper: invalid SDK path from nix-nrf bootstrap: '$_sdk_path'" >&2
        exit 1
      fi
      export ZEPHYR_BASE="$_sdk_path/zephyr"
      _env="$(${nrfutilExe} sdk-manager toolchain env ${toolchainSelectorArgs} --as-script sh)" || {
        echo "west wrapper: nrfutil sdk-manager toolchain env ${toolchainSelectorArgs} failed" >&2
        echo "Selected toolchain: ${toolchainSelectorDesc}" >&2
        echo "Run: nix-nrf bootstrap" >&2
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
      inherit name inputsFrom;
      packages =
        [
          westWrapper
          openocd-master
          nrfutilPackage
          nixNrf
        ]
        ++ pkgs.lib.optionals useMultilib [pkgs.gccMultiStdenv.cc]
        ++ packages;

      shellHook = ''
        # Escaped selector values, assigned once; used by the banner, the
        # ZEPHYR_BASE derivation, and any toolchain env queries below.
        _ncs_version=${ncsVersionEsc}
        ${pkgs.lib.optionalString (toolchainBundleId != null) ''
          _toolchain_bundle_id=${bundleIdEsc}
        ''}
        _nix_nrf_exe=${nixNrf}/bin/nix-nrf
        echo "${name} shell (backend nrfutil, NCS "$_ncs_version"${
          pkgs.lib.optionalString (toolchainBundleId != null) ", toolchain bundle \"$_toolchain_bundle_id\""
        }, toolchain env scoped to west, ${
          if autoBootstrap
          then "lazy bootstrap on first west"
          else "manual bootstrap (autoBootstrap = false)"
        })"
        ${pkgs.lib.optionalString pkgs.stdenv.isLinux ''
          # ── ZEPHYR_BASE derivation ─────────────────────────────────────
          # The toolchain env itself stays scoped inside the west wrapper;
          # only ZEPHYR_BASE is exported here (needed by helper scripts and
          # for orientation). This shell must never mutate state: run the
          # shell-specific helper's read-only --check path and keep its
          # output even when overall readiness fails, because it may return
          # an installed SDK path while the toolchain is missing.
          if [ -z "''${ZEPHYR_BASE:-}" ]; then
            _zephyr_base="$("$_nix_nrf_exe" bootstrap --check --quiet --print-sdk-path 2>/dev/null || true)"
            if [ -n "$_zephyr_base" ] && [ -d "$_zephyr_base/zephyr" ]; then
              export ZEPHYR_BASE="$_zephyr_base/zephyr"
            else
              printf 'ZEPHYR_BASE could not be derived (NCS SDK source for %s not found).\n' "$_ncs_version" >&2
              printf 'Run `nix-nrf bootstrap` to install the selected SDK and toolchain.\n' >&2
            fi
          fi

          # Project-local helper scripts, if the project has them.
          if [ -d "$PWD/scripts/bin" ]; then
            export PATH="$PWD/scripts/bin:$PATH"
          fi
        ''}
        ${pkgs.lib.optionalString pkgs.stdenv.isLinux ''
          if [ -n "''${ZEPHYR_BASE:-}" ]; then
            echo "ZEPHYR_BASE: $ZEPHYR_BASE"
          fi
        ''}
        ${extraShellHook}
      '';
    };
in
  nrfutilShell
