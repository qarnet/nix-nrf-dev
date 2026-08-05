# mkNrfShell — devShell factory for nRF Connect SDK projects.
#
# Two backends provide the NCS toolchain environment:
#
# nrfutil (default): provides openocd-master (wrapped), the nix-nrf CLI
# facade (which owns the internal `nix-nrf probes`, `nix-nrf bootstrap`, and
# `nix-nrf doctor` command modules), the packaged nrfutil with the sdk-manager
# extension, multilib GCC (for native_sim -m32 builds), a scoped-env `west`
# wrapper with lazy SDK/toolchain bootstrap, and ZEPHYR_BASE derivation. The
# shell-specific `nix-nrf doctor` carries the exact udev-rules package path
# (internal `udevRules` closure wiring from flake.nix).
#
#   Scoped toolchain env: Nordic's `nrfutil sdk-manager toolchain env` script
#   exports PYTHONHOME, PYTHONPATH, LD_LIBRARY_PATH, GIT_EXEC_PATH, ... —
#   variables that break any non-toolchain tool run from the same shell (nix
#   itself fails to load shared libraries, nix-store pythons pick up the
#   wrong stdlib, git may misbehave). Instead of eval'ing that script into
#   the whole shell, the `west` wrapper evals it only inside west's process
#   tree (~100 ms overhead per invocation). Builds still see the full
#   toolchain because cmake/ninja/gcc are spawned by west.
#
#   Lazy bootstrap: the `west` wrapper invokes the shell-specific
#   `nix-nrf bootstrap --print-sdk-path` on every call. That checks the
#   configured NCS SDK source and selected toolchain, installs only when
#   something is missing (with interactive confirmation unless
#   NIX_NRF_BOOTSTRAP_YES=1 / `--yes`), and returns the absolute SDK root for
#   ZEPHYR_BASE. With `autoBootstrap = false` it only checks and, when anything
#   is missing, reports that automatic bootstrap is disabled plus the exact
#   `nix-nrf bootstrap` remediation — it never mutates. The shell hook itself
#   stays non-mutating (read-only `--check` path).
#
# west (experimental; v3.3.0 / x86_64-linux only): Nix owns the exact Zephyr
# SDK package, host tools, and the metadata-selected Python interpreter; the
# official mutable west workspace and a version-local venv own the NCS source,
# west, and workspace Python requirements (see nix/west-backend/). No
# nrfutil/sdk-manager participates. `nix-nrf versions`, `nix-nrf bootstrap`,
# and `nix-nrf doctor` become backend-aware via exact west command modules.
# `toolchainBundleId` and non-default `nrfutilPackage` overrides are rejected
# for west; `autoBootstrap`, `name`, `packages`, `withMultilib`,
# `extraShellHook`, and `inputsFrom` behave like the nrfutil backend.
#
# The NCS release is a required argument for both backends: every caller
# selects a release explicitly (no "latest" alias or default).
#
# Usage from a consumer flake:
#   devShells.default = nix-nrf-dev.lib.${system}.mkNrfShell {
#     backend = "nrfutil";
#     ncsVersion = "v3.3.0";
#   };
#
# West backend (experimental, metadata-supported releases only):
#   devShells.default = nix-nrf-dev.lib.${system}.mkNrfShell {
#     backend = "west";
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
  # Internal closure wiring, always supplied by flake.nix at the module
  # import: the exact udev-rules package whose store path the shell-specific
  # `nix-nrf doctor` wrapper reports in its remediation
  # (NIX_NRF_DOCTOR_UDEV_RULES). Required here so the wiring can never be
  # silently dropped — it is not a public consumer option; the public
  # `mkNrfShell { ... }` call signature is unchanged (only flake.nix imports
  # this module).
  udevRules,
  # West backend constructors, always supplied by flake.nix at the module
  # import: the version metadata attrset and the builder imports. The west
  # branch of this module constructs per-shell SDK/venv/bootstrap/versions
  # instances from the selected metadata; the builders contain no
  # release-specific literals.
  westVersions,
  westZephyrSdkBuilder,
  westEnvironmentBuilder,
  westBootstrapBuilder,
  westVersionsCommandBuilder,
}: {
  # Backend that provides the NCS toolchain environment. "nrfutil" is the
  # default (Nordic sdk-manager); "west" is the experimental hybrid backend
  # (Nix Zephyr SDK + host tools + Python, mutable west workspace + venv);
  # "sdk-nrf" remains reserved for a future Nix-native backend and fails
  # evaluation until implemented.
  backend ? "nrfutil",
  # NCS release (e.g. "v3.3.0"). Required: every caller selects a release
  # explicitly. For `backend = "west"` the release must be present in
  # nix/west-backend/versions.nix; unknown releases fail evaluation naming
  # the supported west versions.
  ncsVersion,
  # Exact patched Nordic toolchain bundle ID (nrfutil backend only). null
  # (omission) selects the newest compatible patched toolchain for
  # `ncsVersion` (via --ncs-version); a non-null value selects that exact
  # bundle (via --toolchain-bundle-id). Rejected for `backend = "west"`.
  toolchainBundleId ? null,
  # Lazy SDK/toolchain bootstrap: `west` checks the selection on every
  # invocation and installs only when something is missing (with
  # confirmation). false switches west to check-only with exact manual
  # remediation; shell entry stays non-mutating either way.
  autoBootstrap ? true,
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
  # inclusion (west wrapper, nix-nrf versions/bootstrap subcommands). Defaults
  # to the repository's packaged nrfutil with the sdk-manager extension;
  # advanced callers may supply another compatible derivation. Rejected for
  # `backend = "west"` (no nrfutil participates).
  nrfutilPackage ? nrfutil,
}: let
  # Backend selector: exact-match only, no aliases, no silent fallback.
  supportedBackends = [
    "nrfutil"
    "west"
  ];
  supportedBackendsMsg = builtins.concatStringsSep ", " supportedBackends;
  # Throws with the invalid value and the supported list; the assert below
  # forces it whenever the returned shell derivation is evaluated.
  backendSupported =
    builtins.elem backend supportedBackends
    || throw "mkNrfShell: unsupported backend '${backend}'; supported backends: ${supportedBackendsMsg}";

  useMultilib = pkgs.stdenv.isLinux && withMultilib;

  # West release resolution: only forced when backend == "west" (the nrfutil
  # branch never evaluates it). Fails evaluation for unknown releases and
  # names the supported west versions.
  westSupportedMsg = builtins.concatStringsSep ", " (
    builtins.sort builtins.lessThan (builtins.attrNames westVersions)
  );
  westReleaseSupported =
    builtins.hasAttr ncsVersion westVersions
    || throw "mkNrfShell: west backend: unknown NCS release '${ncsVersion}'; supported west releases: ${westSupportedMsg}";

  # ── nrfutil backend shell (unchanged behavior) ────────────────────────────
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
    nixNrf = import ./nix-nrf.nix {
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
        echo "${name} shell (backend ${backend}, NCS "$_ncs_version"${
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
    westNixNrf = import ./nix-nrf.nix {
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
    westEnvironmentBuilder {
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
  # Force backend validation when the returned shell derivation is
  # evaluated: unsupported values fail Nix evaluation instead of silently
  # falling back to nrfutil. West-specific restrictions (unknown release,
  # toolchainBundleId, non-default nrfutilPackage) are asserted only in the
  # selected west branch, so the nrfutil branch keeps today's behavior.
  assert backendSupported;
  assert backend != "west" || westReleaseSupported;
  assert backend
  != "west"
  || toolchainBundleId == null
  || throw "mkNrfShell: backend 'west' does not support toolchainBundleId (Nix owns the exact Zephyr SDK; the west workspace/venv own the source)";
  assert backend
  != "west"
  || nrfutilPackage.outPath == nrfutil.outPath
  || throw "mkNrfShell: backend 'west' does not support a non-default nrfutilPackage override (no nrfutil participates in the west backend)";
    if backend == "west"
    then westShell
    else nrfutilShell
