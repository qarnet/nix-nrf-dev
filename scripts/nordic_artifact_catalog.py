"""Snapshot advertised Nordic artifact metadata as JSONL; never fetch artifacts."""

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import time
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

BASE = "/artifactory"
SOURCES = [
    ("repositories", None, f"{BASE}/api/repositories"),
    ("configuration", "toolchains", f"{BASE}/NCS/external/bundles/config.json"),
    (
        "configuration",
        "sdk-sources",
        f"{BASE}/ncs-src-mirror/external/sdk-manager/config.json",
    ),
    (
        "configuration",
        "nrfutil-packages",
        f"{BASE}/swtools/external/nrfutil/index/config.json",
    ),
    ("sdk-source", None, f"{BASE}/ncs-src-mirror/external/sdk-manager/index.json"),
]
for platform, filename in (
    ("x86_64-unknown-linux-gnu", "linux-x86_64"),
    ("aarch64-unknown-linux-gnu", "linux-aarch64"),
):
    SOURCES.extend(
        [
            (
                "toolchain",
                platform,
                f"{BASE}/NCS/external/bundles/v3/index-{filename}.json",
            ),
            (
                "nrfutil-package",
                platform,
                f"{BASE}/swtools/external/nrfutil/index/{platform}/nrfutil-sdk-manager",
            ),
        ]
    )


class SameOriginRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if urlsplit(newurl)[:2] != urlsplit(req.full_url)[:2]:
            raise ValueError("cross-origin metadata redirect refused")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def records(kind, scope, source, payload):
    """Preserve source schemas and duplicates rather than invent a universal lock."""
    prefix = {"kind": kind, "source": source, "availability": "advertised"}
    if scope is not None:
        prefix["scope"] = scope
    if kind == "configuration":
        if not isinstance(payload, dict):
            raise ValueError("configuration must be an object")
        return [dict(prefix, data=payload)]
    if kind == "sdk-source":
        versions = payload["versions"]
        if not isinstance(versions, dict):
            raise ValueError("SDK versions must be schema branches")
        result = []
        for branch, data in versions.items():
            if not isinstance(data["bundles"], list):
                raise ValueError("SDK bundles must be a list")
            result.extend(
                dict(prefix, schema_branch=branch, data=item)
                for item in data["bundles"]
            )
            result.append(
                dict(
                    prefix,
                    kind="sdk-schema",
                    schema_branch=branch,
                    data={
                        key: value for key, value in data.items() if key != "bundles"
                    },
                )
            )
        return result
    if not isinstance(payload, list) or not all(
        isinstance(item, dict) for item in payload
    ):
        raise ValueError("index must be a list of objects")
    if kind == "toolchain" and any(
        item.get("json_api_version") not in (1, 2) for item in payload
    ):
        raise ValueError("unsupported toolchain index schema")
    return [dict(prefix, data=item) for item in payload]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output", required=True, type=Path, help="new directory; refuses overwriting"
    )
    parser.add_argument(
        "--origin",
        default="https://files.nordicsemi.com",
        help="HTTPS origin; HTTP loopback allowed for fixture tests",
    )
    parser.add_argument("--timeout", type=float, default=30)
    parser.add_argument("--max-response-bytes", type=int, default=2 * 1024 * 1024)
    parser.add_argument("--delay", type=float, default=0.25)
    args = parser.parse_args()
    parsed = urlsplit(args.origin)
    loopback = parsed.scheme == "http" and parsed.hostname in (
        "127.0.0.1",
        "localhost",
        "::1",
    )
    if (
        (parsed.scheme != "https" and not loopback)
        or parsed.username
        or parsed.password
        or parsed.path
        or parsed.query
        or parsed.fragment
        or not parsed.hostname
    ):
        parser.error("origin must be credential-free HTTPS origin or HTTP loopback")
    if args.timeout <= 0 or args.max_response_bytes <= 0 or args.delay < 0:
        parser.error("invalid request limits")
    output = args.output.resolve()
    output.mkdir(mode=0o755, exist_ok=False)
    manifest = {
        "schema": 1,
        "observed_at": datetime.now(timezone.utc).isoformat(),
        "outcome": "partial",
        "scope": "published SDK source selectors, Linux toolchain selectors, and Linux sdk-manager package versions; not a full Artifactory mirror",
        "not_covered": [
            "unadvertised/orphaned artifacts",
            "other host indexes",
            "Python distribution files",
            "archive contents or runtime compatibility",
        ],
        "sources": [],
    }
    opener = build_opener(SameOriginRedirect())
    catalog = []
    for kind, scope, path in SOURCES:
        url = args.origin + path
        evidence = {"url": url, "kind": kind, "scope": scope}
        try:
            with opener.open(
                Request(
                    url,
                    headers={
                        "Accept": "application/json, application/x-ndjson, */*",
                        "User-Agent": "nix-nrf-dev-metadata-catalog/1",
                    },
                ),
                timeout=args.timeout,
            ) as response:
                raw = response.read(args.max_response_bytes + 1)
                if len(raw) > args.max_response_bytes:
                    raise ValueError("metadata response exceeds byte limit")
                evidence.update(
                    content_type=response.headers.get("Content-Type"),
                    etag=response.headers.get("ETag"),
                    last_modified=response.headers.get("Last-Modified"),
                    bytes=len(raw),
                    sha256=hashlib.sha256(raw).hexdigest(),
                )
            text = raw.decode("utf-8")
            payload = (
                [json.loads(line) for line in text.splitlines() if line.strip()]
                if kind == "nrfutil-package"
                else json.loads(text)
            )
            entries = records(kind, scope, url, payload)
            catalog.extend(entries)
            evidence.update(status="pass", records=len(entries))
        except (OSError, ValueError, KeyError, TypeError) as exc:
            evidence.update(status="fail", error=str(exc))
        manifest["sources"].append(evidence)
        time.sleep(args.delay)
    lines = sorted(
        json.dumps(record, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
        for record in catalog
    )
    encoded = ("\n".join(lines) + ("\n" if lines else "")).encode()
    (output / "catalog.jsonl").write_bytes(encoded)
    manifest.update(
        records=len(catalog),
        counts=dict(sorted(Counter(record["kind"] for record in catalog).items())),
        catalog_sha256=hashlib.sha256(encoded).hexdigest(),
    )
    if all(source["status"] == "pass" for source in manifest["sources"]):
        manifest["outcome"] = "captured"
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({key: manifest[key] for key in ("outcome", "records", "counts")}))
    return 0 if manifest["outcome"] == "captured" else 1


if __name__ == "__main__":
    raise SystemExit(main())
