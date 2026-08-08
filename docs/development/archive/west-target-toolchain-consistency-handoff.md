# West Target/Toolchain Consistency — Phase 7 Implementation Handoff

Status: historical. Phase 7 of
`docs/development/nixos-safety-init-testing-plan.md` was implemented and
accepted on branch `feat/nixos-safety-and-init` (commit `test(west): verify
target archive consistency`). This document records the implementation
shape; archived with the accepted plan.

## Goal

Add one meaningful pure-Nix metadata gate using the pinned Nixpkgs
`lib.debug.runTests`: west Zephyr SDK declared targets and x86_64-linux
toolchain archive targets must match in both directions for every supported NCS
release.

## Grounding

- Metadata source: `nix/backends/west/versions.nix`.
- Existing schema check: `westBackendMetadataCheck` in
  `nix/flake/checks/west.nix`; retain it unchanged except adjacent comments if
  needed. It proves types/nonempty fields but not cross-list consistency.
- Pinned Nixpkgs implementation:
  `/nix/store/2a2yjwdqfc0hrfhjpx5fny4fl5fmdgbx-source/lib/debug.nix`
  documents and implements `lib.debug.runTests`. Only attrs beginning `test`
  run. Return value is a list containing failures only, each with `name`,
  `expected`, and `result`.
- Current `v3.3.0` metadata declares `arm-zephyr-eabi` and
  `riscv64-zephyr-elf`; x86_64-linux toolchain archives contain both.

## Implementation

Implement in `nix/flake/checks/west.nix`; no new module is needed.

Build two order-preserving per-release attrsets from `westBackendVersions`:

1. `missingArchives`: each release maps to declared
   `entry.zephyrSdk.targets` values absent from
   `entry.zephyrSdk.assets."x86_64-linux".toolchains[*].target`.
2. `undeclaredArchives`: each release maps to archive target values absent from
   `entry.zephyrSdk.targets`.

Build matching expected attrsets mapping every release to `[]`. Run exactly:

```nix
failures = pkgs.lib.debug.runTests {
  testEveryDeclaredTargetHasToolchainArchive = {
    expr = missingArchives;
    expected = emptyPerRelease;
  };
  testEveryToolchainArchiveTargetIsDeclared = {
    expr = undeclaredArchives;
    expected = emptyPerRelease;
  };
};
```

Use membership semantics (`builtins.elem` or equivalent), not list-order
equality: metadata order remains meaningful for packaging but coverage does not
depend on matching list order.

Export check name `west-target-toolchain-consistency`. If `failures == []`,
the derivation prints a concise pass message and creates `$out`. If nonempty,
serialize the full failure list with `builtins.toJSON`, print a clear heading
plus JSON to stderr, and exit nonzero. JSON must preserve `name`, `expected`,
and `result`, making missing/extra targets and affected releases visible.

Wire the check explicitly in `nix/flake/checks/default.nix`. No
`nix/flake/per-system.nix` change should be needed because the existing west
check module already receives `pkgs` and `westBackendVersions`.

Update `docs/development/architecture.md` check ownership concisely. Update the
accepted-plan header after verification to Phase 7 complete pending review,
Phase 8 next.

## Scope boundaries

Do not:

- duplicate backend-selector `tryEval` tests;
- fetch/build Zephyr SDK or toolchain archives;
- compare URLs/hashes already covered by the schema check;
- require target lists and archive lists to use identical order;
- change west metadata to make the check pass unless current data genuinely
  violates the accepted invariant (escalate if so).

## Verification

```sh
nix build -L .#checks.x86_64-linux.west-target-toolchain-consistency
nix flake check --all-systems --no-build -L
nix flake check -L
```

Also inspect the evaluated failure JSON shape safely with a synthetic local
expression or temporary non-repository fixture if useful; do not leave fixture
changes or weaken current metadata.

Implement without commit/push and return for review. Report exact files,
failure data shape, commands/results, deviations, and blockers.
