# nix/init-project/default.nix. Public `nix-nrf-init-project` package.
#
# Builds a public standalone binary at $out/bin/nix-nrf-init-project, installs
# the render skeleton under $out/share/nix-nrf/init-project, patches the
# Python shebang, and wraps the script exactly once with the internal
# exact-store configuration (not caller override seams):
#
#   NIX_NRF_INIT_NRFUTIL             exact packaged nrfutil executable
#   NIX_NRF_INIT_WEST_VERSIONS_JSON  sorted JSON key list from versions.nix
#   NIX_NRF_INIT_SKELETON            exact packaged skeleton directory
#   --unset PYTHONHOME / PYTHONPATH
#
# The initializer is a separate public flake app (`apps.<system>.init-project`),
# not a `nix-nrf` subcommand; it is not packaged under $out/libexec/nix-nrf/.
# Production never resolves nrfutil from PATH. The wrapper pins the exact
# store executable. Tests substitute `nrfutilPackage` at Nix construction time
# (nix/flake/checks/init-project.nix) so the deterministic fake search script
# is the packaged nrfutil.
#
# The west supported-release list is baked from the sorted attr names of
# versions.nix (the same source of truth `nix-nrf versions` uses); the script
# source contains no release literals.
{
  pkgs,
  # Packaged nrfutil whose sdk-manager search is the nrfutil latest authority.
  nrfutilPackage,
  # versions.nix attrset keyed by NCS release; sorted attr names become the
  # JSON key list baked into the wrapper.
  westVersions,
}: let
  sortedNames = builtins.sort builtins.lessThan (builtins.attrNames westVersions);
  # Shell-escaped wrapProgram arguments, mirroring nix/lib/mk-python-command.nix
  # so values with quotes/newlines survive the generated build script.
  wrapperArgs = [
    [
      "--set"
      "NIX_NRF_INIT_NRFUTIL"
      "${nrfutilPackage}/bin/nrfutil"
    ]
    [
      "--set"
      "NIX_NRF_INIT_WEST_VERSIONS_JSON"
      (builtins.toJSON sortedNames)
    ]
    [
      "--set"
      "NIX_NRF_INIT_SKELETON"
      "${builtins.placeholder "out"}/share/nix-nrf/init-project"
    ]
    [
      "--unset"
      "PYTHONHOME"
    ]
    [
      "--unset"
      "PYTHONPATH"
    ]
  ];
  escapedArgs =
    builtins.concatMap (
      args: map (a: pkgs.lib.escapeShellArg (toString a)) args
    )
    wrapperArgs;
in
  pkgs.runCommand "nix-nrf-init-project"
  {
    nativeBuildInputs = [
      pkgs.makeWrapper
      pkgs.python3
    ];
    script = ../../bin/commands/nix-nrf-init-project;
    skeleton = ./skeleton;
  }
  ''
    install -Dm755 "$script" "$out/bin/nix-nrf-init-project"
    install -Dm644 "$skeleton/flake.nix.in" "$out/share/nix-nrf/init-project/flake.nix.in"
    install -Dm644 "$skeleton/.envrc" "$out/share/nix-nrf/init-project/.envrc"
    patchShebangs "$out/bin/nix-nrf-init-project"
    wrapProgram "$out/bin/nix-nrf-init-project" ${builtins.concatStringsSep " " escapedArgs}
  ''
