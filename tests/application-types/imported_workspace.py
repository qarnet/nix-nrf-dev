#!/usr/bin/env python3
"""Opt-in local-only application-manifest SDK qualification; four real builds."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from typing import Any

from local_workspace import (
    FixtureError,
    digest,
    git,
    isolated_env,
    prepare,
    verify_original,
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--approve-local-setup-build", action="store_true")
    parser.add_argument("--sdk-workspace", required=True, type=Path)
    parser.add_argument("--python-environment", required=True, type=Path)
    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help="new output root; retained, never deleted",
    )
    parser.add_argument(
        "--exclude-project",
        action="append",
        default=[],
        help="explicit import blocklist; record omitted SDK features",
    )
    parser.add_argument("--max-copy-gib", type=float, default=3)
    parser.add_argument("--reserve-gib", type=float, default=1)
    parser.add_argument("--board", default="xiao_nrf54l15/nrf54l15/cpuapp")
    args = parser.parse_args()
    if not args.approve_local_setup_build:
        parser.error(
            "--approve-local-setup-build required; creates local clones/working files and firmware artifacts"
        )
    if args.max_copy_gib <= 0 or args.reserve_gib < 0:
        parser.error("copy budget must be positive and reserve non-negative")
    if any(name in args.exclude_project for name in ("nrf", "zephyr")):
        parser.error("Nordic/Zephyr source projects cannot be excluded")
    root = args.output.resolve()
    root.mkdir(mode=0o700, parents=False, exist_ok=False)
    repo = Path(__file__).resolve().parents[2]
    report: dict[str, Any] = dict(
        outcome="failed", cases=[], negative_checks=[], commands=[], board=args.board
    )
    plan = None
    started = time.monotonic()
    try:
        plan = prepare(
            args.sdk_workspace,
            root / "workspace",
            repo / "tests/firmware/workspace-import-fixture",
            max_bytes=int(args.max_copy_gib * 1024**3),
            reserve_bytes=int(args.reserve_gib * 1024**3),
            excluded_projects=args.exclude_project,
        )
        report["fixture"] = plan
        report["preparation_seconds"] = time.monotonic() - started
        workspace = Path(plan["destination"])
        zephyr, nrf, module = (
            workspace / "sdk/rtos",
            workspace / "sdk/nrf",
            workspace / "modules/source_import_probe",
        )
        env = dict(
            isolated_env(),
            SOURCE_MATRIX_REPO=str(repo),
            SOURCE_MATRIX_WORKSPACE=str(workspace),
            SOURCE_MATRIX_VERSION="v" + plan["ncs_version"],
            SOURCE_MATRIX_PYTHON=str(args.python_environment.resolve()),
        )
        expression = """(builtins.getFlake (builtins.getEnv "SOURCE_MATRIX_REPO")).lib.x86_64-linux.mkNrfShell {
          backend = builtins.getEnv "SOURCE_MATRIX_BACKEND";
          ncsVersion = builtins.getEnv "SOURCE_MATRIX_VERSION";
          autoBootstrap = false;
          source = { mode = "workspace"; workspace = builtins.getEnv "SOURCE_MATRIX_WORKSPACE"; };
          pythonEnvironment = if builtins.getEnv "SOURCE_MATRIX_BACKEND" == "west" then builtins.getEnv "SOURCE_MATRIX_PYTHON" else null;
        }"""
        prefix = ["nix", "develop", "--impure", "--expr", expression, "-c"]

        def run(backend, command, name, extra=None):
            full = [*prefix, *command]
            report["commands"].append(full)
            context = dict(env, SOURCE_MATRIX_BACKEND=backend, **(extra or {}))
            with (root / f"{name}.log").open("w") as log:
                result = subprocess.run(
                    full,
                    cwd=repo,
                    env=context,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=log,
                )
                log.write(result.stdout)
            return result

        for backend in ("nrfutil", "west"):
            source = run(backend, ["nix-nrf", "source", "--json"], f"{backend}-source")
            if source.returncode:
                raise FixtureError(f"{backend} source discovery failed; see source log")
            identity = json.loads(source.stdout.splitlines()[-1])
            if (
                identity["manifest"] != str(workspace / "application/west.yml")
                or identity["zephyr_base"] != str(zephyr)
                or identity["nrf_base"] != str(nrf)
            ):
                raise FixtureError(
                    f"{backend} source discovery did not select the independent application workspace"
                )
            report[backend + "_source"] = identity
            # The old checkout is valid, but must never silently win selection.
            bad = run(
                backend,
                ["nix-nrf", "source", "--json"],
                f"{backend}-conflicting-source",
                {"ZEPHYR_BASE": str(args.sdk_workspace.resolve() / "zephyr")},
            )
            if bad.returncode == 0:
                raise FixtureError(
                    "original SDK environment silently overrode fixture sources"
                )
            report["negative_checks"].append(
                dict(name=backend + "-conflicting-source", passed=True)
            )
        nrf_sha = git(nrf, "rev-parse", "refs/heads/manifest-rev")
        git(nrf, "update-ref", "-d", "refs/heads/manifest-rev")
        try:
            for backend in ("nrfutil", "west"):
                failed = run(
                    backend,
                    ["nix-nrf", "source", "--json"],
                    f"{backend}-missing-import-ref",
                )
                if failed.returncode == 0 or git(
                    nrf, "show-ref", "refs/heads/manifest-rev", check=False
                ):
                    raise FixtureError(
                        "missing importer ref was accepted or implicitly repaired"
                    )
                report["negative_checks"].append(
                    dict(name=backend + "-missing-import-ref", passed=True)
                )
        finally:
            git(nrf, "update-ref", "refs/heads/manifest-rev", nrf_sha)

        for backend in ("nrfutil", "west"):
            ready = run(
                backend, ["nix-nrf", "bootstrap", "--check"], f"{backend}-readiness"
            )
            if ready.returncode:
                raise FixtureError(
                    f"{backend} existing tools/Python not ready; no provisioning attempted"
                )
            for sysbuild in (False, True):
                name = backend + ("-sysbuild" if sysbuild else "-single")
                build = root / "builds" / name
                build_started = time.monotonic()
                result = run(
                    backend,
                    [
                        "west",
                        "build",
                        "--sysbuild" if sysbuild else "--no-sysbuild",
                        "-b",
                        args.board,
                        "-d",
                        str(build),
                        str(workspace / "application"),
                    ],
                    name,
                )
                case: dict[str, Any] = dict(
                    name=name,
                    returncode=result.returncode,
                    seconds=time.monotonic() - build_started,
                )
                report["cases"].append(case)
                if result.returncode:
                    raise FixtureError(f"real imported-workspace build failed: {name}")
                caches = [build / "CMakeCache.txt", *build.glob("*/CMakeCache.txt")]
                case["caches"], case["module_maps"] = {}, {}
                compilers, pythons = [], []
                for cache in caches:
                    if not cache.is_file():
                        continue
                    values = {}
                    for line in cache.read_text().splitlines():
                        key, sep, value = line.partition("=")
                        key = key.split(":", 1)[0]
                        if sep and key in (
                            "ZEPHYR_BASE",
                            "CMAKE_C_COMPILER",
                            "WEST_PYTHON",
                            "ZEPHYR_SDK_INSTALL_DIR",
                        ):
                            values[key] = value
                    case["caches"][str(cache)] = values
                    if (
                        "ZEPHYR_BASE" in values
                        and Path(values["ZEPHYR_BASE"]).resolve() != zephyr
                    ):
                        raise FixtureError("build used another Zephyr checkout")
                    if "CMAKE_C_COMPILER" in values:
                        compilers.append(values["CMAKE_C_COMPILER"])
                    if "WEST_PYTHON" in values:
                        pythons.append(values["WEST_PYTHON"])
                    module_map = cache.parent / "zephyr_modules.txt"
                    if module_map.is_file():
                        text = module_map.read_text()
                        case["module_maps"][str(module_map)] = text
                        names = dict(re.findall(r'^"([^"]+)":"([^"]*)":', text, re.M))
                        for path in names.values():
                            if path and not Path(path).resolve().is_relative_to(
                                workspace
                            ):
                                raise FixtureError(
                                    f"module source escaped the independent workspace: {path}"
                                )
                        if names.get("nrf") != str(nrf) or names.get(
                            "source_import_probe"
                        ) != str(module):
                            raise FixtureError(
                                "Nordic or manifest-owned module integration missing"
                            )
                if not compilers or not pythons or not case["module_maps"]:
                    raise FixtureError("missing compiler/Python/module evidence")
                if backend == "west" and (
                    not all(c.startswith("/nix/store/") for c in compilers)
                    or not all(
                        Path(p).parent == args.python_environment.resolve() / "bin"
                        for p in pythons
                    )
                ):
                    raise FixtureError(
                        "west backend did not use Nix compiler/prepared Python"
                    )
                if backend == "nrfutil" and any(
                    c.startswith("/nix/store/") for c in compilers
                ):
                    raise FixtureError(
                        "nrfutil backend unexpectedly used the Nix compiler"
                    )
                artifacts = list(build.glob("**/zephyr/zephyr.elf"))
                if not artifacts:
                    raise FixtureError("no firmware ELF produced")
                case["artifacts"] = {}
                for artifact in artifacts:
                    nm = compilers[0].removesuffix("gcc") + "nm"
                    symbols = subprocess.check_output(
                        [nm, "-g", str(artifact)], text=True, env=isolated_env()
                    )
                    if "source_import_fixture_value" not in symbols:
                        raise FixtureError(
                            "manifest-owned module symbol absent from final ELF"
                        )
                    case["artifacts"][str(artifact)] = hashlib.sha256(
                        artifact.read_bytes()
                    ).hexdigest()
        if (
            digest(workspace / "application/west.yml") != plan["manifest_sha256"]
            or digest(workspace / ".west/config") != plan["destination_config_sha256"]
        ):
            raise FixtureError("fixture manifest/config was mutated by public commands")
        verify_original(plan)
        report["outcome"] = "passed"
    except (OSError, ValueError, FixtureError, subprocess.SubprocessError) as exc:
        report["error"] = str(exc)
        print(f"imported-workspace qualification: {exc}", file=sys.stderr)
    finally:
        if plan:
            try:
                verify_original(plan)
                report["original_inputs_unchanged"] = True
            except (FixtureError, OSError, subprocess.SubprocessError) as exc:
                report.update(
                    outcome="failed",
                    original_inputs_unchanged=False,
                    original_error=str(exc),
                )
        report["total_seconds"] = time.monotonic() - started
        (root / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    # Final source verification can turn a successful build into a failure.
    # Decide the process status only after the retained report is finalized.
    return 0 if report["outcome"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())
