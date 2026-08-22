#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
#
# Parses and validates nix-nrf-dev release metadata.
#
# The nix-nrf-dev project version is independent from Nordic NCS versions:
# release.json (repo root) holds the only strict stable SemVer
# (MAJOR.MINOR.PATCH, no leading `v`, no prerelease/build metadata), and
# CHANGELOG.md must carry a matching table row and release body. This
# utility owns that parsing; the Nix flake gate, the direct CI gate, and the
# trusted-main release workflow all run it. Python stdlib only, no network.
#
# Commands:
#   python3 scripts/release.py check              validate manifest + changelog
#   python3 scripts/release.py version            print only the version
#   python3 scripts/release.py notes --output P   write only the current body
#
# Repository root defaults to the script's parent repository (scripts/ -> ..).
# Pure functions accept explicit manifest/changelog text so the test suite can
# exercise every contract element without touching the real files.

import argparse
import json
import pathlib
import re
import sys

STRICT_SEMVER_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
UNRELEASED_HEADING = "## [Unreleased]"


def repo_root() -> pathlib.Path:
    """The repository root: the parent of this script's directory."""
    return pathlib.Path(__file__).resolve().parents[1]


def load_release_json(text):
    """Parse manifest text into (version | None, diagnostics).

    Diagnostics name every shape/version violation found. Returns None as
    the version whenever the manifest cannot yield a valid stable SemVer.
    """
    diags = []
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        diags.append("release.json: malformed JSON: {0}".format(exc))
        return None, diags
    if not isinstance(data, dict):
        diags.append("release.json: top-level value must be a JSON object")
        return None, diags
    keys = sorted(data.keys())
    if keys != ["version"]:
        diags.append(
            'release.json: must be a JSON object with exactly the "version" '
            "key (got: {0})".format(", ".join(keys) if keys else "no keys")
        )
        return None, diags
    version = data["version"]
    if not isinstance(version, str):
        diags.append(
            "release.json: version must be a string (got {0})".format(
                type(version).__name__
            )
        )
        return None, diags
    if not STRICT_SEMVER_RE.match(version):
        diags.append(
            "release.json: version {0!r} is not strict stable SemVer "
            "(MAJOR.MINOR.PATCH, no leading v, no prerelease/build metadata)".format(
                version
            )
        )
        return None, diags
    return version, diags


def _heading_line_starts(text):
    """Char offsets where level-2 heading lines (`##` followed by whitespace
    at line start) begin. Level-3 (`### ...`) lines are not headings."""
    offsets = []
    pos = 0
    for line in text.splitlines(keepends=True):
        if re.match(r"^##\s", line):
            offsets.append(pos)
        pos += len(line)
    return offsets


def _heading_start(text, heading):
    """Char offset of the first line whose content is EXACTLY `heading`
    (whole line, no suffix), or -1 when absent. A `## [0.1.0] extra` line
    does not match the `## [0.1.0]` heading."""
    for offset in _heading_line_starts(text):
        end = text.find("\n", offset)
        line = text[offset:end] if end != -1 else text[offset:]
        if line == heading:
            return offset
    return -1


def current_release_body(text, version):
    """Content after the exact current heading line until the next level-2
    heading line. Level-3 (`### ...`) headings do not terminate the body.
    Returns None when the exact heading line is absent."""
    heading = "## [{0}]".format(version)
    idx = _heading_start(text, heading)
    if idx == -1:
        return None
    rest = text[idx:]
    nl = rest.find("\n")
    rest = rest[nl + 1 :] if nl != -1 else ""
    lines = []
    for line in rest.splitlines(keepends=True):
        if re.match(r"^##\s", line):
            break
        lines.append(line)
    return "".join(lines)


