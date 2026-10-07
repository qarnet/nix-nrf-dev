#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Check selected requirement roots against this interpreter's distributions.

Runs under the selected workspace Python, not the bootstrap interpreter. Reads
local requirement files only; never installs packages or contacts an index.
"""

import importlib.metadata as metadata
import json
from pathlib import Path
import shlex
import sys

from packaging.requirements import Requirement


def check_requirements(root, paths):
    """Return missing/version errors; reject escaping or excessively deep includes."""
    root = Path(root).resolve()
    seen = set()
    errors = []

    def check_file(path, depth=0):
        path = Path(path).resolve()
        if not path.is_relative_to(root) or depth > 16:
            raise ValueError(
                "requirement include escapes workspace or exceeds depth limit"
            )
        if path in seen:
            return
        seen.add(path)
        for raw in path.read_text().splitlines():
            line = raw.strip().split(" #", 1)[0]
            if not line or line.startswith("#"):
                continue
            if line.startswith(("-r ", "--requirement ", "--requirement=")):
                included = (
                    line.split("=", 1)[1]
                    if line.startswith("--requirement=")
                    else shlex.split(line)[1]
                )
                check_file(path.parent / included, depth + 1)
                continue
            if line.startswith(
                ("--index-url", "--extra-index-url", "--find-links", "--trusted-host")
            ):
                continue
            requirement = Requirement(line)
            if requirement.marker and not requirement.marker.evaluate():
                continue
            try:
                installed = metadata.version(requirement.name)
            except metadata.PackageNotFoundError:
                errors.append(
                    f"{requirement.name}: not installed (requested by {path})"
                )
                continue
            if requirement.specifier and not requirement.specifier.contains(
                installed, prereleases=True
            ):
                errors.append(
                    f"{requirement.name}: installed {installed}, requires {requirement.specifier}"
                )

    for path in paths:
        check_file(path)
    return errors


def main():
    errors = check_requirements(sys.argv[1], json.loads(sys.argv[2]))
    if errors:
        print("\n".join(errors))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
