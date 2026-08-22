# Release/changelog consistency gate: runs the real scripts/release.py
# `check` command and the tests/unit/test_release.py regression suite against
# a sandbox layout holding copies of the real release.json and CHANGELOG.md.
# Checks the strict-SemVer manifest and changelog contract
# (table row, exact current heading, `## [Unreleased]` before current,
# nonempty body), and every negative contract element. No network or
# repository mutation, pinned pkgs.python3. Fails outright when any required
# release file is absent from the flake source.
{pkgs}: let
  releaseManifest = ../../../release.json;
  changelog = ../../../CHANGELOG.md;
  releaseScript = ../../../scripts/release.py;
  testFile = ../../../tests/unit/test_release.py;
in {
  release-consistency =
    pkgs.runCommand "release-consistency-check"
    {
      nativeBuildInputs = [pkgs.python3];
      inherit
        releaseManifest
        changelog
        releaseScript
        testFile
        ;
    }
    ''
      set -eu
      # Explicit absence checks: cp would fail too, but naming the missing file
      # makes the failure deterministic and readable.
      for f in "$releaseManifest" "$changelog" "$releaseScript" "$testFile"; do
        [ -f "$f" ] || {
          echo "release-consistency check: required release file missing from flake source: $f" >&2
          exit 1
        }
      done
      # Sandbox layout mirroring the repository layout so the utility's default
      # repo-root detection (script parent's parent) and the test suite's
      # repo-root detection (parents[2]) both resolve to the copied layout.
      mkdir -p layout/scripts layout/tests/unit
      cp "$releaseManifest" layout/release.json
      cp "$changelog" layout/CHANGELOG.md
      cp "$releaseScript" layout/scripts/release.py
      chmod +x layout/scripts/release.py
      cp "$testFile" layout/tests/unit/test_release.py
      (
        cd layout
        python3 scripts/release.py check
        python3 tests/unit/test_release.py
      )
      echo "release consistency check passed" >&2
      mkdir -p "$out"
    '';
}
