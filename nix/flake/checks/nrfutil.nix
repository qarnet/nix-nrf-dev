# nrfutil-backend regression gates: fake-boundary bootstrap lifecycle tests
# and the bootstrap wrapper quoting round-trip. Comments moved verbatim with
# the implementations.
{
  pkgs,
  nrfutil,
}: let
  # Fake-boundary bootstrap test gate: runs
  # tests/unit/test_nix_nrf_bootstrap.py against a temporary fake
  # nrfutil executable/state directory with sandboxed Python stdlib.
  # Proves every lifecycle branch — ready selection, --check, approval,
  # install matrix, exact-bundle behavior, malformed state, failed and
  # incomplete installs, missing version — with no network, no real SDK,
  # and no real nrfutil state.
  bootstrapTests =
    pkgs.runCommand "nix-nrf-bootstrap-tests"
    {
      nativeBuildInputs = [pkgs.python3];
      bootstrapScript = ../../../bin/backends/nrfutil/nix-nrf-bootstrap;
      testFile = ../../../tests/unit/test_nix_nrf_bootstrap.py;
    }
    ''
      cp "$bootstrapScript" nix-nrf-bootstrap
      chmod +x nix-nrf-bootstrap
      cp "$testFile" test_nix_nrf_bootstrap.py
      NIX_NRF_BOOTSTRAP_SCRIPT="$PWD/nix-nrf-bootstrap" python3 test_nix_nrf_bootstrap.py
      echo "bootstrap tests passed" >&2
      mkdir -p "$out"
    '';

  # Shell-quoting regression for the internal bootstrap module:
  # instantiate and build nix/backends/nrfutil/bootstrap.nix with caller
  # selector values containing spaces and single/double quotes,
  # proving wrapProgram generation succeeds without shell injection
  # or syntax break, then round-trip the generated wrapper's exports
  # to prove the exact values — and the exact selected nrfutil store
  # path — survive.
  bootstrapQuotingCheck = let
    nastyNcsVersion = "v3.3.0 with space 'and quote'";
    nastyBundleId = "bundle \"with\" 'quotes' and spaces";
    module = import ../../backends/nrfutil/bootstrap.nix {
      inherit pkgs;
      nrfutilPackage = nrfutil;
      ncsVersion = nastyNcsVersion;
      toolchainBundleId = nastyBundleId;
    };
  in
    pkgs.runCommand "nix-nrf-bootstrap-quoting-check"
    {
      inherit module;
      expectedNcsVersion = nastyNcsVersion;
      expectedBundleId = nastyBundleId;
      expectedNrfutil = "${nrfutil}/bin/nrfutil";
    }
    ''
      wrapper="$module/libexec/nix-nrf/bootstrap"
      eval "$(grep -E '^export NIX_NRF_(NRFUTIL|NCS_VERSION|TOOLCHAIN_BUNDLE_ID)=' "$wrapper")"
      [ "$NIX_NRF_NCS_VERSION" = "$expectedNcsVersion" ] || {
        echo "NCS_VERSION mismatch: '$NIX_NRF_NCS_VERSION' != '$expectedNcsVersion'" >&2
        exit 1
      }
      [ "$NIX_NRF_TOOLCHAIN_BUNDLE_ID" = "$expectedBundleId" ] || {
        echo "TOOLCHAIN_BUNDLE_ID mismatch: '$NIX_NRF_TOOLCHAIN_BUNDLE_ID' != '$expectedBundleId'" >&2
        exit 1
      }
      [ "$NIX_NRF_NRFUTIL" = "$expectedNrfutil" ] || {
        echo "NRFUTIL mismatch: '$NIX_NRF_NRFUTIL' != '$expectedNrfutil'" >&2
        exit 1
      }
      "$wrapper" --help >/dev/null
      echo "bootstrap quoting check passed" >&2
      mkdir -p "$out"
    '';
in {
  bootstrap-tests = bootstrapTests;
  bootstrap-quoting = bootstrapQuotingCheck;
}
