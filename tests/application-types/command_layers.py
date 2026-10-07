"""Opt-in resolved west registry and per-command parser qualification."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import signal

import yaml
from west.configuration import Configuration
from west.manifest import Manifest

from host_platform import native_host


def catalog(workspace):
    manifest = Manifest.from_topdir(
        topdir=workspace, config=Configuration(topdir=workspace)
    )
    result = []
    for project in manifest.projects:
        paths = project.west_commands or []
        if isinstance(paths, str):
            paths = [paths]
        for descriptor in paths:
            path = Path(project.abspath) / descriptor
            if not path.is_file():
                result.append(
                    {
                        "owner": project.path,
                        "descriptor": str(path),
                        "error": "missing descriptor",
                    }
                )
                continue
            for entry in yaml.safe_load(path.read_text()).get("west-commands", []):
                implementation = Path(project.abspath) / entry["file"]
                for command in entry["commands"]:
                    result.append(
                        {
                            "name": command["name"],
                            "class": command["class"],
                            "owner": project.path,
                            "descriptor": str(path),
                            "implementation": str(implementation),
                            "implementation_present": implementation.is_file(),
                        }
                    )
    return result


def source_state(workspace, registrations):
    """Capture command owners' Git state plus workspace configuration."""
    result = {}
    config = workspace / ".west/config"
    result["config_sha256"] = hashlib.sha256(config.read_bytes()).hexdigest()
    manifest = Manifest.from_topdir(topdir=workspace)
    owners = {registration["owner"] for registration in registrations}
    owners.add(manifest.projects[0].path)
    for project in manifest.projects:
        if project.path not in owners:
            continue
        root = Path(project.abspath)
        state = {}
        for label, command in (
            ("head", ["rev-parse", "HEAD"]),
            ("status", ["status", "--porcelain=v1", "--untracked-files=all"]),
            ("diff", ["diff", "--binary", "HEAD"]),
        ):
            proc = subprocess.run(
                ["git", "-C", str(root), *command], capture_output=True, timeout=120
            )
            if proc.returncode:
                raise RuntimeError(
                    f"cannot snapshot {project.path}: {proc.stderr.decode(errors='replace')}"
                )
            state[label] = hashlib.sha256(proc.stdout).hexdigest()
        result[project.path] = state
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--approve-command-tests", action="store_true")
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--workspace-app", required=True, type=Path)
    parser.add_argument("--python-environment", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--backend", choices=("west", "nrfutil"), action="append")
    parser.add_argument(
        "--sbom-smoke",
        action="store_true",
        help="optional offline Nordic execution smoke; not an availability verdict",
    )
    args = parser.parse_args()
    if not args.approve_command_tests:
        parser.error(
            "--approve-command-tests required; writes test-owned logs/reports only, never provisions SDK/Python or operates hardware"
        )
    repo = Path(__file__).resolve().parents[2]
    host = native_host(repo)
    backends = args.backend or host["backends"]
    if any(backend not in host["backends"] for backend in backends):
        parser.error("requested backend unavailable on native host")
    workspace = args.workspace.resolve()
    workspace_app = args.workspace_app.resolve()
    if not workspace_app.is_dir() or not workspace_app.is_relative_to(workspace):
        parser.error(
            "--workspace-app must be an existing application directory inside selected workspace"
        )
    output = args.output.resolve()
    if output.is_relative_to(workspace):
        parser.error(
            "--output must be outside selected workspace; qualification never writes SDK sources"
        )
    output.mkdir(mode=0o700, exist_ok=False)
    report = {
        "outcome": "failed",
        "host": host["system"],
        "cases": [],
        "registry": [],
        "sbom": [],
        "errors": [],
    }

    def checkpoint():
        (output / "result.json").write_text(json.dumps(report, indent=2) + "\n")

    def interrupted(*_):
        raise InterruptedError("qualification interrupted")

    signal.signal(signal.SIGTERM, interrupted)
    env = dict(
        os.environ,
        SOURCE_MATRIX_REPO=str(repo),
        SOURCE_MATRIX_WORKSPACE=str(workspace),
        SOURCE_MATRIX_PYTHON=str(args.python_environment.resolve()),
        PYTHONDONTWRITEBYTECODE="1",
        REUSE_ENCODING_MODULE="charset_normalizer",
    )
    for key in (
        "PYTHONPATH",
        "PYTHONHOME",
        "ZEPHYR_BASE",
        "Zephyr_DIR",
        "WEST_CONFIG_LOCAL",
    ):
        env.pop(key, None)
    expression = """(builtins.getFlake (builtins.getEnv "SOURCE_MATRIX_REPO")).lib.${builtins.currentSystem}.mkNrfShell {
      backend = builtins.getEnv "SOURCE_MATRIX_BACKEND";
      ncsVersion = "v3.4.1";
      pythonRequirementGroups = if builtins.getEnv "SOURCE_MATRIX_BACKEND" == "west" then [ "ncs-extra" "ncs-ci" ] else [];
      autoBootstrap = false;
      source = { mode = "workspace"; workspace = builtins.getEnv "SOURCE_MATRIX_WORKSPACE"; };
      pythonEnvironment = if builtins.getEnv "SOURCE_MATRIX_BACKEND" == "west" then builtins.getEnv "SOURCE_MATRIX_PYTHON" else null;
    }"""
    prefix = ["nix", "develop", "--impure", "--expr", expression, "-c"]

    shell_envs = {}

    def run(backend, cwd, command, label):
        if backend not in shell_envs:
            # Enter the public shell once per backend; every subsequent command
            # still crosses its public west wrapper. Never serialize credentials
            # or unrelated inherited environment into qualification logs.
            capture = subprocess.run(
                [
                    *prefix,
                    "python3",
                    "-c",
                    "import os,json; print(json.dumps({k:os.environ[k] for k in ('PATH','NIX_NRF_SOURCE_WORKSPACE','ZEPHYR_TOOLCHAIN_VARIANT','ZEPHYR_SDK_INSTALL_DIR','SSL_CERT_FILE','SSL_CERT_DIR','NIX_SSL_CERT_FILE','GIT_SSL_CAINFO','REQUESTS_CA_BUNDLE') if k in os.environ}))",
                ],
                cwd=repo,
                env=dict(env, SOURCE_MATRIX_BACKEND=backend),
                text=True,
                capture_output=True,
                timeout=180,
            )
            if capture.returncode:
                raise RuntimeError(capture.stderr)
            shell_envs[backend] = dict(
                env, **json.loads(capture.stdout.splitlines()[-1])
            )
        full = command
        try:
            proc = subprocess.run(
                full,
                cwd=cwd,
                env=shell_envs[backend],
                text=True,
                capture_output=True,
                timeout=180,
            )
        except subprocess.TimeoutExpired as exc:

            def text(value):
                return (
                    value.decode(errors="replace")
                    if isinstance(value, bytes)
                    else value or ""
                )

            proc = subprocess.CompletedProcess(
                full,
                124,
                text(exc.stdout),
                text(exc.stderr)
                + "\ncommand qualification timed out after 180 seconds\n",
            )
        (output / (label + ".stdout")).write_text(proc.stdout)
        (output / (label + ".stderr")).write_text(proc.stderr)
        return proc

    before = None
    registrations = []
    try:
        registrations = catalog(workspace)
        report["catalog"] = registrations
        before = source_state(workspace, registrations)
        names = set()
        commands = []
        for registration in registrations:
            if "name" not in registration:
                report["errors"].append(registration)
                continue
            name = registration["name"]
            names.add(name)
            commands.append(registration)
        identity = Manifest.from_topdir(topdir=workspace)
        zephyr = Path(identity.get_projects(["zephyr"])[0].abspath)
        try:
            nrf = Path(identity.get_projects(["nrf"])[0].abspath)
        except ValueError:
            candidate = Path(identity.projects[0].abspath)
            nrf = candidate if (candidate / "Kconfig.nrf").is_file() else None
        # Application fixtures are test-owned. Repository cases use existing
        # source directories and never create files inside SDK repositories.
        freestanding = output / "freestanding-app"
        freestanding.mkdir()
        cwd_cases = {
            "zephyr-repository": zephyr,
            "workspace-application": workspace_app,
            "freestanding": freestanding,
        }
        if nrf is not None:
            cwd_cases["ncs-repository"] = nrf
        report["layout_scope"] = {
            "directories": {name: str(path) for name, path in cwd_cases.items()},
            "nordic_project_present": nrf is not None,
        }
        for backend in backends:
            baseline_registry = None
            for layout, cwd in cwd_cases.items():
                registry_proc = run(
                    backend,
                    cwd,
                    ["nix-nrf", "doctor", "--json"],
                    f"{backend}-{layout}-registry",
                )
                # Doctor's overall hardware/readiness exit code is not registry
                # readiness. Inspect only its read-only west discovery result.
                discovery = json.loads(registry_proc.stdout)["west"][
                    "extensions_discovered"
                ]
                current_registry = discovery["commands"]
                if baseline_registry is None:
                    baseline_registry = current_registry
                registry_passed = (
                    discovery["status"] in ("pass", "partial")
                    and current_registry == baseline_registry
                )
                report["registry"].append(
                    {
                        "backend": backend,
                        "layout": layout,
                        "passed": registry_passed,
                        "discovery": discovery,
                    }
                )
                active = {(entry["owner"], entry["name"]) for entry in current_registry}
                seen = set()
                for index, registration in enumerate(commands):
                    name = registration["name"]
                    label = f"{backend}-{layout}-{index:02d}-{name}"
                    registered = (
                        registration["owner"],
                        name,
                    ) in active and name not in seen
                    seen.add(name)
                    proc = (
                        run(backend, cwd, ["west", "help", name], label)
                        if registered
                        else subprocess.CompletedProcess(
                            [], 1, "", "registration is not effective in west registry"
                        )
                    )
                    passed = (
                        proc.returncode == 0
                        and registered
                        and registration["implementation_present"]
                        and "usage:" in proc.stdout.lower()
                    )
                    report["cases"].append(
                        {
                            "backend": backend,
                            "layout": layout,
                            "command": name,
                            "owner": registration["owner"],
                            "descriptor": registration["descriptor"],
                            "registered": registered,
                            "activation_status": (
                                "pass"
                                if passed
                                else (
                                    "missing-implementation"
                                    if registered
                                    and not registration["implementation_present"]
                                    else (
                                        "parser-load-failed"
                                        if registered
                                        else "not-registered"
                                    )
                                )
                            ),
                            "stdout": (
                                str(output / (label + ".stdout"))
                                if registered
                                else None
                            ),
                            "stderr": (
                                str(output / (label + ".stderr"))
                                if registered
                                else None
                            ),
                            "returncode": proc.returncode,
                            "passed": passed,
                        }
                    )
                    checkpoint()
                if not args.sbom_smoke:
                    continue
                if "ncs-sbom" not in names:
                    report["sbom"].append(
                        {
                            "backend": backend,
                            "layout": layout,
                            "passed": False,
                            "reason": "optional smoke command not declared",
                        }
                    )
                    continue
                sbom_root = output / f"sbom-{backend}-{layout}"
                sbom_root.mkdir()
                source = sbom_root / "input.c"
                source.write_text(
                    "// SPDX-License-Identifier: MIT\nint command_layer_fixture(void) { return 1; }\n"
                )
                spdx = sbom_root / "report.spdx"
                proc = run(
                    backend,
                    cwd,
                    [
                        "west",
                        "ncs-sbom",
                        "--input-files",
                        str(source),
                        "--license-detectors",
                        "spdx-tag",
                        "--optional-license-detectors",
                        "",
                        "--processes",
                        "1",
                        "--output-spdx",
                        str(spdx),
                    ],
                    f"{backend}-{layout}-sbom",
                )
                text = spdx.read_text() if spdx.is_file() else ""
                passed = (
                    proc.returncode == 0
                    and "SPDXVersion: SPDX-2.2" in text
                    and "MIT" in text
                    and hashlib.sha1(source.read_bytes()).hexdigest() in text
                )
                report["sbom"].append(
                    {
                        "backend": backend,
                        "layout": layout,
                        "returncode": proc.returncode,
                        "passed": passed,
                        "report": str(spdx),
                    }
                )
                checkpoint()
        if not report["errors"] and all(
            case["passed"] for case in report["registry"] + report["cases"]
        ):
            report["outcome"] = "passed"
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as exc:
        report["errors"].append(str(exc))
    finally:
        report["sbom_smoke_outcome"] = (
            "not-requested"
            if not args.sbom_smoke
            else (
                "passed"
                if report["sbom"] and all(case["passed"] for case in report["sbom"])
                else "failed"
            )
        )
        if before is not None:
            try:
                after = source_state(workspace, registrations)
                report["preservation"] = {
                    "passed": before == after,
                    "before": before,
                    "after": after,
                    "scope": "command-owner Git HEAD/status/diff and workspace config; not all SDK projects",
                }
                if before != after:
                    report["outcome"] = "failed"
                    report["errors"].append(
                        "command qualification changed selected source/configuration state"
                    )
            except (
                OSError,
                ValueError,
                RuntimeError,
                subprocess.SubprocessError,
            ) as exc:
                report["outcome"] = "failed"
                report["errors"].append(f"source preservation check failed: {exc}")
        (output / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print(
        json.dumps(
            {
                "outcome": report["outcome"],
                "cases": len(report["cases"]),
                "failed": sum(not case["passed"] for case in report["cases"]),
                "errors": report["errors"],
            }
        )
    )
    return 0 if report["outcome"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())
