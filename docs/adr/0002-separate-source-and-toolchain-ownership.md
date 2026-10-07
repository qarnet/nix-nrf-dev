# 0002: Separate source ownership from toolchain selection

Status: Accepted

## Context

Repository, workspace and freestanding applications can use the same NCS
toolchain. Application location does not select the SDK source tree. A
project-owned west manifest may import Nordic and relocate Zephyr; injecting a
different managed `ZEPHYR_BASE` mixes source, extension and module discovery.

Nordic's toolchain environment also exports Python, loader and Git variables
that can break Nix and other contributor tools if loaded into the parent shell.

## Alternatives

- Add a backend per application layout: duplicates tool provisioning and cannot
  identify which source workspace a freestanding application should use.
- Always install managed SDK sources: ignores project-owned revisions and creates
  duplicate checkouts.
- Export Nordic's environment globally or automatically use `west zephyr-export`:
  leaks tool state and writes persistent CMake registry entries.

## Decision

Select tools with `backend` and source ownership with `source`. Keep managed mode
as the compatible default. Workspace mode selects an existing caller-owned west
workspace, resolves project paths from its manifest and validates conflicts.

Workspace paths are strings anchored at shell entry, not Nix paths that copy SDK
trees into the store. Readiness never acquires or updates caller-owned sources.
West workspace Python is caller-prepared and check-only, including `--yes`.
Nordic toolchain provisioning remains separate from source ownership.

Load selected build environment only in west and its children. Do not mutate the
parent's loader/Python/Git environment or automatically export CMake packages.
SDK-independent west core commands do not require build readiness; extensions
use the selected workspace and backend environment.

## Consequences

- Either supported backend can build the same project-owned sources without
  source repair or another managed SDK checkout.
- Missing imports, conflicting configuration and detectable stale caches fail
  instead of selecting another SDK or deleting build output.
- Manifest/source identity, toolchain selection and command readiness need
  separate diagnostics. A matching VERSION is not a complete dependency lock.
- Direct outer-shell CMake is not an implicit Nordic execution interface.
  Source selection does not promise arbitrary forks or custom build layouts.

## References

- [Source caller contract](../application-types.md)
- [Source implementation ownership](../development/architecture.md#backend-boundaries)
- [Qualification procedure](../../tests/application-types/README.md)
- Completed PB-023 and PB-024
