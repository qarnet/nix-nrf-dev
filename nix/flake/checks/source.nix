{
  pkgs,
  mkNrfShell,
}: let
  nrfutilSupported =
    builtins.elem "nrfutil"
    (import ../../platforms.nix).${pkgs.stdenv.hostPlatform.system}.backends;
  python = pkgs.python3.withPackages (ps: [ps.west]);
  fakeNrfutil = pkgs.writeShellScriptBin "nrfutil" ''
    exec ${python}/bin/python3 ${../../../tests/fixtures/source-toolchain.py} "$@"
  '';
  options = {
    ncsVersion = "v3.4.1";
    autoBootstrap = false;
    withMultilib = false;
    source = {
      mode = "workspace";
      workspace = ".";
    };
  };
  nrf = mkNrfShell (options // {nrfutilPackage = fakeNrfutil;});
  west = mkNrfShell (options // {backend = "west";});
  westGroup = mkNrfShell (
    options
    // {
      backend = "west";
      pythonRequirementGroups = ["ncs-ci"];
    }
  );
  requirementPython = pkgs.python3.withPackages (ps: [
    ps.west
    ps.pip
    ps.pyelftools
    ps.pyusb
    ps.natsort
  ]);
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
    {
      backend = "nrfutil";
      pythonEnvironment = ".venv";
    }
  ];
  invalidRejected =
    builtins.all (
      extra: !(builtins.tryEval (mkNrfShell (options // {backend = "west";} // extra)).drvPath).success
    )
    invalid;
in {
  nordic-artifact-catalog-tests =
    pkgs.runCommand "nordic-artifact-catalog-tests"
    {
      nativeBuildInputs = [pkgs.python3];
      NORDIC_ARTIFACT_CATALOG_SCRIPT = ../../../scripts/nordic_artifact_catalog.py;
    }
    ''
      python3 -B ${../../../tests/unit/test_nordic_artifact_catalog.py} -v
      touch "$out"
    '';
  ci-partition-tests =
    pkgs.runCommand "ci-partition-tests"
    {
      nativeBuildInputs = [(pkgs.python3.withPackages (ps: [ps.pyyaml]))];
      CI_PARTITION_SCRIPT = ../../../scripts/ci.py;
      CI_WORKFLOW = ../../../.github/workflows/ci.yml;
    }
    ''
      python3 ${../../../tests/unit/test_ci_partition.py} -v
      touch "$out"
    '';
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
      SOURCE_NRF_HOOK =
        if nrfutilSupported
        then pkgs.writeText "nrf-source-shell-hook" nrf.shellHook
        else "";
      SOURCE_WEST_HOOK = pkgs.writeText "west-source-shell-hook" west.shellHook;
      SOURCE_NRF_PATH =
        if nrfutilSupported
        then pathFor nrf
        else "";
      SOURCE_TEST_BACKENDS =
        if nrfutilSupported
        then "nrf west"
        else "west";
      SOURCE_WEST_PATH = pathFor west;
      SOURCE_WEST_GROUP_HOOK = pkgs.writeText "west-group-source-shell-hook" westGroup.shellHook;
      SOURCE_WEST_GROUP_PATH = pathFor westGroup;
      SOURCE_REQUIREMENT_PYTHON = "${requirementPython}/bin/python3";
      SOURCE_WEST_ALT_HOOK = pkgs.writeText "west-alt-source-shell-hook" westAlt.shellHook;
      SOURCE_WEST_ALT_PATH = pathFor westAlt;
      SOURCE_MATRIX_SCRIPT = "${../../../tests/application-types}/run.py";
      SOURCE_REAL_TOOLS = "${python}/bin";
    }
    ''
      ${pkgs.lib.optionalString (!invalidRejected) ''echo "invalid source options were accepted" >&2; exit 1''}
      python3 ${../../../tests/unit/test_source_workspace.py} -v
      touch "$out"
    '';
}
