# Nordic advertised artifact metadata

This is a metadata-only research catalog, not a package lock or a complete mirror
of Nordic's Artifactory. It is never queried by consumer shell entry or Nix
evaluation. No SDK/toolchain/Python archive is downloaded by the collector.

`scripts/nordic_artifact_catalog.py` collects nine public metadata responses:
repository names, SDK/toolchain/nrfutil configuration, all SDK source schema
branches, both Linux toolchain indexes, and both Linux sdk-manager package indexes.
Nordic's published indexes are cheaper and clearer than recursive storage crawling;
the package indexes already use JSONL upstream.

Each snapshot contains:

- `catalog.jsonl`: sorted records with kind, scope, source URL and preserved
  upstream data. Selectors and duplicate mappings are not discarded.
- `manifest.json`: observation time, exact response digests and byte counts,
  source-level outcomes/counts, catalog digest, and explicit coverage exclusions.

An empty platform index is recorded as a successful zero-record observation.
A failed request/HTML response is recorded as a failure, not evidence of an empty
inventory. `captured` means the chosen published sources were captured; it does
not mean all server artifacts or runtime support were verified. Index response
digests are distinct from artifact digests contained in those responses.

Excluded: orphaned/unadvertised files, non-Linux platform indexes, Python wheel
inventory, archive contents and compatibility qualification. Basic Storage API
calls can enrich selected records later; anonymous bulk listing returned 403 and
AQL requires authentication. No credentials or bypass are used.

Refresh deliberately into a **new** directory, review the diff, and retain or
replace snapshots only through normal authorized Git work:

```sh
python3 -B scripts/nordic_artifact_catalog.py \
  --output /tmp/opencode/nordic-artifacts-new-snapshot
python3 -B tests/unit/test_nordic_artifact_catalog.py
```

The same hardware-free HTTP/CLI tests run in
`checks.<system>.nordic-artifact-catalog-tests` without external network access.
Acquisition/coverage research is PB-029; release update automation is separate
PB-030 through PB-033.

Requests have timeouts, a two-MiB per-response limit, a fixed nine-source scope,
same-origin redirects, and a short delay. Failures preserve a partial snapshot and
produce nonzero exit status; an existing output directory is never overwritten.

Example query (jq optional, not a consumer dependency):

```sh
jq -c 'select(.kind == "toolchain" and .data.key == "v3.4.1")' \
  docs/research/nordic-artifacts/2026-10-06/catalog.jsonl
```

Broader acquisition/export alternatives and maintainer/consumer policy are in
[Nordic artifact metadata research](../../development/nordic-artifact-metadata-research.md).
