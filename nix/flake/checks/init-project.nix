# Dynamic project initializer gate: runs tests/unit/test_nix_nrf_init_project.py
# twice with sandboxed Python stdlib. One run uses the raw repository script
# (standalone), and one uses the packaged public binary constructed with a
# deterministic fake nrfutil (tests/fixtures/nrfutil-search.py) as
# `nrfutilPackage` and the real west metadata. Proves CLI contract, version
# resolution (semantic max, schema validation, offline explicit paths, west
# metadata constraint), filesystem safety (collisions, symlink escapes,
# exclusive create, atomic renameat2), and the exact generated file set. It uses no
# network, real nrfutil, sdk-manager state, or SDK/toolchain download.
{
  pkgs,
  # Real west backend version metadata (nix/backends/west/versions.nix); its
  # sorted key list is baked into the packaged initializer.
  westBackendVersions,
}: let
  initProjectBuilder = import ../../init-project/default.nix;

  # Test-only fake nrfutil package: the deterministic search fixture installed
  # as $out/bin/nrfutil with the shebang patched to the sandbox Python. Driven
  # by the test-only environment variables documented in the fixture; the
  # production packaging seam (nrfutilPackage) is unchanged.
  fakeNrfutil =
    pkgs.runCommand "fake-nrfutil-search"
    {
      nativeBuildInputs = [pkgs.python3];
    }
    ''
      mkdir -p "$out/bin"
      install -m755 ${../../../tests/fixtures/nrfutil-search.py} "$out/bin/nrfutil"
      patchShebangs "$out/bin/nrfutil"
    '';

  # Packaged public initializer: same exact-store wiring production uses, with
  # the fake as nrfutilPackage and the real west metadata.
  initProject = initProjectBuilder {
    inherit pkgs;
    nrfutilPackage = fakeNrfutil;
    westVersions = westBackendVersions;
  };

  westVersionsJson = builtins.toJSON (
    builtins.sort builtins.lessThan (builtins.attrNames westBackendVersions)
  );
in {
  init-project-tests =
    pkgs.runCommand "init-project-tests"
    {
      nativeBuildInputs = [pkgs.python3];
      initScript = ../../../bin/commands/nix-nrf-init-project;
      testFile = ../../../tests/unit/test_nix_nrf_init_project.py;
      fixture = ../../../tests/fixtures/nrfutil-search.py;
      skeletonSrc = ../../../nix/init-project/skeleton;
      inherit initProject fakeNrfutil westVersionsJson;
    }
    ''
      set -eu
      cp "$initScript" nix-nrf-init-project
      chmod +x nix-nrf-init-project
      cp "$testFile" test_nix_nrf_init_project.py
      cp "$fixture" nrfutil-search.py

      # Raw source standalone: the suite runs the raw script through the
      # current interpreter and constructs its own fake nrfutil from the
      # fixture.
      export NIX_NRF_INIT_PROJECT_SCRIPT="$PWD/nix-nrf-init-project"
      export NIX_NRF_INIT_TEST_FIXTURE="$PWD/nrfutil-search.py"
      export NIX_NRF_INIT_TEST_SKELETON="$skeletonSrc"
      export NIX_NRF_INIT_TEST_WEST_VERSIONS_JSON='["v3.3.0","v3.3.4","v3.4.0-rc1","v2.7.0"]'
      python3 test_nix_nrf_init_project.py

      # Packaged initializer: same suite against the packaged public binary
      # with the fake as nrfutilPackage and the real west metadata baked in.
      export NIX_NRF_INIT_PROJECT_COMMAND="$initProject/bin/nix-nrf-init-project"
      unset NIX_NRF_INIT_PROJECT_SCRIPT NIX_NRF_INIT_TEST_FIXTURE NIX_NRF_INIT_TEST_SKELETON
      export NIX_NRF_INIT_TEST_WEST_VERSIONS_JSON="$westVersionsJson"
      python3 test_nix_nrf_init_project.py

      echo "init-project tests passed" >&2
      mkdir -p "$out"
    '';
}
