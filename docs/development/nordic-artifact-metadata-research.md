# Nordic artifact metadata and locked release maintenance

Read-only findings recorded on 2026-10-06. The implementation session remains
paused. This note records verified evidence and recommendations, not approval to
install packages, implement a crawler, or enable an automated updater.

## Verified release identity chain

For sdk-nrf v3.4.1, commit
`b20f8619ba9a5530f8c34b0a130d829947cfe55d`, the Linux checksum script hashes
`scripts/requirements-fixed.txt` followed by `scripts/tools-versions-linux.yml`,
normalizes carriage returns at line ends, and takes the first ten SHA-256 hex
characters. It selects the tools file by OS, not CPU architecture.

An independent computation from the two Git blobs produced:

```text
SHA-256: 8285d8ad56edc038db6b345e8e85b39a099da4531bb6cdbc36541e9194efe428
Bundle ID: 8285d8ad56
```

That ID matches the published v3.4.1 Linux amd64 index entry and the isolated
installed bundle's `manifest.json`. The archive filename is
`ncs-toolchain-x86_64-linux-8285d8ad56.tar.gz`; the index supplies a full SHA-512.
The ten-character ID is a metadata fingerprint, not archive integrity proof or
proof that the whole SDK source tree is identical.

Installed manifest provenance names a PR snapshot (`PR-30809`, commit
`12dd622f18e1f8ba940fe9e5460d5890f8b499e9`), not the v3.4.1 tag itself. SDK source
identity and toolchain build identity must therefore remain separate.

Nordic's source-mirroring action uses this checksum to find a matching index
record in one path, but also supports explicit toolchain-version input and tag
release selection. Do not assume every release mapping must always be derived by
the same action branch or that mappings are one-to-one.

Sources:

