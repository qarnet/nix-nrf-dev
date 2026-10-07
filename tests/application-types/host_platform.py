"""Resolve native qualification coverage from the repository's host policy."""

import json
import os
import subprocess


def native_host(repo):
    expression = """let
      system = builtins.currentSystem;
      platforms = import ((builtins.getEnv "SOURCE_MATRIX_REPO") + "/nix/platforms.nix");
    in { inherit system; backends = platforms.${system}.backends; }"""
    return json.loads(
        subprocess.check_output(
            ["nix", "eval", "--impure", "--json", "--expr", expression],
            cwd=repo,
            env=dict(os.environ, SOURCE_MATRIX_REPO=str(repo)),
            text=True,
            timeout=120,
        )
    )
