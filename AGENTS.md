# Repository work

Read `CONTRIBUTING.md` for executable gates and
`docs/development/architecture.md` for source ownership.

For backlog creation, refinement, and implementation, read
`docs/product/README.md` first. It owns lifecycle and vocabulary. Use the pinned
CLI through `nix develop .#product -c backlog`; do not install it globally or
allocate IDs manually. Status changes follow the product contract, not older
skill defaults. Commits and PR creation still require user authorization.
Never merge PRs.

Keep Nordic's toolchain environment scoped to child processes. Contributor
tools must not leak into consumer `mkNrfShell` packages. NCS version and the
nix-nrf-dev release version are independent.

Public `mkNrfShell` keeps the nrfutil default and rejects it on ARM64; only
repository and initializer presets choose west automatically. No fallback.

NCS v3.4.1 has a west-version metadata discrepancy: `tools-versions-linux.yml`
lists 1.4.0, while `requirements-fixed.txt` pins 1.5.0 and the observed Nordic
bundle `8285d8ad56` contains 1.5.0. Keep declared tool versions, Python resolution,
and observed binaries distinct; do not silently rewrite one to match another.
History and evidence: `docs/product/research/nordic-release-metadata.md`.

`source.mode = "workspace"` selects existing SDK sources, not application type.
Workspace strings anchor at shell entry; never replace them with Nix paths that
copy SDK trees into the store. Existing-source readiness must not acquire/update
repositories or implicitly repair Python environments.

Do not run bootstrap downloads, flashing, recovery, or hardware control without
explicit approval. Small verification firmware belongs in tests; production
firmware belongs in consumer projects. Test real public behavior, not only
generated command arguments.
