# Nordic release metadata research

Evidence for PB-029 through PB-033, inspected against NCS v3.4.1 at
`b20f8619ba9a5530f8c34b0a130d829947cfe55d`. These items own future acquisition,
checksum and lock-generation work; this report does not claim they are implemented.

## Release identity

`scripts/print_toolchain_checksum.sh` hashes `requirements-fixed.txt` followed by
the OS tools YAML, normalizes trailing carriage returns and takes ten SHA-256 hex
characters. Linux v3.4.1 yields `8285d8ad56`, matching the published amd64 mapping.
The script selects an OS, not CPU architecture. The short ID is a metadata
fingerprint, not archive integrity or source-tree identity; use the index's full
archive digest separately. Multiple selectors can name the same bundle.

## Python requirements and tool versions

`requirements-fixed.txt` is installable with pip `-r`, not unmodified `-c`:
extras such as `pyjwt[crypto]` are invalid in constraints. A generated constraints
view must normalize base-package pins while preserving markers and requesting
extras through the selected requirements. Index policy and artifact hashes are
separate; version pins alone do not lock wheel bytes or isolated build dependencies.

Nordic's tagged validation uses `pip-compile-cross-platform==1.4.2+nordic.3`.
That inspected generator is Poetry-backed; SDK west-command CI installs its
output with pip. This does not establish the proprietary bundler's installer
order. JFrog client instructions are not evidence of bundler behavior.

The Linux tools YAML declares west 1.4.0, the base minimum is `>=1.4.0`, and the
fixed/observed bundle version is 1.5.0. Commit
`5f1e23566c6af7f1dac802a7e96729d7126d2d50` changed the fixed pin without changing
the YAML. Why the YAML stayed unchanged is unestablished. Keep declared,
resolved and observed values distinct rather than inventing precedence.

## Acquisition boundary

Prefer published SDK/toolchain indexes and sdk-manager's per-platform JSONL
registry over recursive storage crawling. Read every SDK schema branch and retain
selector aliases. Anonymous Basic Storage reads can enrich known artifacts;
bulk listing returned 403 and AQL requires authentication. Neither a denied
request nor an HTML response proves an empty inventory.

The [captured catalog](../../research/nordic-artifacts/README.md) preserves nine
metadata responses and advertised records, not a complete mirror. It excludes
Python wheel files, unadvertised artifacts and runtime compatibility. Python
Simple endpoints may return PEP 503 HTML despite JSON negotiation.

Candidate lock/update tooling remains maintainer-only. Consumers use reviewed
committed data; shell entry does not regenerate locks, advance releases or repair
caller Python. Fingerprint calculation is not update acceptance. Both-host parser,
package and real-build qualification remain necessary.

## Sources

- [Tagged checksum script](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/scripts/print_toolchain_checksum.sh)
- [Fixed requirements](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/scripts/requirements-fixed.txt)
- [Tools YAML](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/scripts/tools-versions-linux.yml)
- [Fixed-file validation](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/.github/workflows/validate-pip-requirements-fixed-file.yml)
- [Pip consumer](https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/.github/workflows/west-commands.yml#L60-L63)
- [Fixed-pin change](https://github.com/nrfconnect/sdk-nrf/commit/5f1e23566c6af7f1dac802a7e96729d7126d2d50)
- [Pip constraints](https://pip.pypa.io/en/stable/user_guide/#constraints-files)
