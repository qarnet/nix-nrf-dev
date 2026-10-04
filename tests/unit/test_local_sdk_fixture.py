"""Real local Git/west fixture lifecycle, without SDK downloads or firmware builds."""

import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import yaml
from west.manifest import Manifest, ManifestImportFailed

sys.path.insert(0, os.environ["LOCAL_FIXTURE_HELPERS"])
from local_workspace import (
    FixtureError,
    git,
    prepare,
    seed_repo,
    snapshot,
    verify_original,
)


class LocalFixtureTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.sdk = self.root / "sdk"
        self.sdk.mkdir()
        self.nrf, self.zephyr, self.probe = (
            self.sdk / "nrf",
            self.sdk / "zephyr",
            self.sdk / "modules/probe",
        )
        for repo in (self.nrf, self.zephyr, self.probe):
            repo.mkdir(parents=True)
        (self.probe / "probe.txt").write_text("original source bytes\n")
        probe_sha = seed_repo(self.probe)
        (self.zephyr / "west.yml").write_text(
            yaml.safe_dump(
                {
                    "manifest": {
                        "projects": [
                            {
                                "name": "probe",
                                "url": str(self.probe),
                                "path": "modules/probe",
                                "revision": probe_sha,
                            }
                        ]
                    }
                }
            )
        )
        zephyr_sha = seed_repo(self.zephyr)
        git(self.zephyr, "update-ref", "refs/heads/manifest-rev", zephyr_sha)
        (self.nrf / "Kconfig.nrf").write_text("# Nordic fixture sentinel\n")
        (self.nrf / "VERSION").write_text("3.3.0\n")
        (self.nrf / "west.yml").write_text(
            yaml.safe_dump(
                {
                    "manifest": {
                        "projects": [
                            {
                                "name": "zephyr",
                                "url": str(self.zephyr),
                                "revision": zephyr_sha,
                                "import": {"name-allowlist": ["probe"]},
                            }
                        ]
                    }
                }
            )
        )
        seed_repo(self.nrf)
        (self.sdk / ".west").mkdir()
        (self.sdk / ".west/config").write_text("[manifest]\npath = nrf\n")
        self.fixture = Path(os.environ["LOCAL_APPLICATION_FIXTURE"])

    def prepare(self, path=None, **kwargs):
        return prepare(
            self.sdk,
            path or self.root / "independent",
            self.fixture,
            reserve_bytes=0,
            **kwargs,
        )

    def test_independent_imports_refs_and_working_files(self):
        before = snapshot(self.nrf)
        plan = self.prepare()
        root = Path(plan["destination"])
        manifest = Manifest.from_topdir(topdir=root)
        self.assertEqual(manifest.get_projects(["nrf"])[0].path, "sdk/nrf")
        self.assertEqual(manifest.get_projects(["zephyr"])[0].path, "sdk/rtos")
        self.assertEqual(manifest.get_projects(["probe"])[0].path, "sdk/modules/probe")
        self.assertEqual(
            manifest.get_projects(["source_import_probe"])[0].path,
            "modules/source_import_probe",
        )
        self.assertEqual(
            git(root / "sdk/nrf", "rev-parse", "refs/heads/manifest-rev"),
            before["head"],
        )
        copy = root / "sdk/modules/probe/probe.txt"
        self.assertFalse(os.path.samefile(copy, self.probe / "probe.txt"))
        copy.write_text("changed copied working tree\n")
        self.assertEqual(
            (self.probe / "probe.txt").read_text(), "original source bytes\n"
        )
        verify_original(plan)
        self.assertEqual(snapshot(self.nrf), before)

    def test_existing_destination_is_preserved(self):
        output = self.root / "existing"
        output.mkdir()
        (output / "sentinel").write_text("keep")
        with self.assertRaisesRegex(FixtureError, "must not exist"):
            self.prepare(output)
        self.assertEqual((output / "sentinel").read_text(), "keep")

    def test_dirty_inputs_and_budget_do_not_create_workspace(self):
        with self.assertRaisesRegex(FixtureError, "copy budget"):
            self.prepare(max_bytes=1)
        self.assertFalse((self.root / "independent").exists())
        (self.nrf / "VERSION").write_text("dirty input\n")
        with self.assertRaisesRegex(FixtureError, "dirty source"):
            self.prepare()
        self.assertFalse((self.root / "independent").exists())
        self.assertEqual((self.nrf / "VERSION").read_text(), "dirty input\n")

    def test_missing_local_import_ref_never_repairs_or_acquires(self):
        git(self.zephyr, "update-ref", "-d", "refs/heads/manifest-rev")
        with self.assertRaises(ManifestImportFailed):
            self.prepare()
        self.assertFalse((self.root / "independent").exists())
        self.assertEqual(
            git(self.zephyr, "show-ref", "refs/heads/manifest-rev", check=False), ""
        )

    def test_missing_project_revision_does_not_create_workspace(self):
        data = yaml.safe_load((self.zephyr / "west.yml").read_text())
        data["manifest"]["projects"][0]["revision"] = "f" * 40
        (self.zephyr / "west.yml").write_text(yaml.safe_dump(data))
        sha = seed_repo(self.zephyr)
        git(self.zephyr, "update-ref", "refs/heads/manifest-rev", sha)
        data = yaml.safe_load((self.nrf / "west.yml").read_text())
        data["manifest"]["projects"][0]["revision"] = sha
        (self.nrf / "west.yml").write_text(yaml.safe_dump(data))
        seed_repo(self.nrf)
        before = snapshot(self.probe)
        with self.assertRaisesRegex(FixtureError, "rev-parse"):
            self.prepare()
        self.assertFalse((self.root / "independent").exists())
        self.assertEqual(snapshot(self.probe), before)

    def test_free_space_shortage_does_not_create_workspace(self):
        # Only the resource probe is substituted; Git/west and preparation are real.
        from collections import namedtuple

        usage = namedtuple("usage", "total used free")(100, 100, 0)
        with patch("local_workspace.shutil.disk_usage", return_value=usage):
            with self.assertRaisesRegex(FixtureError, "insufficient free space"):
                self.prepare()
        self.assertFalse((self.root / "independent").exists())

    def test_absolute_symlink_is_refused_before_copy(self):
        (self.probe / "external").symlink_to(self.root / "outside")
        git(self.probe, "add", "external")
        git(
            self.probe,
            "-c",
            "user.name=Fixture",
            "-c",
            "user.email=fixture@example.invalid",
            "commit",
            "-qm",
            "external link",
        )
        probe_sha = git(self.probe, "rev-parse", "HEAD")
        zdata = yaml.safe_load((self.zephyr / "west.yml").read_text())
        zdata["manifest"]["projects"][0]["revision"] = probe_sha
        (self.zephyr / "west.yml").write_text(yaml.safe_dump(zdata))
        zephyr_sha = seed_repo(self.zephyr)
        git(self.zephyr, "update-ref", "refs/heads/manifest-rev", zephyr_sha)
        ndata = yaml.safe_load((self.nrf / "west.yml").read_text())
        ndata["manifest"]["projects"][0]["revision"] = zephyr_sha
        (self.nrf / "west.yml").write_text(yaml.safe_dump(ndata))
        seed_repo(self.nrf)
        with self.assertRaisesRegex(FixtureError, "absolute source symlink"):
            self.prepare()
        self.assertFalse((self.root / "independent").exists())


if __name__ == "__main__":
    unittest.main()
