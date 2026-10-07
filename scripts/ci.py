#!/usr/bin/env python3
"""Run shared source gates once and all other checks on each native host."""

import argparse
import json
import subprocess

SHARED_CHECKS = frozenset({"formatting", "pre-commit", "release-consistency"})


def select_checks(names, phase):
    names = set(names)
    missing = SHARED_CHECKS - names
    if missing:
        raise ValueError("missing shared gates: " + ", ".join(sorted(missing)))
    if phase == "shared":
        return sorted(SHARED_CHECKS)
    if phase == "native":
        return sorted(names - SHARED_CHECKS)
    raise ValueError("unknown CI phase: " + phase)


def capture(*command):
    return subprocess.check_output(command, text=True).strip()


def run(*command):
    print("+ " + " ".join(command), flush=True)
    subprocess.run(command, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=["shared", "native", "packages"])
    parser.add_argument("--system")
    args = parser.parse_args()
    system = capture(
        "nix", "eval", "--impure", "--raw", "--expr", "builtins.currentSystem"
    )
    if args.system and args.system != system:
        parser.error(f"native system {system} does not match {args.system}")
    if args.phase == "packages":
        names = json.loads(
            capture(
                "nix",
                "eval",
                "--json",
                f".#packages.{system}",
                "--apply",
                "builtins.attrNames",
            )
        )
        run(
            "nix",
            "build",
            "-L",
            "--no-link",
            *(f".#packages.{system}.{n}" for n in names if n != "default"),
        )
        return
    if args.phase == "shared":
        hosts = json.loads(
            capture("nix", "eval", "--json", ".#lib", "--apply", "builtins.attrNames")
        )
        if hosts != ["aarch64-linux", "x86_64-linux"]:
            parser.error("published hosts do not match supported systems")
        for host in hosts:
            capture("nix", "eval", "--raw", f".#devShells.{host}.product.drvPath")
        run("nix", "flake", "check", "--all-systems", "--no-build", "-L")
    names = json.loads(
        capture(
            "nix",
            "eval",
            "--json",
            f".#checks.{system}",
            "--apply",
            "builtins.attrNames",
        )
    )
    run(
        "nix",
        "build",
        "-L",
        "--no-link",
        *(f".#checks.{system}.{n}" for n in select_checks(names, args.phase)),
    )


if __name__ == "__main__":
    main()
