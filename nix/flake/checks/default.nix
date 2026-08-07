# Composes the per-domain check modules into the flake's `checks` attrset.
# Every key is spelled out here; if two modules ever export the same check
# name, normal Nix attrset construction raises a duplicate-attribute error
# instead of silently overwriting one check.
{
  backendSelector,
  core,
  nrfutil,
  west,
  formatting,
  pre-commit,
}: {
  inherit (backendSelector) backend-selector;
  inherit
    (core)
    doctor-tests
    doctor-udev-wiring
    flash-recipe-tests
    nix-nrf-help
    nixos-module
    probes-tests
    udev-rules
    ;
  inherit (nrfutil) bootstrap-tests bootstrap-quoting nrfutil-shell-boundary;
  inherit
    (west)
    west-bootstrap-tests
    west-versions-tests
    west-backend-metadata
    west-backend-quoting
    west-shell-boundary
    ;
  inherit formatting pre-commit;
}
