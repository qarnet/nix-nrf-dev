#!/usr/bin/env python3
"""Opt-in, no-bootstrap firmware build matrix for an existing NCS workspace."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from typing import Any

from host_platform import native_host


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--approve-build",
        action="store_true",
        help="approve builds into a new output directory; never provisions tools/sources",
    )
    parser.add_argument("--backend", choices=("nrfutil", "west"), required=True)
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--workspace-app", type=Path, required=True)
    parser.add_argument("--freestanding-app", type=Path, required=True)
    parser.add_argument("--ncs-version", default="v3.4.1")
    parser.add_argument("--python-environment", default="")
    parser.add_argument("--board", default="xiao_nrf54l15/nrf54l15/cpuapp")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not args.approve_build:
        parser.error(
            "--approve-build required; this creates build artifacts but never downloads SDK sources/toolchains or flashes"
        )
    if args.python_environment and args.backend != "west":
        parser.error("--python-environment requires backend west")
    workspace = args.workspace.resolve()
    workspace_app = args.workspace_app.resolve()
    free_app = args.freestanding_app.resolve()
    if not workspace_app.is_relative_to(workspace) or free_app.is_relative_to(
        workspace
    ):
        parser.error(
            "workspace application must be inside the workspace; freestanding application must be outside it"
        )
    repo = Path(__file__).resolve().parents[2]
    host = native_host(repo)
    if args.backend not in host["backends"]:
        parser.error(
            f"backend {args.backend} unavailable on {host['system']}; use west"
        )
    output = args.output.resolve()
    output.mkdir(mode=0o700, parents=False, exist_ok=False)
    env = dict(
        os.environ,
        SOURCE_MATRIX_REPO=str(repo),
        SOURCE_MATRIX_WORKSPACE=str(workspace),
        SOURCE_MATRIX_BACKEND=args.backend,
        SOURCE_MATRIX_VERSION=args.ncs_version,
        SOURCE_MATRIX_PYTHON=args.python_environment,
    )
    # Runtime strings are read through getEnv, never interpolated into Nix code.
    expression = """(builtins.getFlake (builtins.getEnv "SOURCE_MATRIX_REPO")).lib.${builtins.currentSystem}.mkNrfShell {
      backend = builtins.getEnv "SOURCE_MATRIX_BACKEND";
      ncsVersion = builtins.getEnv "SOURCE_MATRIX_VERSION";
      autoBootstrap = false;
      source = { mode = "workspace"; workspace = builtins.getEnv "SOURCE_MATRIX_WORKSPACE"; };
      pythonEnvironment = let p = builtins.getEnv "SOURCE_MATRIX_PYTHON"; in if p == "" then null else p;
    }"""
    prefix = ["nix", "develop", "--impure", "--expr", expression, "-c"]
    report: dict[str, Any] = dict(
        outcome="failed",
        host=host["system"],
        backend=args.backend,
        board=args.board,
        cases=[],
        commands=[],
    )

    def run(command, name):
        report["commands"].append(command)
        with (output / f"{name}.log").open("w") as log:
            result = subprocess.run(
                command,
                cwd=repo,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=log,
            )
            log.write(result.stdout)
        return result

    try:
        discovered = run([*prefix, "nix-nrf", "source", "--json"], "source")
        if discovered.returncode:
            raise RuntimeError("source discovery failed; see source.log")
        source = json.loads(discovered.stdout.splitlines()[-1])
        report["source"] = source
        zephyr = Path(source["zephyr_base"])
        nrf = Path(source["nrf_base"])
        if workspace_app.is_relative_to(zephyr) or workspace_app.is_relative_to(nrf):
            raise RuntimeError(
                "workspace application must be outside Zephyr/Nordic source repositories"
            )
        ready = run([*prefix, "nix-nrf", "bootstrap", "--check"], "readiness")
        if ready.returncode:
            report["outcome"] = "blocked"
            raise RuntimeError(
                "tools/Python environment unavailable; see readiness.log; no provisioning attempted"
            )
        applications = (
            ("zephyr-repository", zephyr / "samples/hello_world"),
            ("ncs-repository", nrf / "samples/basic/empty"),
            ("workspace", workspace_app),
            ("freestanding", free_app),
        )
        for name, app in applications:
            if not (app / "CMakeLists.txt").is_file():
                raise RuntimeError(f"missing application: {app}")
            for sysbuild in (False, True):
                case_name = name + ("-sysbuild" if sysbuild else "-single")
                build = output / case_name
                result = run(
                    [
                        *prefix,
                        "west",
                        "build",
                        "--sysbuild" if sysbuild else "--no-sysbuild",
                        "-b",
                        args.board,
                        "-d",
                        str(build),
                        str(app),
                    ],
                    case_name,
                )
                case: dict[str, Any] = dict(
                    name=case_name, application=str(app), returncode=result.returncode
                )
                report["cases"].append(case)
                if result.returncode:
                    raise RuntimeError(f"build failed: {case_name}; see matching log")
                caches = [build / "CMakeCache.txt", *build.glob("*/CMakeCache.txt")]
                selected = []
                for cache in caches:
                    if not cache.is_file():
                        continue
                    values = {}
                    for line in cache.read_text().splitlines():
                        key, sep, value = line.partition("=")
                        name_key = key.split(":", 1)[0]
                        if sep and (
                            name_key
                            in (
                                "ZEPHYR_BASE",
                                "ZEPHYR_SDK_INSTALL_DIR",
                                "CMAKE_C_COMPILER",
                                "WEST_PYTHON",
                            )
                            or name_key.endswith("_MODULE_DIR")
                        ):
                            values[name_key] = value
                    selected.append(dict(cache=str(cache), values=values))
                case["selection"] = selected
                bases = [
                    entry["values"]["ZEPHYR_BASE"]
                    for entry in selected
                    if "ZEPHYR_BASE" in entry["values"]
                ]
                if not bases or any(base != str(zephyr) for base in bases):
                    raise RuntimeError(
                        f"intended source selection not found in cache: {case_name}"
                    )
                if not any(
                    entry["values"].get("CMAKE_C_COMPILER") for entry in selected
                ):
                    raise RuntimeError(f"compiler selection absent: {case_name}")
                # Module directories are not necessarily cached CMake variables.
                # Preserve Zephyr's generated maps instead of inventing metadata.
                case["module_maps"] = {}
                for cache in caches:
                    for map_name in ("zephyr_modules.txt", "sysbuild_modules.txt"):
                        module_map = cache.parent / map_name
                        if module_map.is_file():
                            case["module_maps"][
                                str(module_map)
                            ] = module_map.read_text()
                artifacts = list(build.glob("**/zephyr/zephyr.elf"))
                if not artifacts:
                    raise RuntimeError(f"missing ELF: {case_name}")
                case["artifacts"] = {
                    str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                    for path in artifacts
                }
        report["outcome"] = "passed"
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as exc:
        report["error"] = str(exc)
        print(f"application matrix: {exc}", file=sys.stderr)
        return 1
    finally:
        (output / "result.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    sys.exit(main())
