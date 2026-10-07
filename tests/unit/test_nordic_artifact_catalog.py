"""Public CLI tests using real HTTP fixture responses, without Nordic traffic."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest

SCRIPT = (
    Path(os.environ["NORDIC_ARTIFACT_CATALOG_SCRIPT"])
    if os.environ.get("NORDIC_ARTIFACT_CATALOG_SCRIPT")
    else Path(__file__).resolve().parents[2] / "scripts/nordic_artifact_catalog.py"
)


class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.output = Path(self.temp.name) / "snapshot"
        self.paths = []
        self.bad = False
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, format, *args):
                pass

            def do_GET(self):
                outer.paths.append(self.path)
                if outer.bad == "redirect" and self.path.endswith(
                    "index-linux-x86_64.json"
                ):
                    self.send_response(302)
                    self.send_header(
                        "Location", "https://outside.invalid/artifact.tar.gz"
                    )
                    self.end_headers()
                    return
                if self.path.endswith("config.json"):
                    payload = {"versions": {"1": {}}}
                elif "sdk-manager/index.json" in self.path:
                    payload = {
                        "versions": {
                            "1": {"bundles": [{"version": "old", "sha512": "a"}]},
                            "3": {
                                "types": {},
                                "bundles": [{"version": "new", "sha512": "b"}],
                            },
                        }
                    }
                elif self.path.endswith("index-linux-aarch64.json"):
                    payload = []
                elif "/bundles/v3/" in self.path:
                    payload = [
                        {
                            "json_api_version": 2,
                            "key": "v3.4.1",
                            "metadata": {"version": "bundle-id", "sha512": "c"},
                        }
                    ]
                else:
                    payload = [{"key": "NCS", "type": "LOCAL"}]
                raw = json.dumps(payload).encode()
                if self.path.endswith("/nrfutil-sdk-manager"):
                    raw = b'{"name":"sdk-manager","vers":"1.16.1","cksum":"d","yanked":false}\n'
                if outer.bad and self.path.endswith("index-linux-x86_64.json"):
                    raw = b"<html>JFrog</html>"
                self.send_response(200)
                self.end_headers()
                self.wfile.write(raw)

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)

    def run_catalog(self, *extra):
        return subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--origin",
                f"http://127.0.0.1:{self.server.server_port}",
                "--output",
                str(self.output),
                "--delay",
                "0",
                *extra,
            ],
            capture_output=True,
            text=True,
            timeout=15,
        )

    def test_complete_advertised_capture_preserves_branches_and_empty_platform(self):
        result = self.run_catalog()
        self.assertEqual(result.returncode, 0, result.stderr)
        records = [
            json.loads(line)
            for line in (self.output / "catalog.jsonl").read_text().splitlines()
        ]
        self.assertEqual(
            {
                record["schema_branch"]
                for record in records
                if record["kind"] == "sdk-source"
            },
            {"1", "3"},
        )
        manifest = json.loads((self.output / "manifest.json").read_text())
        arm = [
            source
            for source in manifest["sources"]
            if source["kind"] == "toolchain"
            and source["scope"] == "aarch64-unknown-linux-gnu"
        ][0]
        self.assertEqual((arm["status"], arm["records"]), ("pass", 0))
        self.assertEqual(len(self.paths), 9)
        self.assertTrue(
            all(".tar" not in path and "api/search" not in path for path in self.paths)
        )
        self.assertIn("not a full Artifactory mirror", manifest["scope"])
        before = (self.output / "catalog.jsonl").read_bytes()
        self.assertEqual(manifest["catalog_sha256"], hashlib.sha256(before).hexdigest())
        self.assertNotEqual(self.run_catalog().returncode, 0)
        self.assertEqual((self.output / "catalog.jsonl").read_bytes(), before)
        self.output = Path(self.temp.name) / "second-snapshot"
        self.assertEqual(self.run_catalog().returncode, 0)
        self.assertEqual((self.output / "catalog.jsonl").read_bytes(), before)

    def test_html_response_is_explicit_partial_not_empty_success(self):
        self.bad = True
        self.assertEqual(self.run_catalog().returncode, 1)
        manifest = json.loads((self.output / "manifest.json").read_text())
        self.assertEqual(manifest["outcome"], "partial")
        self.assertTrue(
            any(source["status"] == "fail" for source in manifest["sources"])
        )
        self.assertGreater(manifest["records"], 0)

    def test_cross_origin_redirect_is_refused_before_following_it(self):
        self.bad = "redirect"
        self.assertEqual(self.run_catalog().returncode, 1)
        manifest = json.loads((self.output / "manifest.json").read_text())
        errors = [
            source["error"]
            for source in manifest["sources"]
            if source["status"] == "fail"
        ]
        self.assertEqual(errors, ["cross-origin metadata redirect refused"])

    def test_byte_limit_retains_failure_coverage(self):
        self.assertEqual(self.run_catalog("--max-response-bytes", "1").returncode, 1)
        manifest = json.loads((self.output / "manifest.json").read_text())
        self.assertEqual(manifest["records"], 0)
        self.assertTrue(
            all("byte limit" in source["error"] for source in manifest["sources"])
        )


if __name__ == "__main__":
    unittest.main()
