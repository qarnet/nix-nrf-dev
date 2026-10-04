{
  pkgs,
  openocd,
  nix-nrf,
}: {
  debug-fixture-tests =
    pkgs.runCommand "nix-nrf-debug-fixture-tests"
    {
      nativeBuildInputs = [
        pkgs.stdenv.cc
        (pkgs.python3.withPackages (ps: [ps.pyelftools]))
      ];
    }
    ''
      cc -std=c11 -Wall -Wextra -Werror -I${../../../tests/firmware/debug-fixture/src} \
        ${../../../tests/fixtures/fixture-wire.c} -o fixture-encoder
      export FIXTURE_ENCODER="$PWD/fixture-encoder"
      export FIXTURE_HARNESS=${../../../tests/hardware/debug}
      python3 ${../../../tests/unit/test_debug_fixture.py} -v
      touch "$out"
    '';
  session-tests =
    pkgs.runCommand "nix-nrf-session-tests"
    {
      nativeBuildInputs = [pkgs.python3];
    }
    ''
      cp -r ${../../../tests/fixtures} fixtures
      chmod -R u+w fixtures
      chmod +x fixtures/session-*.py
      patchShebangs fixtures/session-*.py
      export SESSION_SCRIPT=${../../../bin/commands/nix-nrf-session}
      export SESSION_FIXTURES="$PWD/fixtures"
      export REAL_OPENOCD=${openocd}/bin/openocd
      python3 ${../../../tests/unit/test_nix_nrf_session.py} -v
      ${nix-nrf}/bin/nix-nrf help session
      ${nix-nrf}/bin/nix-nrf session start --help
      touch "$out"
    '';
}
