# mkNrfShell — devShell factory for nRF Connect SDK projects.
#
# Provides: openocd-master (wrapped), nrf-probes, the packaged nrfutil with
# the sdk-manager extension, the nrf-sdk-versions helper, multilib GCC (for
# native_sim -m32 builds), a scoped-env `west` wrapper, and ZEPHYR_BASE
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
# The NCS release is a required argument: sdk-manager is the runtime
# authority for available versions, and every caller selects a release
# explicitly (no "latest" alias or default).
#
# Usage from a consumer flake:
#   devShells.default = nix-nrf-dev.lib.${system}.mkNrfShell {
#     backend = "nrfutil";
#     ncsVersion = "v3.3.0";
#   };
#
# Advanced callers may replace the composed nrfutil derivation (which must
# still provide `nrfutil` with the sdk-manager extension):
#   devShells.default = nix-nrf-dev.lib.${system}.mkNrfShell {
#     backend = "nrfutil";
#     ncsVersion = "v3.3.0";
#     nrfutilPackage = myNrfutil;
#   };
#
# Hybrid consumers may compose additional derivations via inputsFrom:
#   devShells.default = nix-nrf-dev.lib.${system}.mkNrfShell {
#     backend = "nrfutil";
#     ncsVersion = "v3.3.0";
#     inputsFrom = [ myPackage ];
#   };
{
  pkgs,
  openocd-master,
  nrfutil,
  nrf-probes,
}: {
  # Backend that provides the NCS toolchain environment. "nrfutil" is the
  # only implemented backend (Nordic sdk-manager); "sdk-nrf" is reserved for
  # a future Nix-native backend and fails evaluation until implemented.
  backend ? "nrfutil",
  # NCS release as installed by nrfutil sdk-manager (e.g. "v3.3.0").
  # Required: every caller selects a release explicitly.
  ncsVersion,
  # Exact patched Nordic toolchain bundle ID. null (omission) selects the
  # newest compatible patched toolchain for `ncsVersion` (via
  # --ncs-version); a non-null value selects that exact bundle (via
  # --toolchain-bundle-id).
  toolchainBundleId ? null,
  name ? "nrf-dev",
  # Extra packages for the shell (project-specific tools).
  packages ? [],
  # Multilib GCC for Zephyr native_sim (-m32) host builds on x86_64-linux.
  withMultilib ? true,
  # Appended after the environment setup.
  extraShellHook ? "",
  # Additional derivations whose environment to compose (propagated directly
  # to pkgs.mkShell). Use this for hybrid projects that need Node, Python,
  # or other non-Nordic tooling alongside the NCS toolchain.
  inputsFrom ? [],
  # Composed nrfutil derivation used for every nrfutil invocation and shell
  # inclusion (west wrapper, nrf-sdk-versions helper). Defaults to the
  # repository's packaged nrfutil with the sdk-manager extension; advanced
  # callers may supply another compatible derivation.
  nrfutilPackage ? nrfutil,
}: let
  # Backend selector: exact-match only, no aliases, no silent fallback.
  supportedBackends = ["nrfutil"];
  supportedBackendsMsg = builtins.concatStringsSep ", " supportedBackends;
  # Throws with the invalid value and the supported list; the assert below
  # forces it whenever the returned shell derivation is evaluated.
  backendSupported =
    builtins.elem backend supportedBackends
    || throw "mkNrfShell: unsupported backend '${backend}'; supported backends: ${supportedBackendsMsg}";

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
  # Remediation distinguishes missing SDK source from toolchain selection:
  # with an exact bundle, `sdk-manager install` alone would install the newest
  # compatible toolchain for the release, not the configured bundle, so the
  # exact toolchain must be installed separately by bundle ID. Single-line
  # strings keep generated-script indentation aligned at the call site.
  installSdkRemediation = ''
    echo "Install the SDK source with: nrfutil sdk-manager install \"$_ncs_version\"" >&2
  '';
  installToolchainRemediation = ''
    echo "Install the exact toolchain with: nrfutil sdk-manager toolchain install --toolchain-bundle-id \"$_toolchain_bundle_id\"" >&2
  '';
  installBothRemediation = ''
    echo "Install the SDK and its matching toolchain with: nrfutil sdk-manager install \"$_ncs_version\"" >&2
  '';

  # sdk-manager-backed version-list command, instantiated from the selected
  # nrfutil package so a caller package override also controls it.
  nrfSdkVersions = import ./nrf-sdk-versions.nix {
    inherit pkgs;
    inherit nrfutilPackage;
  };

  useMultilib = pkgs.stdenv.isLinux && withMultilib;

  # `west` wrapper: load the NCS toolchain env, then exec the real west
  # from the toolchain (its bin dirs are prepended to PATH by the env
  # script, so the first non-wrapper `west` on PATH is the real one).
  westWrapper = pkgs.writeShellScriptBin "west" ''
    _ncs_version=${ncsVersionEsc}
    ${pkgs.lib.optionalString (toolchainBundleId != null) ''
      _toolchain_bundle_id=${bundleIdEsc}
    ''}
    _env="$(${nrfutilExe} sdk-manager toolchain env ${toolchainSelectorArgs} --as-script sh)" || {
      echo "west wrapper: nrfutil sdk-manager toolchain env ${toolchainSelectorArgs} failed" >&2
      echo "Selected toolchain: ${toolchainSelectorDesc}" >&2
      echo "Is the NCS SDK source and its matching toolchain installed?" >&2
      ${pkgs.lib.optionalString (toolchainBundleId != null) installSdkRemediation}
      ${pkgs.lib.optionalString (toolchainBundleId != null) installToolchainRemediation}
      ${pkgs.lib.optionalString (toolchainBundleId == null) installBothRemediation}
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
  # Force backend validation when the returned shell derivation is
  # evaluated: unsupported values fail Nix evaluation instead of silently
  # falling back to nrfutil.
  assert backendSupported;
    pkgs.mkShell {
      inherit name inputsFrom;

      packages =
        [
          westWrapper
          openocd-master
          nrf-probes
          nrfutilPackage
          nrfSdkVersions
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
        echo "${name} shell (backend ${backend}, NCS "$_ncs_version"${
          pkgs.lib.optionalString (toolchainBundleId != null) ", toolchain bundle \"$_toolchain_bundle_id\""
        }, toolchain env scoped to west)"
        ${pkgs.lib.optionalString pkgs.stdenv.isLinux ''
          # ── ZEPHYR_BASE derivation ─────────────────────────────────────
          # The toolchain env itself stays scoped inside the west wrapper;
          # only ZEPHYR_BASE is exported here (needed by helper scripts and
          # for orientation). Derive it from the toolchain layout without
          # polluting this shell, falling back to the well-known home path.
          if [ -z "''${ZEPHYR_BASE:-}" ]; then
            _zephyr_candidate=""
            _sdk_dir="$(
              eval "$(${nrfutilExe} sdk-manager toolchain env ${toolchainSelectorArgs} --as-script sh 2>/dev/null)" 2>/dev/null
              printf '%s' "''${ZEPHYR_SDK_INSTALL_DIR:-}"
            )"
            if [ -n "$_sdk_dir" ]; then
              _ncs_root="$(dirname "$(dirname "$(dirname "$(dirname "$_sdk_dir")")")")"
              _zephyr_candidate="$_ncs_root/$_ncs_version/zephyr"
            fi
            if [ ! -d "''${_zephyr_candidate:-}" ] && [ -d "$HOME/ncs/$_ncs_version/zephyr" ]; then
              _zephyr_candidate="$HOME/ncs/$_ncs_version/zephyr"
            fi
            if [ -n "''${_zephyr_candidate:-}" ] && [ -d "$_zephyr_candidate" ]; then
              export ZEPHYR_BASE="$_zephyr_candidate"
            else
              printf 'ZEPHYR_BASE could not be derived.\n' >&2
              printf 'Set it manually: export ZEPHYR_BASE=/path/to/ncs/%s/zephyr\n' "$_ncs_version" >&2
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
    }
