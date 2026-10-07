"""New checks cannot disappear between shared and native CI phases."""

import importlib.util
import os
from pathlib import Path
import unittest

import yaml

path = os.environ.get(
    "CI_PARTITION_SCRIPT", str(Path(__file__).resolve().parents[2] / "scripts/ci.py")
)
spec = importlib.util.spec_from_file_location("ci", path)
assert spec is not None and spec.loader is not None
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)


class PartitionTests(unittest.TestCase):
    def test_workflow_requires_both_native_hosts_before_release(self):
        workflow_path = os.environ.get(
            "CI_WORKFLOW",
            str(Path(__file__).resolve().parents[2] / ".github/workflows/ci.yml"),
        )
        workflow = yaml.safe_load(Path(workflow_path).read_text())
        jobs = workflow["jobs"]
        native = jobs["check"]
        self.assertEqual(native["needs"], "shared")
        self.assertFalse(native["strategy"]["fail-fast"])
        self.assertEqual(
            {
                entry["system"]: (entry["runner"], entry["backend"])
                for entry in native["strategy"]["matrix"]["include"]
            },
            {
                "x86_64-linux": ("ubuntu-24.04", "nrfutil"),
                "aarch64-linux": ("ubuntu-24.04-arm", "west"),
            },
        )
        release = jobs["release"]
        self.assertEqual(set(release["needs"]), {"shared", "check"})
        self.assertEqual(
            release["if"],
            "github.event_name == 'push' && github.ref == 'refs/heads/main'",
        )
        self.assertEqual(workflow["permissions"], {"contents": "read"})
        self.assertNotIn("permissions", native)
        commands = "\n".join(step.get("run", "") for step in native["steps"])
        self.assertIn("scripts/ci.py native --system", commands)
        self.assertIn("scripts/ci.py packages --system", commands)

    def test_every_check_runs_in_exactly_one_phase(self):
        names = {
            "formatting",
            "pre-commit",
            "release-consistency",
            "new-check",
            "backlog",
        }
        shared = set(ci.select_checks(names, "shared"))
        native = set(ci.select_checks(names, "native"))
        self.assertEqual(shared | native, names)
        self.assertFalse(shared & native)
        self.assertIn("new-check", native)
        self.assertIn("backlog", native)

    def test_missing_shared_contract_is_not_waived(self):
        with self.assertRaisesRegex(ValueError, "release-consistency"):
            ci.select_checks(["formatting", "pre-commit"], "native")

    def test_unknown_phase_fails(self):
        with self.assertRaisesRegex(ValueError, "unknown"):
            ci.select_checks(ci.SHARED_CHECKS, "other")


if __name__ == "__main__":
    unittest.main()