- [Tagged checksum script](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/scripts/print_toolchain_checksum.sh)
- [Tagged Linux tools metadata](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/scripts/tools-versions-linux.yml)
- [Source-mirroring action](https://github.com/nrfconnect/action-src-mirror/blob/main/action.yml)
- [Linux amd64 index](https://files.nordicsemi.com/artifactory/NCS/external/bundles/v3/index-linux-x86_64.json)

## Why the fixed file contains extras

`requirements-fixed.txt` is an installable pinned **requirements** file, not a
pip **constraints** file. Tagged upstream west-command CI explicitly runs:

```sh
pip3 install -r nrf/scripts/requirements-fixed.txt -r nrf/scripts/requirements-west-ncs-sbom.txt
```

v3.4.1 contains both `pyjwt==2.13.0` and `pyjwt[crypto]==2.13.0`. PyGithub requests
the crypto extra, while nrfcloud-utils requests bare PyJWT. Both select the same
distribution; the extra additionally activates cryptography dependencies.

Pip supports that syntax for `-r`. It forbids extras for `-c`; the inspected pip
validator returns `Constraints cannot have extras`. The fixed file's
`--index-url` is package-source configuration, not a version constraint. It also
contains Nordic-specific versions such as `x690==1.0.0.post2+nordic`.

Consequently, the suggested `pip install -c requirements-fixed.txt ...` is not a
drop-in change. A derived constraints view must normalize extras to base-package
pins, preserve environment markers, validate syntax, deduplicate equivalent
pins, and handle index policy separately. Optional extras must still be requested
by the selected requirement groups, not activated through constraints.

This version-pinned file has no package hashes. It improves version repeatability
but does not, by itself, lock wheel/source artifact bytes or establish ARM64
availability. Ordinary constraints also do not universally lock isolated package
build environments; build-dependency policy needs separate verification.

Sources:

- [Tagged fixed requirements](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/scripts/requirements-fixed.txt), lines 7, 123-124, 192.
- [Actual pip installation in upstream CI](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/.github/workflows/west-commands.yml#L60-L63)
- [Pip constraints semantics](https://pip.pypa.io/en/stable/user_guide/#constraints-files)

## Generator versus installer

The tagged validation workflow installs
`pip-compile-cross-platform==1.4.2+nordic.3`. Inspection of that exact Nordic
wheel found a Poetry-backed generator: it creates a temporary project, resolves
requirements through Poetry, and exports a pip-compatible requirements file.
It can preserve existing output pins through its temporary lock procedure.

This does not mean Poetry installs the final SDK environment. The verified SDK
CI consumer uses pip. Newer public generator versions may use uv; that must not
be confused with Nordic's pinned generator variant. The proprietary toolchain
bundler's exact Python installation command/order remains unverified.

JFrog's pip/Poetry/uv setup instructions describe clients that can use a Python
repository; their presence is not evidence of which client Nordic used to build
a particular SDK bundle.

Sources:

- [Tagged fixed-file validation workflow](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/.github/workflows/validate-pip-requirements-fixed-file.yml)
- [Exact Nordic generator wheel](https://files.nordicsemi.com/artifactory/api/pypi/nordic-pypi/pip-compile-cross-platform/1.4.2+nordic.3/pip_compile_cross_platform-1.4.2+nordic.3-py3-none-any.whl)
- Wheel SHA-256 verified during read-only inspection:
  `4b2ea26831d61ed418135b2f1c4651b522f7e7d2db6673abf5b607c2789ef5fb`.

## West-version discrepancy: verified origin

v3.4.1 records three different roles:

| Role | Value |
| --- | --- |
| Nordic base requirement | `west>=1.4.0` |
| Linux tools YAML | `west: 1.4.0` |
| Fixed Python resolution | `west==1.5.0` |

The installed `8285d8ad56` bundle contains `west-1.5.0.dist-info/METADATA`, whose
version is 1.5.0. Its Python installation therefore agrees with the fixed file,
not the YAML west field.

History explains when these values diverged:

1. Commit `83e823730a2a67a3fc56b9a1f538cc01c77487a2` (May 2025) updated the base
   minimum, fixed pin, and Linux YAML together to 1.4.0.
2. Commit `5f1e23566c6af7f1dac802a7e96729d7126d2d50` (January 2026), "tools:
   Update pip packages", changed only `scripts/requirements-fixed.txt`, moving
   west to 1.5.0. Base and YAML remained unchanged.

There is no conflict between 1.5.0 and the base minimum `>=1.4.0`. There is a
YAML-versus-resolution documentation/metadata discrepancy. The reason maintainers
left the YAML unchanged is not established; do not invent bundler precedence or
installation order to explain it. Preserve expected, resolved, and observed
versions as distinct fields.

Sources:

- [Synchronized 1.4.0 update](https://github.com/nrfconnect/sdk-nrf/commit/83e823730a2a67a3fc56b9a1f538cc01c77487a2)
- [Fixed-package update](https://github.com/nrfconnect/sdk-nrf/commit/5f1e23566c6af7f1dac802a7e96729d7126d2d50)

## Local Artifactory metadata catalog: feasible with limits

Anonymous read-only requests verified:

```text
GET /artifactory/api/repositories
GET /artifactory/api/storage/NCS/external/bundles
GET /artifactory/api/storage/NCS/external/bundles/v3/index-linux-aarch64.json
```

Repository discovery returned Generic repositories such as NCS, ncs-src-mirror
and swtools, plus local/virtual PyPI repositories. Basic folder info returns
children; file info returns size, timestamps, download URI and checksums.
This permits a bounded metadata-only traversal and local SQLite/JSONL catalog
without downloading toolchain archives or scraping `/ui/packages`.

Limit observed: adding `?list&deep=0` to the bundles folder returns HTTP 403.
JFrog documents this bulk listing as requiring a non-anonymous privileged user.
AQL also requires authentication. No credentials were supplied or requested,
and no authentication bypass is proposed. Basic anonymous child traversal is the
available route; a repository name being listed does not prove all its paths are
readable.

Recommended initial roots: NCS toolchain bundles, SDK-source index metadata,
nrfutil package metadata, and only the Python packages referenced by v3.4.1's
lock source. Record fetched-at times, source URLs, digests, denied paths,
failures and completeness boundaries. Use request/depth/byte budgets, caching,
resume checkpoints and retry/backoff. Never label a partial crawl a complete
mirror, or infer missing artifacts from unvisited/denied paths.

Sources:

- https://files.nordicsemi.com/artifactory/api/repositories
- https://files.nordicsemi.com/artifactory/api/storage/NCS/external/bundles
- [Storage API and permissions](https://docs.jfrog.com/artifactory/reference/getstorageitem.md)
- [AQL authentication and execution](https://docs.jfrog.com/artifactory/docs/aql-query-execution.md)

## Published indexes and initial JSONL catalog

The metadata-only capture at
`docs/research/nordic-artifacts/2026-10-06/` contains 391 JSONL records from nine
public metadata endpoints. `manifest.json` records exact source digests,
observation time and coverage. These are advertised records, including selector
aliases and SDK schema branches, not 391 distinct verified binary artifacts.

Research recommends **published indexes before recursive Storage traversal**:

- SDK-source config/index already lists advertised releases and archive SHA-512.
  Read every schema branch; highest branch alone loses older entries.
- Platform toolchain indexes already supply selectors, bundle names and SHA-512.
- nrfutil registry publishes per-platform sdk-manager versions as JSONL with
  archive SHA-256 in `cksum`. The small registry config supplies URL templates.
- For Python wheel availability, query the configured PyPI Simple project page
  only for selected dependencies. Nordic returned HTML despite PEP 691 JSON
  negotiation; support HTML/PEP 503 links, hashes, markers and yank metadata.
- Basic File Info enriches selected known artifacts without archive transfer.
  Checksum search can join known SHA-256 values with scoped repository results;
  it is not a complete-inventory discovery API.
- JFrog CLI search does not bypass AQL permissions. Administrative repository
  export is not a suitable anonymous read-only catalog API. UI browsing APIs have
  no established stable export contract and should not be the foundation.

Registry endpoints used by the initial capture:

```text
/artifactory/swtools/external/nrfutil/index/config.json
/artifactory/swtools/external/nrfutil/index/x86_64-unknown-linux-gnu/nrfutil-sdk-manager
/artifactory/swtools/external/nrfutil/index/aarch64-unknown-linux-gnu/nrfutil-sdk-manager
```

Tracked work: PB-029 metadata acquisition/coverage research; PB-030 checksum glue
and validation; PB-031 maintainer-generated consumer locks; PB-032 manual update
workflow; PB-033 later scheduled proposal PRs. All remain Backlog; snapshot capture
does not imply those automation stages are implemented.

## Maintainer and consumer separation

Normal consumers should use reviewed, committed release data and the flake's
locked inputs/artifact hashes. Shell entry and Nix evaluation must not infer
versions from current upstream main, query live indexes, regenerate constraints,
or repair caller-owned Python. Explicit managed provisioning can acquire the
already-selected, verified artifacts under its existing approval contract.

Maintainer-only tooling can fetch an exact SDK revision, compute the metadata
fingerprint, inspect published mappings, resolve per-host compiler assets, and
generate candidate release data plus a normalized Python constraints view.
Record Git revision, source-file digests, upstream versus selected tool versions,
archive integrity hashes, supported-host facts, profile policy and exceptions.
Availability/compatibility still require real package, parser and build tests.

Recommended automation sequence:

1. Add the checksum glue and deterministic validation first. It must preserve
   upstream byte order/newline handling and reject malformed or ambiguous index
   data; source changes, duplicate mappings and hash mismatches are explicit.
2. Add a maintainer generator with deterministic output and a check-only mode.
   Ordinary contributor CI validates committed data against committed evidence;
   an explicitly network-enabled job detects current publisher drift separately.
3. A manual GitHub Actions workflow can generate candidate metadata, compare
   diffs and run both-host qualification. Later, a scheduled workflow may open
   update PRs. Do not auto-merge, auto-release, or silently advance consumer locks.

Computing a hash is not qualifying or accepting an update. The full bundle hash
and Zephyr SDK archive hashes are different from the short input-derived bundle
ID. An empty Nordic ARM64 bundle index remains compatible with independently
published Zephyr SDK ARM64 assets; one must not be used to infer the other.
