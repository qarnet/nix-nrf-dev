#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
#
# Public-boundary unit tests for
# the dynamic project initializer (bin/commands/nix-nrf-init-project,
# packaged by nix/init-project/default.nix and published through
# apps.<system>.init-project).
#
# The suite runs in two modes:
#   - raw source standalone (default): the raw repository script is run
#     through the current interpreter; the suite constructs its own fake
#     nrfutil from tests/fixtures/nrfutil-search.py and points
#     NIX_NRF_INIT_NRFUTIL / NIX_NRF_INIT_SKELETON /
#     NIX_NRF_INIT_WEST_VERSIONS_JSON at test-controlled locations;
#   - packaged (NIX_NRF_INIT_PROJECT_COMMAND set by the check derivation):
#     the packaged public binary (makeWrapper script) is exec'd directly; the
#     wrapper's baked exact-store configuration (fake nrfutil package, real
#     west metadata, packaged skeleton) is used and never overridden.
#
# The fake sdk-manager search is driven by test-only environment variables:
#   NIX_NRF_INIT_FAKE_SEARCH_FILE   path to the emitted search JSON
#   NIX_NRF_INIT_FAKE_SEARCH_EXIT   simulated nonzero exit (network failure)
#   NIX_NRF_INIT_FAKE_SEARCH_STDERR simulated stderr for the failure
#   NIX_NRF_INIT_FAKE_LOG           appended JSON argv log (one line per call)
#
# No network, no real nrfutil, no sdk-manager state, no SDK/toolchain
# download. Run standalone from the repo:
#   python3 tests/unit/test_nix_nrf_init_project.py
# Wired as checks.init-project-tests in nix/flake/checks/init-project.nix.

import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

# West release literal used by the raw-source metadata list. Both modes prove
# the numeric semantic maximum; the packaged mode bakes the real versions.nix
# key list, the raw mode a synthetic list with a newer prerelease key.
RAW_WEST_VERSIONS_JSON = json.dumps(["v3.3.0", "v3.3.4", "v3.4.0-rc1", "v2.7.0"])

# Strict stable vMAJOR.MINOR.PATCH (no suffix), mirroring the initializer's
# west latest-selection grammar.
STRICT_STABLE_RE = re.compile(r"^v[0-9]+\.[0-9]+\.[0-9]+$")


def _repo_root():
    # The sandboxed check derivation copies the test to /build root, where
    # the repo-relative fallback cannot be computed (the derivation sets the
    # NIX_NRF_INIT_*_* variables instead); None means "unavailable".
    try:
        return pathlib.Path(__file__).resolve().parents[2]
    except IndexError:
        return None


def _resolve_command():
    configured = os.environ.get("NIX_NRF_INIT_PROJECT_COMMAND") or os.environ.get(
        "NIX_NRF_INIT_PROJECT_SCRIPT"
    )
    if configured:
        return configured
    root = _repo_root()
    if root is None:
        raise RuntimeError(
            "NIX_NRF_INIT_PROJECT_COMMAND is not set and the repo root is unavailable"
        )
    return str(root / "bin" / "commands" / "nix-nrf-init-project")


def _resolve_fixture():
    configured = os.environ.get("NIX_NRF_INIT_TEST_FIXTURE")
    if configured:
        return configured
    root = _repo_root()
    if root is None:
        return None
    return str(root / "tests" / "fixtures" / "nrfutil-search.py")


def _resolve_skeleton():
    configured = os.environ.get("NIX_NRF_INIT_TEST_SKELETON")
    if configured:
        return configured
    root = _repo_root()
    if root is None:
        return None
    return str(root / "nix" / "init-project" / "skeleton")


COMMAND = _resolve_command()
FIXTURE = _resolve_fixture()
SKELETON = _resolve_skeleton()
# The packaged public binary is a makeWrapper shell script and must be exec'd
# directly; the raw repository script runs through the current interpreter.
PACKAGED = bool(os.environ.get("NIX_NRF_INIT_PROJECT_COMMAND"))


def _strict_stable_max(versions):
    """Numeric semantic maximum among strict stable vMAJOR.MINOR.PATCH keys."""

    def key(version):
        return tuple(int(part) for part in version[1:].split("."))

    stable = [v for v in versions if STRICT_STABLE_RE.match(v)]
    return max(stable, key=key)


