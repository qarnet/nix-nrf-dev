# nix/release.nix. nix-nrf-dev project version loader.
#
# The nix-nrf-dev/nix-nrf product/package version is INDEPENDENT from Nordic
# NCS versions: `release.json` holds the one canonical strict stable SemVer
# (`MAJOR.MINOR.PATCH`, no leading `v`, no prerelease/build metadata), while
# `ncsVersion = "v3.3.0"` remains an upstream SDK selection and tested
# baseline. No version literal is duplicated in Nix source: production code
# (the `nix-nrf` dispatcher), checks, and the release tooling all read this
# single manifest.
#
# The manifest must be a JSON object with EXACTLY the `version` key so no
# second release authority can appear silently. Malformed shape/version
# throws a clear `nix-nrf release manifest: ...` evaluation error.
let
  raw = builtins.readFile ../release.json;
  parsed = builtins.fromJSON raw;
  # Exactly one key, named `version` (attrNames comparison is order- and
  # set-exact). Short-circuit guards the non-attrs case before attrNames.
  validShape = builtins.isAttrs parsed && builtins.attrNames parsed == ["version"];
  # Strict stable SemVer, full match only (decimal digits, dots). Guarded
  # by validShape plus the isString check below before builtins.match runs.
  validVersion =
    validShape
    && builtins.isString parsed.version
    && builtins.match "[0-9]+[.][0-9]+[.][0-9]+" parsed.version != null;
in
  if !validShape
  then throw "nix-nrf release manifest: release.json must be a JSON object with exactly the \"version\" key"
  else if !(builtins.isString parsed.version)
  then throw "nix-nrf release manifest: version must be a string"
  else if !validVersion
  then throw "nix-nrf release manifest: version \"${parsed.version}\" is not strict stable SemVer (MAJOR.MINOR.PATCH, no leading v, no prerelease/build metadata)"
  else {
    inherit (parsed) version;
  }
