# Evaluation gate for the public mkNrfShell backend selector: pure Nix
# evaluation (builtins.tryEval / functionArgs), no SDK build, no network.
{
  pkgs,
  mkNrfShell,
}: let
  # Evaluation-level regression gate for the backend selector:
  # - omitted backend still equals the explicit nrfutil shell
  #   (identical derivations),
  # - omitted backend plus explicit ncsVersion evaluates,
  # - explicit "nrfutil" plus explicit ncsVersion evaluates,
  # - west + v3.3.0 evaluates,
  # - west + unknown release does not evaluate,
  # - missing ncsVersion fails evaluation (ncsVersion is required),
  # - unsupported "sdk-nrf" does not evaluate,
  # - west + non-null toolchainBundleId does not evaluate,
  # - west + non-default nrfutilPackage does not evaluate,
  # - an explicit non-null toolchainBundleId evaluates (nrfutil),
  # - omitted/explicit autoBootstrap (true/false) values evaluate for
  #   both backends,
  # - exact toolchainBundleId evaluates in either bootstrap mode.
  # Pure Nix evaluation via builtins.tryEval — builds no SDK, runs no
  # network bootstrap. Note: builtins.tryEval cannot catch "called
  # without required argument" errors, so required-ness is proven with
  # builtins.functionArgs, which marks arguments *with* a default
  # `true` (so a required argument reads `false`).
  backendSelectorCheck = let
    evaluates = expr: (builtins.tryEval (builtins.seq expr true)).success;
    ncsVersionRequired = (builtins.functionArgs mkNrfShell).ncsVersion == false;
    omittedEqualsNrfutil = let
      s1 = mkNrfShell {
        name = "backend-check-eq";
        ncsVersion = "v3.3.0";
      };
      s2 = mkNrfShell {
        name = "backend-check-eq";
        backend = "nrfutil";
        ncsVersion = "v3.3.0";
      };
    in
      s1.drvPath == s2.drvPath;
    omittedOk = evaluates (mkNrfShell {
      name = "backend-check-omitted";
      ncsVersion = "v3.3.0";
    });
    explicitOk = evaluates (mkNrfShell {
      name = "backend-check-explicit";
      backend = "nrfutil";
      ncsVersion = "v3.3.0";
    });
    westOk = evaluates (mkNrfShell {
      name = "backend-check-west";
      backend = "west";
      ncsVersion = "v3.3.0";
    });
    westUnknownRejected =
      !evaluates (mkNrfShell {
        name = "backend-check-west-unknown";
        backend = "west";
        ncsVersion = "not-a-release";
      });
    unsupportedRejected =
      !evaluates (mkNrfShell {
        name = "backend-check-unsupported";
        backend = "sdk-nrf";
        ncsVersion = "v3.3.0";
      });
    westBundleIdRejected =
      !evaluates (mkNrfShell {
        name = "backend-check-west-bundle-id";
        backend = "west";
        ncsVersion = "v3.3.0";
        toolchainBundleId = "bundle-id-check";
      });
    westNrfutilPackageRejected =
      !evaluates (mkNrfShell {
        name = "backend-check-west-nrfutil";
        backend = "west";
        ncsVersion = "v3.3.0";
        nrfutilPackage = pkgs.hello;
      });
    # Explicit `nrfutilPackage = null` must be rejected with the
    # backend-specific message (guarded before any outPath access), not
    # a null attribute/type error.
    westNullNrfutilPackageRejected =
      !evaluates (mkNrfShell {
        name = "backend-check-west-nrfutil-null";
        backend = "west";
        ncsVersion = "v3.3.0";
        nrfutilPackage = null;
      });
    westAutoOmittedOk = evaluates (mkNrfShell {
      name = "backend-check-west-auto-omitted";
      backend = "west";
      ncsVersion = "v3.3.0";
    });
    westAutoTrueOk = evaluates (mkNrfShell {
      name = "backend-check-west-auto-true";
      backend = "west";
      ncsVersion = "v3.3.0";
      autoBootstrap = true;
    });
    westAutoFalseOk = evaluates (mkNrfShell {
      name = "backend-check-west-auto-false";
      backend = "west";
      ncsVersion = "v3.3.0";
      autoBootstrap = false;
    });
    bundleIdOk = evaluates (mkNrfShell {
      name = "backend-check-bundle-id";
      ncsVersion = "v3.3.0";
      toolchainBundleId = "bundle-id-check";
    });
    autoBootstrapOmittedOk = evaluates (mkNrfShell {
      name = "bootstrap-check-omitted";
      ncsVersion = "v3.3.0";
    });
    autoBootstrapTrueOk = evaluates (mkNrfShell {
      name = "bootstrap-check-true";
      ncsVersion = "v3.3.0";
      autoBootstrap = true;
    });
    autoBootstrapFalseOk = evaluates (mkNrfShell {
      name = "bootstrap-check-false";
      ncsVersion = "v3.3.0";
      autoBootstrap = false;
    });
    bundleIdAutoTrueOk = evaluates (mkNrfShell {
      name = "bootstrap-check-bundle-true";
      ncsVersion = "v3.3.0";
      toolchainBundleId = "bundle-id-check";
      autoBootstrap = true;
    });
    bundleIdAutoFalseOk = evaluates (mkNrfShell {
      name = "bootstrap-check-bundle-false";
      ncsVersion = "v3.3.0";
      toolchainBundleId = "bundle-id-check";
      autoBootstrap = false;
    });
    pass =
      ncsVersionRequired
      && omittedEqualsNrfutil
      && omittedOk
      && explicitOk
      && westOk
      && westUnknownRejected
      && unsupportedRejected
      && westBundleIdRejected
      && westNrfutilPackageRejected
      && westNullNrfutilPackageRejected
      && westAutoOmittedOk
      && westAutoTrueOk
      && westAutoFalseOk
      && bundleIdOk
      && autoBootstrapOmittedOk
      && autoBootstrapTrueOk
      && autoBootstrapFalseOk
      && bundleIdAutoTrueOk
      && bundleIdAutoFalseOk;
  in
    pkgs.runCommand "backend-selector-check"
    {
      inherit
        ncsVersionRequired
        omittedEqualsNrfutil
        omittedOk
        explicitOk
        westOk
        westUnknownRejected
        unsupportedRejected
        westBundleIdRejected
        westNrfutilPackageRejected
        westNullNrfutilPackageRejected
        westAutoOmittedOk
        westAutoTrueOk
        westAutoFalseOk
        bundleIdOk
        autoBootstrapOmittedOk
        autoBootstrapTrueOk
        autoBootstrapFalseOk
        bundleIdAutoTrueOk
        bundleIdAutoFalseOk
        ;
    }
    (
      if pass
      then ''
        echo "backend selector check: ncsVersion required, omitted equals nrfutil, omitted+ncsVersion evaluates, nrfutil+ncsVersion evaluates, west+v3.3.0 evaluates, west unknown release rejected, sdk-nrf rejected, west toolchainBundleId rejected, west nrfutilPackage override (incl. explicit null) rejected, west autoBootstrap omitted/true/false evaluates, toolchainBundleId evaluates, autoBootstrap omitted/true/false evaluates, exact bundle in either bootstrap mode evaluates"
        mkdir -p "$out"
      ''
      else ''
        echo "backend selector check FAILED" >&2
        echo "ncsVersionRequired=$ncsVersionRequired omittedEqualsNrfutil=$omittedEqualsNrfutil omittedOk=$omittedOk explicitOk=$explicitOk westOk=$westOk westUnknownRejected=$westUnknownRejected unsupportedRejected=$unsupportedRejected westBundleIdRejected=$westBundleIdRejected westNrfutilPackageRejected=$westNrfutilPackageRejected westNullNrfutilPackageRejected=$westNullNrfutilPackageRejected westAutoOmittedOk=$westAutoOmittedOk westAutoTrueOk=$westAutoTrueOk westAutoFalseOk=$westAutoFalseOk bundleIdOk=$bundleIdOk autoBootstrapOmittedOk=$autoBootstrapOmittedOk autoBootstrapTrueOk=$autoBootstrapTrueOk autoBootstrapFalseOk=$autoBootstrapFalseOk bundleIdAutoTrueOk=$bundleIdAutoTrueOk bundleIdAutoFalseOk=$bundleIdAutoFalseOk" >&2
        exit 1
      ''
    );
in {
  backend-selector = backendSelectorCheck;
}
