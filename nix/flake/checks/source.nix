{
  pkgs,
  mkNrfShell,
}: let
  python = pkgs.python3.withPackages (ps: [ps.west]);
  fakeNrfutil = pkgs.writeShellScriptBin "nrfutil" ''
    exec ${python}/bin/python3 ${../../../tests/fixtures/source-toolchain.py} "$@"
  '';
  options = {
    ncsVersion = "v3.3.0";
    autoBootstrap = false;
    withMultilib = false;
    source = {
      mode = "workspace";
      workspace = ".";
    };
  };
  nrf = mkNrfShell (options // {nrfutilPackage = fakeNrfutil;});
  west = mkNrfShell (options // {backend = "west";});
  westAlt = mkNrfShell (
    options
    // {
      backend = "west";
      pythonEnvironment = ".python-env";
    }
  );
  pathFor = shell:
    pkgs.lib.makeBinPath (
      shell.nativeBuildInputs
      ++ shell.buildInputs
      ++ [
        pkgs.bash
        pkgs.cmake
        pkgs.ninja
        pkgs.gnumake
        pkgs.coreutils
      ]
    );
  invalid = [
    {source = {};}
    {
      source = {
        mode = "wrong";
      };
    }
    {
      source = {
        mode = "workspace";
      };
    }
    {
      source = {
        mode = "workspace";
        workspace = ../.;
      };
    }
    {
      source = {
        mode = "managed";
        workspace = ".";
      };
    }
    {
      source = {
        mode = "workspace";
        workspace = ".";
        typo = true;
      };
    }
    {pythonEnvironment = ".venv";}
  ];
  invalidRejected =
    builtins.all (
      extra: !(builtins.tryEval (mkNrfShell (options // extra)).drvPath).success
    )
    invalid;
in {
  local-sdk-fixture-tests =
    pkgs.runCommand "local-sdk-fixture-tests"
    {
      nativeBuildInputs = [
        python
        pkgs.git
      ];
      LOCAL_FIXTURE_HELPERS = ../../../tests/application-types;
      LOCAL_APPLICATION_FIXTURE = ../../../tests/firmware/workspace-import-fixture;
      PYTHONDONTWRITEBYTECODE = "1";
      WEST_CONFIG_GLOBAL = "/dev/null";
      WEST_CONFIG_SYSTEM = "/dev/null";
      GIT_CONFIG_GLOBAL = "/dev/null";
      GIT_CONFIG_NOSYSTEM = "1";
    }
    ''
      python3 ${../../../tests/unit/test_local_sdk_fixture.py} -v
      touch "$out"
    '';
  source-workspace-tests =
    pkgs.runCommand "source-workspace-tests"
    {
      nativeBuildInputs = [
        pkgs.python3
        pkgs.git
        pkgs.bash
        pkgs.cmake
      ];
      SOURCE_NRF_HOOK = pkgs.writeText "nrf-source-shell-hook" nrf.shellHook;
      SOURCE_WEST_HOOK = pkgs.writeText "west-source-shell-hook" west.shellHook;
      SOURCE_NRF_PATH = pathFor nrf;
      SOURCE_WEST_PATH = pathFor west;
      SOURCE_WEST_ALT_HOOK = pkgs.writeText "west-alt-source-shell-hook" westAlt.shellHook;
      SOURCE_WEST_ALT_PATH = pathFor westAlt;
      SOURCE_MATRIX_SCRIPT = ../../../tests/application-types/run.py;
      SOURCE_REAL_TOOLS = "${python}/bin";
    }
    ''
      ${pkgs.lib.optionalString (!invalidRejected) ''echo "invalid source options were accepted" >&2; exit 1''}
      python3 ${../../../tests/unit/test_source_workspace.py} -v
      touch "$out"
    '';
}