TEST_WEST_VERSIONS_JSON = os.environ.get(
    "NIX_NRF_INIT_TEST_WEST_VERSIONS_JSON", RAW_WEST_VERSIONS_JSON
)
# Expected west `latest` in every mode: the numeric semantic maximum among
# strict stable keys of exact metadata list under test. It does not use a
# hard-coded per-mode expectation.
TEST_WEST_VERSIONS = json.loads(TEST_WEST_VERSIONS_JSON)
TEST_WEST_LATEST = _strict_stable_max(TEST_WEST_VERSIONS)


def valid_entry(**overrides):
    entry = {
        "sdkStatus": {"local": "none", "remote": "available"},
        "sdkType": "nrf",
        "sdkVersion": "v3.3.0",
        "tags": ["stable"],
        "toolchains": [
            {
                "status": {"local": "none", "remote": "available"},
                "version": "v3.3.0",
            }
        ],
    }
    entry.update(overrides)
    return entry


class InitProjectTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="nix-nrf-init-test-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.fake_log = os.path.join(self.tmp, "fake-commands.log")
        self.fake_bin = None
        if not PACKAGED:
            self.fake_bin = self._install_fake()

    def _install_fake(self):
        assert FIXTURE is not None, "fake fixture unavailable in raw mode"
        fake_tmp = tempfile.mkdtemp(prefix="nix-nrf-init-fake-")
        self.addCleanup(shutil.rmtree, fake_tmp, True)
        bin_dir = os.path.join(fake_tmp, "bin")
        os.makedirs(bin_dir)
        dest = os.path.join(bin_dir, "nrfutil")
        with open(FIXTURE) as fh:
            content = fh.read()
        # Rewrite the shebang to the current interpreter: the raw fixture
        # uses `#!/usr/bin/env python3`, which the Nix build sandbox does not
        # provide. sys.executable works on the host and in the sandbox.
        body = content.split("\n", 1)[1]
        with open(dest, "w") as fh:
            fh.write(f"#!{sys.executable}\n{body}")
        os.chmod(dest, 0o755)
        return dest

    def make_env(
        self,
        fake_fail=False,
        fake_stderr=None,
        search_file=None,
        extra=None,
    ):
        env = os.environ.copy()
        env["NIX_NRF_INIT_FAKE_LOG"] = self.fake_log
        if not PACKAGED:
            # Raw mode owns the internal configuration; packaged mode inherits
            # the exact-store values baked by the wrapper.
            assert (
                self.fake_bin is not None and SKELETON is not None
            ), "raw mode requires the fake fixture and skeleton"
            env["NIX_NRF_INIT_NRFUTIL"] = self.fake_bin
            env["NIX_NRF_INIT_SKELETON"] = SKELETON
            env["NIX_NRF_INIT_WEST_VERSIONS_JSON"] = TEST_WEST_VERSIONS_JSON
        if fake_fail:
            env["NIX_NRF_INIT_FAKE_SEARCH_EXIT"] = "1"
            if fake_stderr:
                env["NIX_NRF_INIT_FAKE_SEARCH_STDERR"] = fake_stderr
        if search_file:
            env["NIX_NRF_INIT_FAKE_SEARCH_FILE"] = search_file
        if extra:
            env.update(extra)
        return env

    def run_init(self, argv, **kwargs):
        env = self.make_env(
            fake_fail=kwargs.pop("fake_fail", False),
            fake_stderr=kwargs.pop("fake_stderr", None),
            search_file=kwargs.pop("search_file", None),
            extra=kwargs.pop("env_extra", None),
        )
        cwd = kwargs.pop("cwd", None)
        self.assertFalse(kwargs, f"unexpected kwargs: {kwargs}")
        if PACKAGED:
            cmd = [COMMAND]
        else:
            cmd = [sys.executable, COMMAND]
        return subprocess.run(
            cmd + list(argv), env=env, capture_output=True, text=True, cwd=cwd
        )

    def write_search(self, payload):
        # A fresh unique file per call: the malformed-schema cases must each
        # execute their own payload, never share one overwritten path.
        fd, path = tempfile.mkstemp(prefix="search-", suffix=".json", dir=self.tmp)
        os.close(fd)
        with open(path, "w") as fh:
            json.dump(payload, fh)
        return path

    def write_raw_search(self, text):
        # Distinct unique file for malformed raw text (non-JSON) payloads.
        fd, path = tempfile.mkstemp(prefix="search-raw-", suffix=".json", dir=self.tmp)
        os.close(fd)
        with open(path, "w") as fh:
            fh.write(text)
        return path

    def fresh_dest(self, name="project"):
        return os.path.join(self.tmp, name)

    def assert_no_destination(self, dest):
        self.assertFalse(
            os.path.lexists(dest), f"destination unexpectedly exists: {dest}"
        )

    def assert_no_temp_siblings(self):
        leftovers = [p for p in os.listdir(self.tmp) if p.startswith(".nix-nrf-init-")]
        self.assertEqual(leftovers, [], f"temporary siblings left behind: {leftovers}")

    def assert_fake_never_called(self):
        self.assertFalse(
            os.path.exists(self.fake_log), "fake nrfutil was invoked unexpectedly"
        )

    def assert_fake_called_exactly(self, count=1):
        with open(self.fake_log) as fh:
            calls = [json.loads(line) for line in fh if line.strip()]
        expected = ["sdk-manager", "search", "--json", "--skip-overhead"]
        self.assertEqual(calls, [expected] * count)

    def read_flake(self, dest):
        path = os.path.join(dest, "flake.nix")
        self.assertTrue(os.path.isfile(path), f"flake.nix missing in {dest}")
        with open(path) as fh:
            return fh.read()

    # 1. Explicit exact nrfutil release: offline success while the fake is
    #    configured to fail if called; generated flake has the concrete
    #    version/backend; nothing on stdout.
    def test_explicit_nrfutil_version_is_offline_and_concrete(self):
        dest = self.fresh_dest()
        proc = self.run_init(
            [dest, "--backend", "nrfutil", "--ncs-version", "v3.3.0"],
            fake_fail=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stdout, "")
        self.assert_fake_never_called()
        content = self.read_flake(dest)
        self.assertIn('backend = "nrfutil"', content)
        self.assertIn('ncsVersion = "v3.3.0"', content)
        self.assertNotIn('"latest"', content)
        with open(os.path.join(dest, ".envrc")) as fh:
            self.assertEqual(fh.read(), "use flake\n")
        self.assertIn(f"created {dest}", proc.stderr)
        self.assertIn("backend nrfutil", proc.stderr)
        self.assertIn("NCS v3.3.0", proc.stderr)
        self.assert_no_temp_siblings()

    # 2. Default and explicit `latest` select the numeric semantic maximum
    #    stable release from unordered fake search JSON containing a newer
    #    RC/preview, another SDK type, a remote-SDK-unavailable entry, a
    #    no-remote-toolchain entry, and lower stable versions.
    def test_latest_selects_semantic_max_stable(self):
        payload = {
            "alerts": [],
            "entries": [
                # Unordered: semantic max v3.4.0 must win regardless of
                # response order and chronological recency (v3.3.4 is later).
                valid_entry(sdkVersion="v3.3.4", tags=["stable"]),
                valid_entry(
                    sdkVersion="v3.4.0-rc1",
                    tags=["RC"],
                    toolchains=[],
                ),
                valid_entry(
                    sdkVersion="v3.6.0-preview",
                    tags=["preview"],
                    sdkStatus={"local": "none", "remote": "available"},
                ),
                valid_entry(sdkType="toolchain", sdkVersion="v9.9.9"),
                valid_entry(
                    sdkVersion="v3.5.0",
                    sdkStatus={"local": "none", "remote": "unavailable"},
                ),
                valid_entry(
                    sdkVersion="v3.2.0",
                    toolchains=[
                        {
                            "status": {"local": "none", "remote": "unavailable"},
                            "version": "v3.2.0",
                        }
                    ],
                ),
                # The winner itself carries an unrelated tag that merely
                # contains the letters "rc" ("source"): exact per-tag blocking
                # must not exclude it (substring search would).
                valid_entry(sdkVersion="v3.4.0", tags=["source", "stable"]),
                valid_entry(sdkVersion="v3.3.0", tags=["stable"]),
            ],
        }
        search_file = self.write_search(payload)
        for argv in (
            [self.fresh_dest("default"), "--backend", "nrfutil"],
            [
                self.fresh_dest("explicit"),
                "--backend",
                "nrfutil",
                "--ncs-version",
                "latest",
            ],
        ):
            dest = argv[0]
            proc = self.run_init(argv, search_file=search_file)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            content = self.read_flake(dest)
            self.assertIn('ncsVersion = "v3.4.0"', content)
            self.assertNotIn('"latest"', content)
            self.assert_no_temp_siblings()
        self.assert_fake_called_exactly(count=2)

    # 3. SDK remote unavailable: no candidate and no destination.
    def test_remote_sdk_unavailable_yields_no_candidate(self):
        payload = {
            "entries": [
                valid_entry(
                    sdkVersion="v3.6.0",
                    sdkStatus={"local": "none", "remote": "unavailable"},
                )
            ]
        }
        search_file = self.write_search(payload)
        dest = self.fresh_dest()
        proc = self.run_init([dest, "--backend", "nrfutil"], search_file=search_file)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("init-project:", proc.stderr)
        self.assert_no_destination(dest)

    # 4. No remote toolchain: no candidate and no destination.
    def test_no_remote_toolchain_yields_no_candidate(self):
        payload = {
            "entries": [
                valid_entry(
                    sdkVersion="v3.6.0",
                    toolchains=[
                        {
                            "status": {"local": "none", "remote": "unavailable"},
                            "version": "v3.6.0",
                        }
                    ],
                )
            ]
        }
        search_file = self.write_search(payload)
        dest = self.fresh_dest()
        proc = self.run_init([dest, "--backend", "nrfutil"], search_file=search_file)
        self.assertNotEqual(proc.returncode, 0)
        self.assert_in_stderr(proc, "no stable remotely installable")
        self.assert_no_destination(dest)

    # 5. Malformed JSON and each malformed required schema class fail without
    #    files, each executing its own payload (every call writes a unique
    #    file) and reporting the expected field diagnostic.
    def test_malformed_search_output_fails_without_files(self):
        malformed_json = self.write_raw_search("not json {")

        cases = {
            "malformed-json": (
                malformed_json,
                "malformed JSON",
            ),
            "top-level-not-object": (
                self.write_search(["x"]),
                "expected a top-level object with an 'entries' list",
            ),
            "entries-not-list": (
                self.write_search({"entries": {}}),
                "expected a top-level object with an 'entries' list",
            ),
            "entry-not-object": (
                self.write_search({"entries": [42]}),
                "entries[0] is not an object",
            ),
            "sdkType-not-string": (
                self.write_search({"entries": [valid_entry(sdkType=5)]}),
                "entries[0].sdkType is not a string",
            ),
            "sdkVersion-not-string": (
                self.write_search({"entries": [valid_entry(sdkVersion=5)]}),
                "entries[0].sdkVersion is not a string",
            ),
            "tags-not-string-list": (
                self.write_search({"entries": [valid_entry(tags="stable")]}),
                "entries[0].tags is not a string list",
            ),
            "sdkStatus-missing": (
                self.write_search({"entries": [valid_entry(sdkStatus=None)]}),
                "entries[0].sdkStatus is not an object",
            ),
            "sdkStatus-remote-not-string": (
                self.write_search({"entries": [valid_entry(sdkStatus={"remote": 5})]}),
                "entries[0].sdkStatus.remote is not a string",
            ),
            "toolchains-not-list": (
                self.write_search({"entries": [valid_entry(toolchains={})]}),
                "entries[0].toolchains is not a list",
            ),
            "toolchain-not-object": (
                self.write_search({"entries": [valid_entry(toolchains=[42])]}),
                "entries[0].toolchains[0] is not an object",
            ),
            "toolchain-version-not-string": (
                self.write_search(
                    {
                        "entries": [
                            valid_entry(
                                toolchains=[
                                    {"status": {"remote": "available"}, "version": 5}
                                ]
                            )
                        ]
                    }
                ),
                "entries[0].toolchains[0].version is not a string",
            ),
            "toolchain-status-missing": (
                self.write_search(
                    {
                        "entries": [
                            valid_entry(
                                toolchains=[{"status": None, "version": "v3.3.0"}]
                            )
                        ]
                    }
                ),
                "entries[0].toolchains[0].status is not an object",
            ),
            "toolchain-status-remote-not-string": (
                self.write_search(
                    {
                        "entries": [
                            valid_entry(
                                toolchains=[
                                    {"status": {"remote": 5}, "version": "v3.3.0"}
                                ]
                            )
                        ]
                    }
                ),
                "entries[0].toolchains[0].status.remote is not a string",
            ),
        }
        for label, (search_file, expected_diagnostic) in cases.items():
            with self.subTest(label=label):
                dest = self.fresh_dest(label.replace("_", "-"))
                proc = self.run_init(
                    [dest, "--backend", "nrfutil"], search_file=search_file
                )
                self.assertNotEqual(proc.returncode, 0, proc.stderr)
                self.assert_in_stderr(proc, expected_diagnostic)
                self.assert_no_destination(dest)

    # 6. Empty / no-stable result fails without files.
    def test_empty_or_no_stable_result_fails_without_files(self):
        empty = self.write_search({"entries": []})
        dest = self.fresh_dest("empty")
        proc = self.run_init([dest, "--backend", "nrfutil"], search_file=empty)
        self.assertNotEqual(proc.returncode, 0)
        self.assert_no_destination(dest)

        only_rc = self.write_search(
            {
                "entries": [
                    valid_entry(
                        sdkVersion="v3.3.0-rc1",
                        tags=["RC"],
                        sdkStatus={"local": "none", "remote": "available"},
                    )
                ]
            }
        )
        dest = self.fresh_dest("only-rc")
        proc = self.run_init([dest, "--backend", "nrfutil"], search_file=only_rc)
        self.assertNotEqual(proc.returncode, 0)
        self.assert_in_stderr(proc, "no stable remotely installable")
        self.assert_no_destination(dest)

    # 7. Simulated sdk-manager nonzero/network failure preserves the useful
    #    diagnostic and creates nothing.
    def test_sdk_manager_failure_preserves_diagnostic_and_creates_nothing(self):
        dest = self.fresh_dest()
        proc = self.run_init(
            [dest, "--backend", "nrfutil"],
            fake_fail=True,
            fake_stderr="network error: SDK index unreachable",
        )
        self.assertNotEqual(proc.returncode, 0)
        self.assert_in_stderr(proc, "sdk-manager search failed")
        self.assert_in_stderr(proc, "network error: SDK index unreachable")
        self.assert_no_destination(dest)
        self.assert_fake_called_exactly(count=1)

    # 8. West omitted/`latest` resolves the semantic max from the local
    #    metadata (packaged versions.nix keys in packaged mode, the synthetic
    #    raw-mode list otherwise) and never invokes fake nrfutil; explicit
    #    west values must be exact metadata keys.
    def test_west_latest_resolves_from_local_metadata_without_nrfutil(self):
        # Derive expected value from exact metadata list under test. Do not use
        # a hard-coded per-mode expectation.
        expected = TEST_WEST_LATEST
        for selection in (None, "latest"):
            dest = self.fresh_dest(f"west-{selection or 'omitted'}")
            argv = [dest, "--backend", "west"]
            if selection:
                argv += ["--ncs-version", selection]
            proc = self.run_init(argv, fake_fail=True)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            content = self.read_flake(dest)
            self.assertIn('backend = "west"', content)
            self.assertIn(f'ncsVersion = "{expected}"', content)
            self.assertNotIn('"latest"', content)
            self.assert_no_temp_siblings()
        self.assert_fake_never_called()

    def test_west_explicit_version_must_be_in_metadata(self):
        # v3.3.0 stays the truthful explicit baseline while both metadata
        # lists support it; if it ever leaves the packaged metadata, fall
        # back to the derived semantic max so the assertion stays truthful.
        baseline = "v3.3.0" if "v3.3.0" in TEST_WEST_VERSIONS else TEST_WEST_LATEST
        dest = self.fresh_dest("supported")
        proc = self.run_init(
            [dest, "--backend", "west", "--ncs-version", baseline],
            fake_fail=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        content = self.read_flake(dest)
        self.assertIn('backend = "west"', content)
        self.assertIn(f'ncsVersion = "{baseline}"', content)

        unsupported = self.fresh_dest("unsupported")
        proc = self.run_init(
            [unsupported, "--backend", "west", "--ncs-version", "v9.9.9"]
        )
        self.assertEqual(proc.returncode, 2)
        self.assert_in_stderr(proc, "unsupported west release 'v9.9.9'")
        self.assert_no_destination(unsupported)

    # An unrelated tag that merely contains the letters "rc" (e.g.
    #     "source") does not exclude a strict stable candidate: blocking is
    #     exact per normalized tag ({unstable, preview, rc}), never a
    #     substring search. The strict version regex separately rejects RC/
    #     preview version suffixes even with stable tags.
    def test_unrelated_rc_letter_tag_does_not_exclude_candidate(self):
        payload = {
            "entries": [
                valid_entry(sdkVersion="v3.7.0", tags=["source", "stable"]),
                valid_entry(
                    sdkVersion="v3.7.1-rc1",
                    tags=["stable"],
                    sdkStatus={"local": "none", "remote": "available"},
                ),
            ]
        }
        search_file = self.write_search(payload)
        dest = self.fresh_dest()
        proc = self.run_init([dest, "--backend", "nrfutil"], search_file=search_file)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        content = self.read_flake(dest)
        self.assertIn('ncsVersion = "v3.7.0"', content)

    # 9. Invalid backend, invalid release syntax, unsupported explicit west
    #    release, and --force exit 2 and leave no destination.
    def test_usage_errors_exit_2(self):
        cases = [
            [
                self.fresh_dest("backend"),
                "--backend",
                "bogus",
                "--ncs-version",
                "v3.3.0",
            ],
            [
                self.fresh_dest("syntax-a"),
                "--backend",
                "nrfutil",
                "--ncs-version",
                "v3.3",
            ],
            [
                self.fresh_dest("syntax-b"),
                "--backend",
                "nrfutil",
                "--ncs-version",
                "3.3.0",
            ],
            [self.fresh_dest("syntax-c"), "--backend", "west", "--ncs-version", "v3.3"],
            [
                self.fresh_dest("west-unsupported"),
                "--backend",
                "west",
                "--ncs-version",
                "v9.9.9",
            ],
            [self.fresh_dest("force"), "--backend", "nrfutil", "--force"],
        ]
        for argv in cases:
            dest = argv[0]
            with self.subTest(dest=dest):
                proc = self.run_init(argv)
                self.assertEqual(proc.returncode, 2, proc.stderr)
                self.assertIn("init-project:", proc.stderr)
                self.assert_no_destination(dest)

    # 10. Existing flake.nix collision preserves the sentinel and creates no
    #     .envrc.
    def test_existing_flake_nix_collision_preserves_sentinel(self):
        dest = self.fresh_dest()
        os.makedirs(dest)
        sentinel = "pre-existing flake content\n"
        with open(os.path.join(dest, "flake.nix"), "w") as fh:
            fh.write(sentinel)
        proc = self.run_init(
            [dest, "--backend", "nrfutil", "--ncs-version", "v3.3.0"],
            fake_fail=True,
        )
        self.assertNotEqual(proc.returncode, 0)
        self.assert_in_stderr(proc, "refusing to overwrite existing flake.nix")
        with open(os.path.join(dest, "flake.nix")) as fh:
            self.assertEqual(fh.read(), sentinel)
        self.assertFalse(os.path.exists(os.path.join(dest, ".envrc")))
        self.assert_no_temp_siblings()

    # 11. Generated-target symlink and destination/parent symlink escape
    #     attempts are rejected while the external sentinel/target stays
    #     unchanged.
    def test_symlink_escape_attempts_rejected(self):
        external = os.path.join(self.tmp, "external")
        os.makedirs(external)
        sentinel = "external sentinel\n"
        sentinel_path = os.path.join(external, "target.txt")
        with open(sentinel_path, "w") as fh:
            fh.write(sentinel)

        # (a) generated-target symlink: .envrc -> external file.
        dest_a = os.path.join(self.tmp, "a")
        os.makedirs(dest_a)
        os.symlink(sentinel_path, os.path.join(dest_a, ".envrc"))
        proc = self.run_init(
            [dest_a, "--backend", "nrfutil", "--ncs-version", "v3.3.0"],
            fake_fail=True,
        )
        self.assertNotEqual(proc.returncode, 0)
        self.assertFalse(os.path.exists(os.path.join(dest_a, "flake.nix")))
        with open(sentinel_path) as fh:
            self.assertEqual(fh.read(), sentinel)

        # (b) destination itself is a symlink to an external directory.
        dest_b = os.path.join(self.tmp, "b")
        os.symlink(external, dest_b)
        proc = self.run_init(
            [dest_b, "--backend", "nrfutil", "--ncs-version", "v3.3.0"],
            fake_fail=True,
        )
        self.assertNotEqual(proc.returncode, 0)
        self.assertFalse(os.path.exists(os.path.join(external, "flake.nix")))
        self.assertFalse(os.path.exists(os.path.join(external, ".envrc")))

        # (c) parent component is a symlink to an external directory.
        link_parent = os.path.join(self.tmp, "linkparent")
        os.symlink(external, link_parent)
        dest_c = os.path.join(link_parent, "project")
        proc = self.run_init(
            [dest_c, "--backend", "nrfutil", "--ncs-version", "v3.3.0"],
            fake_fail=True,
        )
        self.assertNotEqual(proc.returncode, 0)
        self.assertFalse(os.path.exists(os.path.join(external, "project")))
        with open(sentinel_path) as fh:
            self.assertEqual(fh.read(), sentinel)
        self.assert_no_temp_siblings()

    # 12. Existing unrelated directory is preserved while generated files are
    #     added.
    def test_existing_unrelated_directory_preserved(self):
        dest = self.fresh_dest()
        os.makedirs(dest)
        unrelated = "notes.txt"
        with open(os.path.join(dest, unrelated), "w") as fh:
            fh.write("keep me\n")
        proc = self.run_init(
            [dest, "--backend", "nrfutil", "--ncs-version", "v3.3.0"],
            fake_fail=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        with open(os.path.join(dest, unrelated)) as fh:
            self.assertEqual(fh.read(), "keep me\n")
        self.assertTrue(os.path.isfile(os.path.join(dest, "flake.nix")))
        self.assertTrue(os.path.isfile(os.path.join(dest, ".envrc")))
        self.assert_no_temp_siblings()

    # 13. Default destination `.`, --non-interactive, --help, and the success
    #     summary line.
    def test_default_destination_non_interactive_help_and_summary(self):
        cwd = os.path.join(self.tmp, "cwd")
        os.makedirs(cwd)
        proc = self.run_init(
            ["--backend", "nrfutil", "--ncs-version", "v3.3.0", "--non-interactive"],
            cwd=cwd,
            fake_fail=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertTrue(os.path.isfile(os.path.join(cwd, "flake.nix")))
        self.assertTrue(os.path.isfile(os.path.join(cwd, ".envrc")))
        self.assertEqual(proc.stdout, "")
        self.assert_in_stderr(proc, "created .")
        self.assert_in_stderr(proc, "backend nrfutil")
        self.assert_in_stderr(proc, "NCS v3.3.0")

        proc = self.run_init(["--help"])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("nix-nrf-init-project", proc.stdout)

    # 14. Generated file set is exactly .envrc and flake.nix.
    def test_generated_file_set_is_exactly_envrc_and_flake(self):
        dest = self.fresh_dest()
        proc = self.run_init(
            [dest, "--backend", "nrfutil", "--ncs-version", "v3.3.0"],
            fake_fail=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(sorted(os.listdir(dest)), [".envrc", "flake.nix"])
        self.assert_no_temp_siblings()

    def assert_in_stderr(self, proc, text):
        self.assertIn(text, proc.stderr, f"stderr was: {proc.stderr!r}")


if __name__ == "__main__":
    unittest.main()
