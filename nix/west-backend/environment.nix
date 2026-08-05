# nix/west-backend/environment.nix — public west backend dev shell, selected
# by `mkNrfShell { backend = "west"; ncsVersion = ...; }`.
#
# The hybrid model:
#   - Nix owns the exact Zephyr SDK package (ZEPHYR_SDK_INSTALL_DIR /
#     ZEPHYR_TOOLCHAIN_VARIANT via its setup hook), the metadata-selected
#     Python interpreter (pkgs.<pythonPackage>) with venv support, and the
#     host tools (cmake, ninja, dtc, gperf, Git, ccache, dfu-util, file, xz,
#     make, which, optional multilib GCC);
#   - the official mutable west workspace and the version-local venv own the
#     NCS repositories and Python requirements, provisioned by the west
#     bootstrap module (`nix-nrf bootstrap`);
#   - no nrfutil, sdk-manager, or Nordic opaque toolchain bundle participates
#     (this shell intentionally does not include them).
#
# Metadata values (NCS version, SDK version, Python version) are metadata-
# controlled and may contain shell metacharacters, so every escaped value is
# assigned to a shell variable OUTSIDE double quotes and all paths/messages
# are composed from those variables — never by interpolating an escapeShellArg
# output directly inside double quotes (which would embed literal quote
# characters into the value).
#
# The scoped `west` wrapper requires the shell-specific `nix-nrf bootstrap`
# readiness to pass (mutating when `autoBootstrap = true`, read-only when
# false), prepends .venv/bin only inside west's process, exports ZEPHYR_BASE /
# ZEPHYR_TOOLCHAIN_VARIANT / ZEPHYR_SDK_INSTALL_DIR, keeps the project
# OpenOCD ahead of other runners, and execs the exact venv west.
#
# The shell hook is read-only: banner, workspace path, readiness via the
# backend-aware `nix-nrf bootstrap --check --quiet --print-sdk-path`, and
# ZEPHYR_BASE only when ready. It never activates the venv globally and never
# runs setup/update/pip.
{
  pkgs,
  # Exact Zephyr SDK package (nix/west-backend/zephyr-sdk.nix output).
  sdkPackage,
  # Version metadata entry (versions.nix), keyed by NCS release.
  metadata,
  # Nixpkgs package attribute name for the metadata-selected Python (e.g.
  # "python312"); never a release-specific literal in this builder.
  pythonPackage,
  # Packaged west bootstrap module (nix/nix-nrf-west-bootstrap.nix output);
  # reached through the shell-specific `nix-nrf bootstrap`, never exposed on
  # PATH itself.
  westBootstrap,
  # Wrapped project OpenOCD (kept ahead of any runner-spawned openocd).
  openocd,
  # Shell-specific backend-aware nix-nrf facade (versions/bootstrap/doctor
  # dispatch to the exact west command modules; no nrfutil).
  nixNrf,
  # Public shell options, propagated from mkNrfShell.
  autoBootstrap ? true,
  name ? "nrf-dev",
  packages ? [],
  withMultilib ? true,
  extraShellHook ? "",
  inputsFrom ? [],
}:
assert pkgs.stdenv.hostPlatform.system
== "x86_64-linux"
|| throw "west backend supports only x86_64-linux; got ${pkgs.stdenv.hostPlatform.system}"; let
  # Escaped metadata values; assigned to shell variables outside double
  # quotes so the shell consumes the quoting and the variables hold raw
  # values that can safely be embedded in double-quoted paths/messages.
  ncsVersionEsc = pkgs.lib.escapeShellArg metadata.ncsVersion;
  sdkVersionEsc = pkgs.lib.escapeShellArg metadata.zephyrSdk.version;
  pythonVersionEsc = pkgs.lib.escapeShellArg metadata.python;
  python =
    pkgs.${pythonPackage}
      or (throw "west backend: unknown Python package '${pythonPackage}' for NCS ${metadata.ncsVersion}");

  useMultilib = pkgs.stdenv.isLinux && withMultilib;

  # Scoped west wrapper: workspaces resolve from HOME at runtime; the venv
  # python is never leaked into the outer environment. Bootstrap readiness
  # comes from the shell-specific backend-aware `nix-nrf bootstrap` (mutating
  # with approval when autoBootstrap = true, read-only check otherwise).
  westWrapper = pkgs.writeShellScriptBin "west" ''
    _nix_nrf=${nixNrf}/bin/nix-nrf
    _sdk_dir=${sdkPackage}
    _ncs_version=${ncsVersionEsc}
    _workspace="$HOME/ncs/$_ncs_version"

    ${
      if autoBootstrap
      then ''
        _sdk_path="$("$_nix_nrf" bootstrap --print-sdk-path)" || {
          echo "west wrapper: west workspace/bootstrap failed" >&2
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

    # .venv/bin is prepended only inside west's process tree.
    export PATH="$_workspace/.venv/bin:$PATH"
    export ZEPHYR_BASE="$_workspace/zephyr"
    export ZEPHYR_TOOLCHAIN_VARIANT=zephyr
    export ZEPHYR_SDK_INSTALL_DIR="$_sdk_dir"
    ${pkgs.lib.optionalString useMultilib ''
      # Keep multilib GCC ahead of other host gcc so native_sim -m32 builds
      # work.
      export PATH="${pkgs.gccMultiStdenv.cc}/bin:$PATH"
    ''}
    # Keep the project OpenOCD ahead of anything a runner might find.
    export PATH="${openocd}/bin:$PATH"

    exec "$_workspace/.venv/bin/west" "$@"
  '';
in
  pkgs.mkShell {
    inherit name inputsFrom;

    packages =
      [
        # Setup hook exports ZEPHYR_TOOLCHAIN_VARIANT / ZEPHYR_SDK_INSTALL_DIR.
        sdkPackage
        python
        pkgs.cmake
        pkgs.ninja
        pkgs.dtc
        pkgs.gperf
        pkgs.git
        pkgs.ccache
        pkgs.dfu-util
        pkgs.file
        pkgs.xz
        pkgs.gnumake
        pkgs.which
        westWrapper
        openocd
        nixNrf
      ]
      ++ pkgs.lib.optionals useMultilib [pkgs.gccMultiStdenv.cc]
      ++ packages;

    # The scoped wrapper and the shell hook are reachable for regression
    # gates (checks) that need to execute them directly with a synthetic
    # HOME; the bootstrap module output is likewise reachable so gates can
    # assert it installs no standalone command and only a libexec entry.
    passthru = {
      inherit westWrapper westBootstrap;
    };

    shellHook = ''
      _ncs_version=${ncsVersionEsc}
      _sdk_version=${sdkVersionEsc}
      _python_version=${pythonVersionEsc}
      _nix_nrf=${nixNrf}/bin/nix-nrf
      _workspace="$HOME/ncs/$_ncs_version"
      echo "${name} shell (backend west, NCS "$_ncs_version", Nix Zephyr SDK "$_sdk_version", Python "$_python_version", ${
        if autoBootstrap
        then "lazy bootstrap on first west"
        else "manual bootstrap (autoBootstrap = false)"
      })"
      echo "workspace: $_workspace"
      # Readiness uses the backend-aware `nix-nrf bootstrap` read-only --check
      # path: missing .west/config, requirement files, venv structure,
      # imports, or an unsatisfied west version all report not-ready. Never
      # mutates.
      if "$_nix_nrf" bootstrap --check --quiet --print-sdk-path >/dev/null 2>&1; then
        if [ -d "$_workspace/zephyr" ]; then
          export ZEPHYR_BASE="$_workspace/zephyr"
          echo "ZEPHYR_BASE: $ZEPHYR_BASE"
        fi
        echo "setup: ready"
      else
        echo "setup: not ready — run: nix-nrf bootstrap"
      fi
      ${extraShellHook}
    '';
  }
