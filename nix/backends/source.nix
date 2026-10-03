# Existing sources are inspected, never provisioned by this module.
{pkgs}: {
  source,
  ncsVersion,
}: let
  workspaceMode = source.mode == "workspace";
  python = pkgs.python3.withPackages (ps: [ps.west]);
  mkPythonCommand = import ../lib/mk-python-command.nix {
    pkgs =
      pkgs
      // {
        python3 = python;
      };
  };
  resolver = mkPythonCommand {
    pname = "nix-nrf-source";
    script = ../../bin/commands/nix-nrf-source;
    destination = "source";
    wrapperArgs = [
      [
        "--unset"
        "PYTHONHOME"
      ]
      [
        "--unset"
        "PYTHONPATH"
      ]
      [
        "--prefix"
        "PATH"
        ":"
        "${pkgs.git}/bin"
      ]
      [
        "--set-default"
        "NIX_NRF_SOURCE_WORKSPACE"
        source.workspace
      ]
      [
        "--set"
        "NIX_NRF_SOURCE_NCS_VERSION"
        ncsVersion
      ]
    ];
  };
in {
  command =
    if workspaceMode
    then "${resolver}/libexec/nix-nrf/source"
    else null;
  shellHook = pkgs.lib.optionalString workspaceMode ''
    # Freeze relative configuration here, not at each later west invocation.
    export NIX_NRF_SOURCE_WORKSPACE=${pkgs.lib.escapeShellArg (source.workspace or "")}
    NIX_NRF_SOURCE_WORKSPACE="$(${resolver}/libexec/nix-nrf/source --anchor)"
    export NIX_NRF_SOURCE_WORKSPACE
    if ${resolver}/libexec/nix-nrf/source --json >/dev/null; then
      # Workspace mode keeps source discovery out of the parent environment.
      unset ZEPHYR_BASE Zephyr_DIR
      echo "source workspace: $NIX_NRF_SOURCE_WORKSPACE"
    else
      echo "Source workspace not ready; run nix-nrf source --json for details." >&2
    fi
  '';
}