def check_changelog_contract(text, version):
    """Validate every changelog contract element; return a diagnostic list.

    Independent rules so a single defect is named precisely: current-version
    table row, exact current body heading line, exact `## [Unreleased]`
    heading line, Unreleased-before-current ordering, and a nonempty current
    release body. Heading recognition is whole-line: a suffixed
    `## [0.1.0] extra` line is NOT the `## [0.1.0]` heading.
    """
    diags = []
    heading = "## [{0}]".format(version)
    table_row = "| [{0}](#{1}) |".format(version, version.replace(".", ""))
    if table_row not in text:
        diags.append(
            "CHANGELOG release table must contain a row starting with "
            "{0!r} for version {1!r}".format(table_row, version)
        )
    heading_start = _heading_start(text, heading)
    unreleased_start = _heading_start(text, UNRELEASED_HEADING)
    if heading_start == -1:
        diags.append(
            'CHANGELOG body must contain the exact heading "{0}"'.format(heading)
        )
    if unreleased_start == -1:
        diags.append(
            'CHANGELOG body must contain the heading "{0}"'.format(UNRELEASED_HEADING)
        )
    if heading_start != -1 and unreleased_start != -1:
        if unreleased_start > heading_start:
            diags.append(
                'the "{0}" heading must appear before the "{1}" heading'.format(
                    UNRELEASED_HEADING, heading
                )
            )
    if heading_start != -1:
        body = current_release_body(text, version)
        if body is None or not body.strip():
            diags.append('CHANGELOG body after "{0}" must be nonempty'.format(heading))
    return diags


def collect_errors(manifest_text, changelog_text):
    """All manifest + changelog contract violations in deterministic order."""
    errors = []
    version, manifest_diags = load_release_json(manifest_text)
    errors.extend(manifest_diags)
    if version is None:
        return errors
    errors.extend(check_changelog_contract(changelog_text, version))
    return errors


def read_repo_file(rel):
    """Read a repository file, producing a clear diagnostic on failure."""
    path = repo_root() / rel
    try:
        return path.read_text()
    except OSError as exc:
        sys.stderr.write(
            "release consistency: cannot read {0}: {1}\n".format(path, exc)
        )
        sys.exit(1)


def validate_repo():
    """Validate the real repository files; returns the version or exits 1."""
    manifest_text = read_repo_file("release.json")
    changelog_text = read_repo_file("CHANGELOG.md")
    errors = collect_errors(manifest_text, changelog_text)
    if errors:
        for error in errors:
            sys.stderr.write("release consistency: {0}\n".format(error))
        sys.exit(1)
    version, _ = load_release_json(manifest_text)
    return version


def cmd_check(_args):
    validate_repo()
    return 0


def cmd_version(_args):
    version = validate_repo()
    sys.stdout.write("{0}\n".format(version))
    return 0


def cmd_notes(args):
    version = validate_repo()
    changelog_text = read_repo_file("CHANGELOG.md")
    body = current_release_body(changelog_text, version)
    if body is None:
        sys.stderr.write(
            'release consistency: CHANGELOG body after "## [{0}]" not found\n'.format(
                version
            )
        )
        return 1
    notes = body.strip() + "\n"
    out = pathlib.Path(args.output)
    if out.exists():
        sys.stderr.write(
            "release consistency: refusing to overwrite existing {0}\n".format(out)
        )
        return 1
    try:
        out.write_text(notes)
    except OSError as exc:
        sys.stderr.write(
            "release consistency: cannot write {0}: {1}\n".format(out, exc)
        )
        return 1
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="release.py",
        description="nix-nrf-dev release manifest/changelog validation",
    )
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("check", help="validate release.json + CHANGELOG.md")
    sub.add_parser("version", help="print only the project version")
    notes = sub.add_parser("notes", help="write only the current release body")
    notes.add_argument("--output", required=True, help="output file path")
    args = parser.parse_args(argv)
    try:
        if args.command == "check":
            return cmd_check(args)
        if args.command == "version":
            return cmd_version(args)
        if args.command == "notes":
            return cmd_notes(args)
    except BrokenPipeError:
        return 1
    return 1


if __name__ == "__main__":
    sys.exit(main())
