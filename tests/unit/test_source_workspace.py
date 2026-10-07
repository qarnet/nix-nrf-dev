"""Public shell/CLI tests with real west and CMake, synthetic source packages.

These prove source routing and non-mutation, not firmware/toolchain qualification.
"""

import hashlib
import json
import os
import shutil
import signal
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
import zipfile

BACKENDS = os.environ.get("SOURCE_TEST_BACKENDS", "nrf west").split()


class SourceWorkspaceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.ws = self.root / "workspace"
        self.ws.mkdir()
        self.home = self.root / "home"
        self.home.mkdir()
        self.zephyr = self.ws / "vendor/rtos"
        self.nrf = self.ws / "vendor/nordic"
        files = {
            ".west/config": "[manifest]\npath = manifest\n[zephyr]\nbase = vendor/rtos\n",
            "manifest/west.yml": "manifest:\n  self:\n    west-commands: commands.yml\n  projects:\n    - name: zephyr\n      path: vendor/rtos\n      url: https://example.invalid/zephyr\n    - name: nrf\n      path: vendor/nordic\n      url: https://example.invalid/nrf\n",
            "manifest/commands.yml": "west-commands:\n  - file: commands.py\n    commands:\n      - name: build\n        class: Build\n        help: configure a synthetic package discovery fixture\n",
            "manifest/commands.py": """import os
import subprocess
from west.commands import WestCommand

class Build(WestCommand):
    def __init__(self):
        super().__init__('build', 'configure fixture', 'Not a firmware builder')
    def do_add_parser(self, adder):
        parser = adder.add_parser(self.name)
        parser.add_argument('app')
        parser.add_argument('-d', '--build-dir', required=True)
        return parser
    def do_run(self, args, unknown):
        result = subprocess.run(['cmake', '-S', args.app, '-B', args.build_dir,
                                 '-DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF'])
        if result.returncode:
            self.die('fixture configure failed')
""",
            "vendor/rtos/share/zephyr-package/cmake/ZephyrConfig.cmake": """get_filename_component(ZEPHYR_BASE "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
set(ZEPHYR_BASE "${ZEPHYR_BASE}" CACHE PATH "Synthetic source package")
set(Zephyr_FOUND TRUE)
""",
            "vendor/nordic/VERSION": "VERSION_MAJOR = 3\nVERSION_MINOR = 4\nPATCHLEVEL = 1\nVERSION_TWEAK = 0\nEXTRAVERSION =\nVERSION_METADATA = lts\n",
            "vendor/nordic/Kconfig.nrf": "# synthetic NCS source sentinel\n",
        }
        for name in (
            "CMakeLists.txt",
            "Kconfig",
            "VERSION",
            "cmake/modules/zephyr_default.cmake",
            "scripts/zephyr_module.py",
            "share/sysbuild/CMakeLists.txt",
            "share/sysbuild-package/cmake/SysbuildConfig.cmake",
        ):
            files[f"vendor/rtos/{name}"] = "# source readiness sentinel\n"
        for prefix in ("vendor/rtos", "vendor/nordic"):
            files[f"{prefix}/scripts/requirements.txt"] = "west>=1.0\n"
        for name, contents in files.items():
            path = self.ws / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(contents)
        venv = self.ws / ".venv/bin"
        venv.mkdir(parents=True)
        for name in ("python", "pip"):
            # Only the readiness import/version boundary is synthetic. Actual
            # west execution and package discovery use real Nix tools below.
            path = venv / name
            path.write_text("#!/bin/sh\nexit 0\n")
            path.chmod(0o755)
        (venv / "west").symlink_to(Path(os.environ["SOURCE_REAL_TOOLS"]) / "west")
        self.env = dict(
            os.environ,
            HOME=str(self.home),
            SOURCE_TEST_STATE=str(self.root),
            WEST_CONFIG_GLOBAL=str(self.home / "absent-global"),
            WEST_CONFIG_SYSTEM=str(self.home / "absent-system"),
        )
        for key in (
            "ZEPHYR_BASE",
            "Zephyr_DIR",
            "NIX_NRF_SOURCE_WORKSPACE",
            "WEST_CONFIG_LOCAL",
            "NIX_NRF_BOOTSTRAP_YES",
            "NIX_NRF_WEST_PYTHON_ENVIRONMENT",
        ):
            self.env.pop(key, None)

    def run_shell(self, backend, args, *, cwd=None, extra=None, after_hook=""):
        env = dict(self.env, PATH=os.environ[f"SOURCE_{backend.upper()}_PATH"])
        env.update(extra or {})
        return subprocess.run(
            [
                "bash",
                "-ceu",
                f'source "$1" >&2; shift; {after_hook} exec "$@"',
                "source-test",
                os.environ[f"SOURCE_{backend.upper()}_HOOK"],
                *args,
            ],
            cwd=cwd or self.ws,
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
        )

    def assert_ok(self, result):
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)

    def source_snapshot(self):
        return {
            str(path.relative_to(self.ws)): hashlib.sha256(
                path.read_bytes()
            ).hexdigest()
            for path in self.ws.rglob("*")
            if path.is_file() and ".venv" not in path.parts
        }

    def test_selected_group_checks_missing_requested_package_not_only_imports(self):
        library = self.root / "fixture-python"
        library.mkdir()
        for module in ("zcbor", "nrfregtool"):
            (library / f"{module}.py").write_text(
                "# SDK import fixture, not boundary under test\n"
            )
        real_python = os.environ["SOURCE_REQUIREMENT_PYTHON"]
        python = self.ws / ".venv/bin/python"
        python.write_text(
            f'#!/bin/sh\nexport PYTHONPATH="{library}"\nexec "{real_python}" "$@"\n'
        )
        python.chmod(0o755)
        (self.nrf / "scripts/requirements-ci.txt").write_text("pyusb\nwget>=3.2\n")
        unselected = self.ws / "module-tests/scripts"
        unselected.mkdir(parents=True)
        (unselected / "requirements.txt").write_text("fixture-unselected-test-tool\n")
        manifest = self.ws / "manifest/west.yml"
        manifest.write_text(
            manifest.read_text()
            + "    - name: unselected-tests\n      path: module-tests\n      url: https://example.invalid/unselected-tests\n"
        )
        self.assert_ok(self.run_shell("west", ["nix-nrf", "bootstrap", "--check"]))
        self.assert_ok(
            subprocess.run(
                [str(python), "-c", "import usb.core"], capture_output=True, text=True
            )
        )
        self.assert_ok(
            subprocess.run(
                [str(python), "-m", "pip", "check"], capture_output=True, text=True
            )
        )
        before = self.source_snapshot()
        packages = subprocess.check_output(
            [str(python), "-m", "pip", "list", "--format=json"], text=True
        )
        for option in ("--check", "--yes"):
            failed = self.run_shell("west_group", ["nix-nrf", "bootstrap", option])
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn("wget: not installed", failed.stderr)
        self.assertEqual(self.source_snapshot(), before)
        self.assertEqual(
            subprocess.check_output(
                [str(python), "-m", "pip", "list", "--format=json"], text=True
            ),
            packages,
        )
        # Caller explicitly provisions a local test-owned wheel. No network or
        # readiness repair participates in this actual installation boundary.
        wheel = self.root / "wget-3.2-py3-none-any.whl"
        with zipfile.ZipFile(wheel, "w") as archive:
            archive.writestr("wget.py", "# test-owned requested tool fixture\n")
            archive.writestr(
                "wget-3.2.dist-info/METADATA",
                "Metadata-Version: 2.1\nName: wget\nVersion: 3.2\n",
            )
            archive.writestr(
                "wget-3.2.dist-info/WHEEL",
                "Wheel-Version: 1.0\nGenerator: fixture\nRoot-Is-Purelib: true\nTag: py3-none-any\n",
            )
            archive.writestr(
                "wget-3.2.dist-info/RECORD",
                "wget.py,,\nwget-3.2.dist-info/METADATA,,\nwget-3.2.dist-info/WHEEL,,\nwget-3.2.dist-info/RECORD,,\n",
            )
        installed = subprocess.run(
            [
                str(python),
                "-m",
                "pip",
                "install",
                "--no-index",
                "--no-deps",
                "--target",
                str(library),
                str(wheel),
            ],
            capture_output=True,
            text=True,
        )
        self.assert_ok(installed)
        self.assert_ok(
            self.run_shell("west_group", ["nix-nrf", "bootstrap", "--check"])
        )
        self.assertEqual(self.source_snapshot(), before)

    def test_source_and_real_west_select_manifest_paths_without_mutation(self):
        before = self.source_snapshot()
        for backend in BACKENDS:
            with self.subTest(backend=backend):
                result = self.run_shell(backend, ["nix-nrf", "source", "--json"])
                self.assert_ok(result)
                info = json.loads(result.stdout)
                self.assertEqual(info["zephyr_base"], str(self.zephyr))
                self.assertEqual(info["nrf_base"], str(self.nrf))
                result = self.run_shell(
                    backend, ["west", "list", "zephyr", "-f", "{abspath}"]
                )
                self.assert_ok(result)
                self.assertEqual(result.stdout.strip(), str(self.zephyr))
                self.assertEqual(before, self.source_snapshot())
                self.assertFalse((self.home / ".cmake").exists())
                self.assertFalse((self.home / "ncs").exists())

    def test_core_queries_work_without_workspace_or_sdk_python(self):
        shutil.rmtree(self.ws / ".west")
        shutil.rmtree(self.ws / ".venv")
        for backend in BACKENDS:
            for args in (
                ["--version"],
                ["--help"],
                ["help", "init"],
                ["help", "update"],
                ["help", "--help"],
            ):
                result = self.run_shell(backend, ["west", *args])
                self.assert_ok(result)
                self.assertIn("west", result.stdout.lower())
            result = self.run_shell(backend, ["west", "topdir"])
            self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "toolchain.jsonl").exists())
        self.assertFalse((self.home / "ncs").exists())

    def test_core_workspace_queries_ignore_build_readiness_and_bind_freestanding_cwd(
        self,
    ):
        shutil.rmtree(self.ws / ".venv")
        (self.root / "missing-toolchain").touch()
        outside = self.root / "outside"
        outside.mkdir()
        before = self.source_snapshot()
        for backend in BACKENDS:
            result = self.run_shell(
                backend, ["west", "topdir"], after_hook=f'cd "{outside}";'
            )
            self.assert_ok(result)
            self.assertEqual(result.stdout.strip(), str(self.ws))
            self.assert_ok(
                self.run_shell(backend, ["west", "list", "zephyr", "-f", "{abspath}"])
            )
            self.assert_ok(self.run_shell(backend, ["west", "manifest", "--validate"]))
            failed = self.run_shell(backend, ["west", "help", "build"])
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn("core available", failed.stderr)
            self.assertIn("doctor", failed.stderr)
        self.assertEqual(before, self.source_snapshot())

    def test_global_switches_help_and_aliases_preserve_command_layer(self):
        config = self.ws / ".west/config"
        config.write_text(config.read_text() + "\n[alias]\nqtop = topdir\n")
        for backend in BACKENDS:
            for args in (
                ["help", "--", "build"],
                [f"-vz{self.zephyr}", "build", "--help"],
            ):
                result = self.run_shell(backend, ["west", *args])
                self.assert_ok(result)
                self.assertIn("usage:", result.stdout.lower())
        shutil.rmtree(self.ws / ".venv")
        (self.root / "missing-toolchain").touch()
        foreign = self.root / "foreign"
        (foreign / ".west").mkdir(parents=True)
        (foreign / ".west/config").write_text("[fixture]\nidentity = foreign\n")
        for backend in BACKENDS:
            result = self.run_shell(backend, ["west", "qtop"])
            self.assert_ok(result)
            self.assertEqual(result.stdout.strip(), str(self.ws))
            self.assert_ok(self.run_shell(backend, ["west", "help", "qtop"]))
            for args in (["help", "list"], ["-h", "list"]):
                self.assert_ok(
                    self.run_shell(
                        backend, ["west", *args], after_hook=f'cd "{foreign}";'
                    )
                )
            result = self.run_shell(
                backend,
                ["west", f"-vz{self.zephyr}", "topdir"],
                after_hook=f'cd "{foreign}";',
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("another west workspace", result.stderr)

    def test_local_config_never_falls_through_to_foreign_workspace(self):
        foreign = self.root / "foreign"
        (foreign / ".west").mkdir(parents=True)
        config = foreign / ".west/config"
        config.write_text("[fixture]\nidentity = foreign\n")
        shutil.rmtree(self.ws / ".west")
        before = config.read_bytes()
        for backend in BACKENDS:
            for args in (
                ["--local", "fixture.identity"],
                ["--local", "fixture.identity", "changed"],
                ["fixture.identity", "changed"],
            ):
                result = self.run_shell(
                    backend, ["west", "config", *args], after_hook=f'cd "{foreign}";'
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("another west workspace", result.stderr)
            self.assert_ok(
                self.run_shell(
                    backend,
                    ["west", "config", "--global", "fixture.identity", "global"],
                    after_hook=f'cd "{foreign}";',
                )
            )
        self.assertEqual(config.read_bytes(), before)

    def add_layer(self, project, name):
        (project / "probe.yml").write_text(
            f"west-commands:\n  - file: probe.py\n    commands:\n      - name: {name}\n        class: Probe\n        help: layer identity probe\n"
        )
        (project / "probe.py").write_text(f"""import json
from pathlib import Path
from west.commands import WestCommand
class Probe(WestCommand):
    def __init__(self):
        super().__init__({name!r}, 'layer identity probe', 'test-owned command')
    def do_add_parser(self, adder):
        return adder.add_parser(self.name)
    def do_run(self, args, unknown):
        print(json.dumps({{'owner': str(Path(__file__).parent), 'workspace': self.topdir, 'command': self.name}}))
""")

    def test_all_application_layouts_activate_distinct_extension_layers(self):
        self.add_layer(self.zephyr, "zephyr-probe")
        self.add_layer(self.nrf, "ncs-probe")
        manifest = self.ws / "manifest/west.yml"
        manifest.write_text(
            manifest.read_text()
            .replace(
                "path: vendor/rtos\n",
                "path: vendor/rtos\n      west-commands: probe.yml\n",
            )
            .replace(
                "path: vendor/nordic\n",
                "path: vendor/nordic\n      west-commands: probe.yml\n",
            )
        )
        for cwd in (self.zephyr, self.nrf, self.ws / "app", self.root / "freestanding"):
            cwd.mkdir(exist_ok=True)
            for backend in BACKENDS:
                help_result = self.run_shell(
                    backend, ["west", "--help"], after_hook=f'cd "{cwd}";'
                )
                self.assert_ok(help_result)
                self.assertIn("zephyr-probe", help_result.stdout)
                self.assertIn("ncs-probe", help_result.stdout)
                for name, owner in (
                    ("zephyr-probe", self.zephyr),
                    ("ncs-probe", self.nrf),
                ):
                    self.assert_ok(
                        self.run_shell(
                            backend, ["west", "help", name], after_hook=f'cd "{cwd}";'
                        )
                    )
                    executed = self.run_shell(
                        backend, ["west", name], after_hook=f'cd "{cwd}";'
                    )
                    self.assert_ok(executed)
                    identity = json.loads(executed.stdout)
                    self.assertEqual(identity["owner"], str(owner))
                    self.assertEqual(identity["workspace"], str(self.ws))
        manifest.write_text(
            manifest.read_text().replace("      west-commands: probe.yml\n", "", 1)
        )
        absent = self.run_shell(BACKENDS[0], ["west", "help", "zephyr-probe"])
        self.assertNotEqual(absent.returncode, 0)
        self.assert_ok(self.run_shell(BACKENDS[0], ["west", "help", "ncs-probe"]))

    def test_disabled_extensions_and_missing_import_dependency_are_explicit(self):
        config = self.ws / ".west/config"
        config.write_text(
            config.read_text() + "\n[commands]\nallow_extensions = false\n"
        )
        result = self.run_shell(BACKENDS[0], ["west", "--help"])
        self.assert_ok(result)
        self.assertIn("extensions discovered: disabled", result.stderr)
        self.assertNotEqual(
            self.run_shell(BACKENDS[0], ["west", "help", "build"]).returncode, 0
        )
        config.write_text(
            config.read_text().replace(
                "allow_extensions = false", "allow_extensions = true"
            )
        )
        module = self.ws / "manifest/commands.py"
        previous = module.read_text()
        module.write_text("import fixture_dependency_that_does_not_exist\n" + previous)
        for backend in BACKENDS:
            self.assert_ok(self.run_shell(backend, ["west", "--version"]))
            failed = self.run_shell(backend, ["west", "help", "build"])
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn("command ready: unverified", failed.stderr)
        module.write_text(previous)
        self.assert_ok(self.run_shell(BACKENDS[0], ["west", "help", "build"]))

    def test_zephyr_only_manifest_does_not_borrow_nordic_registration(self):
        self.add_layer(self.zephyr, "zephyr-probe")
        self.add_layer(self.nrf, "ncs-probe")
        (self.ws / "manifest/west.yml").write_text(
            "manifest:\n  projects:\n    - name: zephyr\n      path: vendor/rtos\n      url: https://example.invalid/zephyr\n      west-commands: probe.yml\n"
        )
        for backend in BACKENDS:
            result = self.run_shell(backend, ["west", "--help"])
            self.assert_ok(result)
            self.assertIn("zephyr-probe", result.stdout)
            self.assertNotIn("ncs-probe", result.stdout)
            absent = self.run_shell(backend, ["west", "help", "ncs-probe"])
            self.assertNotEqual(absent.returncode, 0)
            self.assertIn("not registered", absent.stderr)
            info = json.loads(
                self.run_shell(backend, ["nix-nrf", "doctor", "--json"]).stdout
            )
            self.assertEqual(info["west"]["extensions_discovered"]["status"], "pass")
            self.assertEqual(info["west"]["command_ready"]["status"], "blocked")

    def test_doctor_reports_three_states_without_importing_extensions(self):
        descriptor = self.ws / "manifest/commands.yml"
        descriptor.write_text(
            descriptor.read_text().replace("commands.py", "danger.py")
        )
        (self.ws / "manifest/danger.py").write_text(
            f'from pathlib import Path\nPath({str(self.root / "imported")!r}).write_text("must not run")\n'
        )
        for backend in BACKENDS:
            result = self.run_shell(
                backend,
                ["nix-nrf", "doctor", "--json"],
                extra={
                    "NIX_NRF_DOCTOR_SYSFS_ROOT": str(self.root / "no-usb"),
                    "NIX_NRF_DOCTOR_DEV_ROOT": str(self.root / "no-dev"),
                },
            )
            data = json.loads(result.stdout)
            self.assertEqual(data["west"]["core_available"]["status"], "pass")
            self.assertEqual(data["west"]["extensions_discovered"]["status"], "pass")
            self.assertEqual(data["west"]["command_ready"]["status"], "unverified")
            self.assertTrue(data["west"]["command_ready"]["environment_ready"])
        self.assertFalse((self.root / "imported").exists())
        (self.ws / "manifest/danger.py").unlink()
        data = json.loads(
            self.run_shell(BACKENDS[0], ["nix-nrf", "doctor", "--json"]).stdout
        )
        self.assertEqual(data["west"]["extensions_discovered"]["status"], "partial")
        self.assertIn(
            "missing command implementation",
            data["west"]["extensions_discovered"]["errors"][0],
        )

    def test_resolved_registry_matches_west_shadowing_without_imports(self):
        self.add_layer(self.zephyr, "layer-probe")
        self.add_layer(self.nrf, "layer-probe")
        descriptor = self.nrf / "probe.yml"
        descriptor.write_text(
            descriptor.read_text()
            + "      - name: topdir\n        class: Probe\n        help: forbidden builtin shadow\n"
        )
        manifest = self.ws / "manifest/west.yml"
        manifest.write_text(
            manifest.read_text()
            .replace(
                "path: vendor/rtos\n",
                "path: vendor/rtos\n      west-commands: probe.yml\n",
            )
            .replace(
                "path: vendor/nordic\n",
                "path: vendor/nordic\n      west-commands: probe.yml\n",
            )
        )
        for backend in BACKENDS:
            data = json.loads(
                self.run_shell(backend, ["nix-nrf", "doctor", "--json"]).stdout
            )
            discovery = data["west"]["extensions_discovered"]
            self.assertEqual(discovery["status"], "partial")
            self.assertEqual(discovery["manifest"], str(manifest))
            self.assertEqual(
                discovery["commands"],
                [
                    {"name": "build", "owner": "manifest"},
                    {"name": "layer-probe", "owner": "vendor/rtos"},
                ],
            )
            rejected = {
                (entry["owner"], entry["name"])
                for entry in discovery["registrations"]
                if not entry["registered"]
            }
            self.assertEqual(
                rejected,
                {("vendor/nordic", "layer-probe"), ("vendor/nordic", "topdir")},
            )
            executed = self.run_shell(backend, ["west", "layer-probe"])
            self.assert_ok(executed)
            self.assertEqual(json.loads(executed.stdout)["owner"], str(self.zephyr))
            topdir = self.run_shell(backend, ["west", "topdir"])
            self.assert_ok(topdir)
            self.assertEqual(topdir.stdout.strip(), str(self.ws))

    def test_local_core_init_update_before_sdk_readiness(self):
        seed = self.root / "local-project"
        seed.mkdir()
        self.git(seed, "init", "--initial-branch=main")
        self.git(seed, "config", "user.email", "fixture@example.invalid")
        self.git(seed, "config", "user.name", "Fixture")
        (seed / "sentinel").write_text("local-only payload")
        self.git(seed, "add", ".")
        self.git(seed, "commit", "-m", "local fixture")
        manifest = self.root / "local-manifest"
        manifest.mkdir()
        (manifest / "west.yml").write_text(
            f"manifest:\n  projects:\n    - name: payload\n      url: {seed}\n      revision: main\n  self:\n    path: local-manifest\n"
        )
        shutil.rmtree(self.ws / ".venv")
        (self.root / "missing-toolchain").touch()
        for backend in BACKENDS:
            dest = self.root / f"new-{backend}"
            local_manifest = dest / "local-manifest"
            local_manifest.mkdir(parents=True)
            shutil.copyfile(manifest / "west.yml", local_manifest / "west.yml")
            self.assert_ok(
                self.run_shell(
                    backend,
                    ["west", "init", "-l", str(local_manifest)],
                    after_hook=f'cd "{dest}";',
                )
            )
            # Selected workspace is explicitly rebound for this new local-only
            # operation. No SDK/source readiness or toolchain bootstrap runs.
            result = self.run_shell(
                backend,
                ["west", "update"],
                extra={
                    "NIX_NRF_SOURCE_WORKSPACE": str(dest),
                },
                after_hook=f'export NIX_NRF_SOURCE_WORKSPACE="{dest}"; cd "{dest}";',
            )
            self.assert_ok(result)
            self.assertEqual(
                (dest / "payload/sentinel").read_text(), "local-only payload"
            )
        self.assertFalse((self.root / "toolchain.jsonl").exists())

    @staticmethod
    def git(path, *args):
        return subprocess.check_output(
            ["git", "-C", str(path), *args], text=True, stderr=subprocess.STDOUT
        )

    def test_all_topologies_configure_correct_package_after_changing_cwd(self):
        for backend in BACKENDS:
            for topology, app in (
                ("repository", self.nrf / "samples/demo"),
                ("workspace", self.ws / "apps/demo"),
                ("freestanding", self.root / "outside/demo"),
            ):
                for hints in (True, False):
                    with self.subTest(backend=backend, topology=topology, hints=hints):
                        self.configure_app(backend, topology, app, hints)

    def configure_app(self, backend, topology, app, hints):
        app.mkdir(parents=True, exist_ok=True)
        (app / "CMakeLists.txt").write_text(
            """cmake_minimum_required(VERSION 3.20)
project(discovery LANGUAGES NONE)
find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
file(WRITE "${CMAKE_BINARY_DIR}/selected.txt" "${ZEPHYR_BASE}")
""".replace(" HINTS $ENV{ZEPHYR_BASE}", "" if not hints else " HINTS $ENV{ZEPHYR_BASE}")
        )
        build = self.root / f"build-{backend}-{topology}-{hints}"
        result = self.run_shell(
            backend,
            ["west", "build", str(app), "-d", str(build)],
            after_hook=f'cd "{app}";',
        )
        self.assert_ok(result)
        self.assertEqual((build / "selected.txt").read_text(), str(self.zephyr))

    def test_conflicting_environment_configuration_and_cache_fail(self):
        for backend in BACKENDS:
            for variable in ("ZEPHYR_BASE", "Zephyr_DIR"):
                result = self.run_shell(
                    backend,
                    ["west", "help", "build"],
                    extra={variable: "/wrong/source"},
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("conflicts", result.stderr)
            cache = self.ws / "build/CMakeCache.txt"
            cache.parent.mkdir(exist_ok=True)
            cache.write_text("ZEPHYR_BASE:PATH=/old/source\n")
            result = self.run_shell(backend, ["west", "build", ".", "-d", "build"])
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("stale source selection", result.stderr)
            self.assertEqual(cache.read_text(), "ZEPHYR_BASE:PATH=/old/source\n")
            self.assert_ok(self.run_shell(backend, ["west", "help", "build"]))
        config = self.ws / ".west/config"
        config.write_text(config.read_text().replace("vendor/rtos", "wrong"))
        result = self.run_shell(BACKENDS[0], ["nix-nrf", "source", "--json"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("conflicts", result.stderr)

    def test_foreign_workspace_and_explicit_overrides_are_rejected(self):
        foreign = self.root / "foreign"
        (foreign / ".west").mkdir(parents=True)
        for backend in BACKENDS:
            result = self.run_shell(
                backend, ["west", "topdir"], after_hook=f'cd "{foreign}";'
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("another west workspace", result.stderr)
            for args in (
                ["-z", "/wrong", "help", "build"],
                ["build", ".", "--", "-DZEPHYR_BASE:PATH=/wrong"],
                ["build", ".", "--", "-D", "Zephyr_DIR:PATH=/wrong"],
            ):
                result = self.run_shell(backend, ["west", *args])
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("conflicts", result.stderr)

    def test_missing_sources_version_and_imports_do_not_trigger_installation(self):
        version = self.nrf / "VERSION"
        version.write_text("9.9.9\n")
        result = self.run_shell(BACKENDS[0], ["nix-nrf", "bootstrap", "--yes"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match", result.stderr)
        self.assertFalse((self.root / "toolchain.jsonl").exists())
        version.write_text("3.4.1\n")
        manifest = self.ws / "manifest/west.yml"
        manifest.write_text(
            manifest.read_text().replace(
                "path: vendor/rtos", "path: vendor/rtos\n      import: west.yml"
            )
        )
        result = self.run_shell("west", ["nix-nrf", "source", "--json"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("import", result.stderr)
        self.assertFalse((self.home / "ncs").exists())

    def test_toolchain_only_approval_and_existing_python_readiness(self):
        if "nrf" in BACKENDS:
            (self.root / "missing-toolchain").touch()
            result = self.run_shell("nrf", ["nix-nrf", "bootstrap", "--check"])
            self.assertNotEqual(result.returncode, 0)
            result = self.run_shell("nrf", ["nix-nrf", "bootstrap"])
            self.assertEqual(result.returncode, 2)
            result = self.run_shell("nrf", ["nix-nrf", "bootstrap", "--yes"])
            self.assert_ok(result)
            actions = [
                json.loads(line)
                for line in (self.root / "toolchain.jsonl").read_text().splitlines()
            ]
            self.assertTrue(
                any(argv[1:3] == ["toolchain", "install"] for argv in actions)
            )
            self.assertTrue(
                all(
                    argv[1:3] in (["toolchain", "env"], ["toolchain", "install"])
                    for argv in actions
                )
            )
        (self.ws / ".venv/bin/python").unlink()
        result = self.run_shell("west", ["nix-nrf", "bootstrap", "--yes"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("pythonEnvironment", result.stderr)
        self.assertFalse((self.ws / ".venv/bin/python").exists())

    def test_doctor_source_metadata_and_parent_environment(self):
        for backend in BACKENDS:
            result = self.run_shell(backend, ["nix-nrf", "doctor", "--json"])
            self.assertEqual(
                json.loads(result.stdout)["sdk"]["source"]["workspace"], str(self.ws)
            )
            result = self.run_shell(
                backend,
                [
                    "bash",
                    "-ceu",
                    'test -z "${ZEPHYR_BASE:-}"; test -z "${FAKE_TOOLCHAIN_ENV:-}"; test "${LD_LIBRARY_PATH:-}" = parent-value',
                ],
                extra={"LD_LIBRARY_PATH": "parent-value"},
            )
            self.assert_ok(result)

    def test_external_python_environment_and_dependency_failure(self):
        (self.ws / ".venv").rename(self.ws / ".python-env")
        result = self.run_shell(
            "west_alt", ["west", "list", "zephyr", "-f", "{abspath}"]
        )
        self.assert_ok(result)
        self.assertEqual(result.stdout.strip(), str(self.zephyr))
        python = self.ws / ".python-env/bin/python"
        python.write_text("#!/bin/sh\nexit 1\n")
        result = self.run_shell("west_alt", ["nix-nrf", "bootstrap", "--yes"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("import check failed", result.stderr)
        self.assertEqual(python.read_text(), "#!/bin/sh\nexit 1\n")

    def test_child_errors_propagate_and_matrix_requires_opt_in(self):
        for backend in BACKENDS:
            result = self.run_shell(backend, ["west", "unrecognized-command"])
            self.assertEqual(result.returncode, 2)
        output = self.root / "matrix-output"
        result = subprocess.run(
            [
                "python3",
                os.environ["SOURCE_MATRIX_SCRIPT"],
                "--backend",
                "nrfutil",
                "--workspace",
                str(self.ws),
                "--workspace-app",
                str(self.ws / "apps/app"),
                "--freestanding-app",
                str(self.root / "free"),
                "--output",
                str(output),
            ],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("--approve-build required", result.stderr)
        self.assertFalse(output.exists())

    def test_distinct_workspaces_and_quoted_paths_do_not_share_selection(self):
        other = self.root / "other workspace 'quoted'"
        shutil.copytree(self.ws, other, symlinks=True)
        (other / "vendor/nordic/Kconfig.nrf").write_text(
            "# same-version modified source\n"
        )
        for backend in BACKENDS:
            result = self.run_shell(backend, ["nix-nrf", "source", "--json"], cwd=other)
            self.assert_ok(result)
            self.assertEqual(
                json.loads(result.stdout)["zephyr_base"], str(other / "vendor/rtos")
            )
            result = self.run_shell(backend, ["nix-nrf", "source", "--json"])
            self.assert_ok(result)
            self.assertEqual(json.loads(result.stdout)["zephyr_base"], str(self.zephyr))

    def test_cancellation_reaches_owned_west_process(self):
        commands = self.ws / "manifest/commands.yml"
        commands.write_text(
            commands.read_text()
            + "      - name: hold\n        class: Hold\n        help: wait for cancellation\n"
        )
        implementation = self.ws / "manifest/commands.py"
        implementation.write_text(implementation.read_text() + """
from pathlib import Path
import time
class Hold(WestCommand):
    def __init__(self):
        super().__init__('hold', 'hold fixture', 'Wait for cancellation')
    def do_add_parser(self, adder):
        parser = adder.add_parser(self.name)
        parser.add_argument('ready')
        return parser
    def do_run(self, args, unknown):
        Path(args.ready).touch()
        while True:
            time.sleep(0.1)
""")
        for backend in BACKENDS:
            ready = self.root / f"ready-{backend}"
            env = dict(self.env, PATH=os.environ[f"SOURCE_{backend.upper()}_PATH"])
            with subprocess.Popen(
                [
                    "bash",
                    "-ceu",
                    'source "$1" >&2; shift; exec "$@"',
                    "test",
                    os.environ[f"SOURCE_{backend.upper()}_HOOK"],
                    "west",
                    "hold",
                    str(ready),
                ],
                cwd=self.ws,
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            ) as child:
                try:
                    # Activation now includes separate core/catalog checks.
                    # Match other public command setup budgets; cancellation
                    # itself must still finish within five seconds below.
                    deadline = time.monotonic() + 30
                    while not ready.exists():
                        self.assertIsNone(child.poll())
                        self.assertLess(time.monotonic(), deadline)
                        time.sleep(0.05)
                    child.terminate()
                    self.assertEqual(child.wait(timeout=5), -signal.SIGTERM)
                finally:
                    if child.poll() is None:
                        child.kill()
                        child.wait(timeout=5)

    def test_prepared_python_ignores_foreign_parent_interpreter_settings(self):
        extra = {
            "PYTHONHOME": "/unrelated/interpreter",
            "PYTHONPATH": "/unrelated/libraries",
        }
        result = self.run_shell(
            "west", ["west", "list", "zephyr", "-f", "{abspath}"], extra=extra
        )
        self.assert_ok(result)
        result = self.run_shell(
            "west",
            [
                "bash",
                "-ceu",
                'test "$PYTHONHOME" = /unrelated/interpreter; test "$PYTHONPATH" = /unrelated/libraries',
            ],
            extra=extra,
        )
        self.assert_ok(result)

    def test_application_manifest_imports_nordic_project_and_reports_its_revision(self):
        (self.nrf / "west.yml").write_text(
            "manifest:\n  projects:\n    - name: zephyr\n      path: vendor/rtos\n      url: https://example.invalid/zephyr\n"
        )
        # Disposable Git state is the actual boundary west uses for imports.
        for args in (
            ["init", "-q"],
            ["add", "."],
            [
                "-c",
                "user.name=Fixture",
                "-c",
                "user.email=fixture@example.invalid",
                "commit",
                "-qm",
                "fixture manifest",
            ],
            ["branch", "manifest-rev"],
        ):
            subprocess.run(
                ["git", "-C", str(self.nrf), *args], check=True, capture_output=True
            )
        expected = subprocess.check_output(
            ["git", "-C", str(self.nrf), "rev-parse", "HEAD"], text=True
        ).strip()
        (self.ws / "manifest/west.yml").write_text(
            "manifest:\n  projects:\n    - name: nrf\n      path: vendor/nordic\n      url: https://example.invalid/nrf\n      import: true\n"
        )
        for backend in BACKENDS:
            result = self.run_shell(backend, ["nix-nrf", "source", "--json"])
            self.assert_ok(result)
            source = json.loads(result.stdout)
            self.assertEqual(source["zephyr_base"], str(self.zephyr))
            self.assertEqual(source["nrf_revision"], expected)


if __name__ == "__main__":
    unittest.main()
