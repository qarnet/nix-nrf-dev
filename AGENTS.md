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

`source.mode = "workspace"` selects existing SDK sources, not application type.
Workspace strings anchor at shell entry; never replace them with Nix paths that
copy SDK trees into the store. Existing-source readiness must not acquire/update
repositories or implicitly repair Python environments.

Do not run bootstrap downloads, flashing, recovery, or hardware control without
explicit approval. Small verification firmware belongs in tests; production
firmware belongs in consumer projects. Test real public behavior, not only
generated command arguments.
