"""Opt-in compile-only qualification for the active NCS baseline and nRF52 LTS."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import sys

from host_platform import native_host


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--approve-builds", action="store_true")
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--python-environment", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--backend", choices=("west", "nrfutil"), action="append")
    args = parser.parse_args()
    if not args.approve_builds:
        parser.error(
            "--approve-builds required; writes firmware artifacts only, never provisions or operates hardware"
        )
    repo = Path(__file__).resolve().parents[2]
    host = native_host(repo)
    backends = args.backend or host["backends"]
    if any(backend not in host["backends"] for backend in backends):
        parser.error("requested backend unavailable on native host")
    workspace = args.workspace.resolve()
    output = args.output.resolve()
    if output.is_relative_to(workspace):
        parser.error("output must be outside selected SDK workspace")
    output.mkdir(mode=0o700, exist_ok=False)
    env = dict(
        os.environ,
        SOURCE_MATRIX_REPO=str(repo),
        SOURCE_MATRIX_WORKSPACE=str(workspace),
        SOURCE_MATRIX_PYTHON=str(args.python_environment.resolve()),
        PYTHONDONTWRITEBYTECODE="1",
    )
    for key in (
        "PYTHONHOME",
        "PYTHONPATH",
        "ZEPHYR_BASE",
        "Zephyr_DIR",
        "WEST_CONFIG_LOCAL",
    ):
        env.pop(key, None)
    expression = """(builtins.getFlake (builtins.getEnv "SOURCE_MATRIX_REPO")).lib.${builtins.currentSystem}.mkNrfShell {
      backend = builtins.getEnv "SOURCE_MATRIX_BACKEND";
      ncsVersion = "v3.4.1";
      autoBootstrap = false;
      source = { mode = "workspace"; workspace = builtins.getEnv "SOURCE_MATRIX_WORKSPACE"; };
      pythonEnvironment = if builtins.getEnv "SOURCE_MATRIX_BACKEND" == "west" then builtins.getEnv "SOURCE_MATRIX_PYTHON" else null;
      pythonRequirementGroups = if builtins.getEnv "SOURCE_MATRIX_BACKEND" == "west" then [ "ncs-extra" "ncs-ci" ] else [];
    }"""
    prefix = ["nix", "develop", "--impure", "--expr", expression, "-c"]
    report = {
        "outcome": "failed",
        "host": host["system"],
        "ncs_version": "v3.4.1",
        "cases": [],
        "errors": [],
    }
    cases = [
        ("nrf52840-single", "nrf52840dk/nrf52840", False, 40),
        ("nrf52840-sysbuild", "nrf52840dk/nrf52840", True, 40),
        ("nrf5340-cpuapp", "nrf5340dk/nrf5340/cpuapp", False, 40),
        ("nrf5340-cpunet", "nrf5340dk/nrf5340/cpunet", False, 40),
        ("nrf54l15-cpuapp", "nrf54l15dk/nrf54l15/cpuapp", True, 40),
        ("nrf54l15-flpr", "nrf54l15dk/nrf54l15/cpuflpr", True, 243),
    ]
    try:
        for backend in backends:
            context = dict(env, SOURCE_MATRIX_BACKEND=backend)
            capture = subprocess.run(
                [
                    *prefix,
                    "python3",
                    "-c",
                    "import json,os; print(json.dumps({k:os.environ[k] for k in ('PATH','NIX_NRF_SOURCE_WORKSPACE','ZEPHYR_TOOLCHAIN_VARIANT','ZEPHYR_SDK_INSTALL_DIR','SSL_CERT_FILE','SSL_CERT_DIR','NIX_SSL_CERT_FILE') if k in os.environ}))",
                ],
                cwd=repo,
                env=context,
                text=True,
                capture_output=True,
                timeout=180,
            )
            if capture.returncode:
                raise RuntimeError(capture.stderr)
            context.update(json.loads(capture.stdout.splitlines()[-1]))
            identity = subprocess.run(
                ["nix-nrf", "source", "--json"],
                cwd=repo,
                env=context,
                capture_output=True,
                text=True,
                timeout=120,
            )
            if identity.returncode:
                raise RuntimeError(identity.stderr)
            source = json.loads(identity.stdout)
            report[backend + "_source"] = source
            application = Path(source["zephyr_base"]) / "samples/hello_world"
            for label, board, sysbuild, machine in cases:
                build = output / f"{backend}-{label}"
                command = [
                    "west",
                    "build",
                    str(application),
                    "-b",
                    board,
                    "-d",
                    str(build),
                    "--sysbuild" if sysbuild else "--no-sysbuild",
                ]
                if sysbuild:
                    command += ["--", "-DSB_CONFIG_PARTITION_MANAGER=n"]
                with (output / f"{backend}-{label}.log").open("w") as log:
                    result = subprocess.run(
                        command,
                        cwd=repo,
                        env=context,
                        stdout=log,
                        stderr=subprocess.STDOUT,
                        timeout=900,
                    )
                artifacts = []
                for elf in build.glob("**/zephyr.elf"):
                    data = elf.read_bytes()
                    if data[:5] != b"\x7fELF\x01":
                        raise RuntimeError(f"not an ELF32 firmware artifact: {elf}")
                    endian = "<" if data[5] == 1 else ">"
                    artifacts.append(
                        {
                            "path": str(elf),
                            "machine": struct.unpack_from(endian + "H", data, 18)[0],
                            "sha256": hashlib.sha256(data).hexdigest(),
                        }
                    )
                passed = result.returncode == 0 and any(
                    artifact["machine"] == machine for artifact in artifacts
                )
                report["cases"].append(
                    {
                        "backend": backend,
                        "board": board,
                        "sysbuild": sysbuild,
                        "returncode": result.returncode,
                        "passed": passed,
                        "artifacts": artifacts,
                    }
                )
                (output / "result.json").write_text(json.dumps(report, indent=2) + "\n")
        if report["cases"] and all(case["passed"] for case in report["cases"]):
            report["outcome"] = "passed"
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as exc:
        report["errors"].append(str(exc))
    finally:
        (output / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print(
        json.dumps(
            {
                "outcome": report["outcome"],
                "cases": len(report["cases"]),
                "errors": report["errors"],
            }
        )
    )
    return 0 if report["outcome"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())
