# nix/west-backend/environment.nix — west backend prototype dev shell.
#
# A dedicated, explicitly-not-public shell proving the hybrid model:
#   - Nix owns the exact Zephyr SDK package (ZEPHYR_SDK_INSTALL_DIR /
#     ZEPHYR_TOOLCHAIN_VARIANT via its setup hook), Python 3.12 with venv
#     support, and the host tools (cmake, ninja, dtc, gperf, Git, ccache,
#     dfu-util, file, xz, make, which, multilib GCC);
#   - the official mutable west workspace and the version-local venv own the
#     NCS repositories and Python requirements;
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
# The scoped `west` wrapper requires the setup helper's --check to pass,
# prepends .venv/bin only inside west's process, exports ZEPHYR_BASE /
# ZEPHYR_TOOLCHAIN_VARIANT / ZEPHYR_SDK_INSTALL_DIR, keeps the project
# OpenOCD ahead of other runners, and execs the exact venv west.
#
# The shell hook is read-only: banner, workspace path, setup readiness via
# the packaged helper's read-only --check, and ZEPHYR_BASE only when ready.
# It never activates the venv globally and never runs setup/update/pip.
{
  pkgs,
  # Exact Zephyr SDK package (nix/west-backend/zephyr-sdk.nix output).
  sdkPackage,
  # Version metadata entry (versions.nix), keyed by NCS release.
  metadata,
  # Packaged setup helper (nix/nix-nrf-west-setup.nix output).
  setupHelper,
  # Wrapped project OpenOCD (kept ahead of any runner-spawned openocd).
  openocd,
  # Public CLI facade carrying the internal probes/doctor modules (the
  # flake-instantiated nix-nrf already carries the exact udev-rules path).
  nixNrf,
}:
assert pkgs.stdenv.hostPlatform.system
== "x86_64-linux"
|| throw "west backend prototype supports only x86_64-linux; got ${pkgs.stdenv.hostPlatform.system}"; let
  # Escaped metadata values; assigned to shell variables outside double
  # quotes so the shell consumes the quoting and the variables hold raw
  # values that can safely be embedded in double-quoted paths/messages.
  ncsVersionEsc = pkgs.lib.escapeShellArg metadata.ncsVersion;
  sdkVersionEsc = pkgs.lib.escapeShellArg metadata.zephyrSdk.version;
  pythonVersionEsc = pkgs.lib.escapeShellArg metadata.python;
  setupHelperExe = "${setupHelper}/libexec/nix-nrf/west-setup";

  # Scoped west wrapper: workspaces resolve from HOME at runtime; the venv
  # python is never leaked into the outer environment.
  westWrapper = pkgs.writeShellScriptBin "west" ''
    _setup=${setupHelperExe}
    _sdk_dir=${sdkPackage}
    _ncs_version=${ncsVersionEsc}
    _workspace="$HOME/ncs/$_ncs_version"

    "$_setup" --check >/dev/null 2>&1 || {
      echo "west wrapper: west workspace for NCS $_ncs_version is not set up" >&2
      echo "Run: nix-nrf-west-setup" >&2
      exit 1
    }

    # .venv/bin is prepended only inside west's process tree.
    export PATH="$_workspace/.venv/bin:$PATH"
    export ZEPHYR_BASE="$_workspace/zephyr"
    export ZEPHYR_TOOLCHAIN_VARIANT=zephyr
    export ZEPHYR_SDK_INSTALL_DIR="$_sdk_dir"
    # Keep the project OpenOCD ahead of anything a runner might find.
    export PATH="${openocd}/bin:$PATH"

    exec "$_workspace/.venv/bin/west" "$@"
  '';
in
  pkgs.mkShell {
    name = "west-prototype";

    packages = [
      # Setup hook exports ZEPHYR_TOOLCHAIN_VARIANT / ZEPHYR_SDK_INSTALL_DIR.
      sdkPackage
      pkgs.python312
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
      # Multilib GCC for native_sim -m32 host builds on x86_64 Linux.
      pkgs.gccMultiStdenv.cc
      westWrapper
      openocd
      nixNrf
      setupHelper
    ];

    # The scoped wrapper is reachable for regression gates (checks) that
    # need to execute it directly with a synthetic HOME.
    passthru.westWrapper = westWrapper;

    shellHook = ''
      _ncs_version=${ncsVersionEsc}
      _sdk_version=${sdkVersionEsc}
      _python_version=${pythonVersionEsc}
      _setup_helper=${setupHelperExe}
      _workspace="$HOME/ncs/$_ncs_version"
      echo "west-prototype shell (NCS $_ncs_version, west workspace + venv, Nix Zephyr SDK $_sdk_version, Python $_python_version)"
      echo "workspace: $_workspace"
      # Readiness uses the packaged helper's read-only --check: missing
      # .west/config, requirement files, venv structure, imports, or an
      # unsatisfied west version all report not-ready. Never mutates.
      if "$_setup_helper" --check --quiet >/dev/null 2>&1; then
        if [ -d "$_workspace/zephyr" ]; then
          export ZEPHYR_BASE="$_workspace/zephyr"
          echo "ZEPHYR_BASE: $ZEPHYR_BASE"
        fi
        echo "setup: ready"
      else
        echo "setup: not ready — run: nix-nrf-west-setup"
      fi
    '';
  }
