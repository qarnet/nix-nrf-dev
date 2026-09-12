# Live handoff: cold-cache CI nrfutil supply

> **Maintenance rule:** Read this file before resuming work. Record every
> material investigation, edit, command result, CI result, blocker, and
> decision in **Progress log** before reporting status. Keep newest entry
> first.

## Progress log

- 2026-09-12. Expanded `0.1.2` notes for full `v0.1.1..HEAD` scope. Follow-up
  release check, 22-test suite, all-system flake evaluation, full flake gate,
  packaged `nix-nrf`, and exact `0.1.2` CLI output passed. Ready to commit
  scope correction and refresh PR/CI.
- 2026-09-12. Last tag `v0.1.1` scope includes documentation refactor
  `a3f665f` and source fix `2e6ac03`. Expand `0.1.2` notes to cover both,
  plus release-test maintenance. Add required latest hygiene receipt to PR
  body, then rerun final gate and CI.
- 2026-09-12. Pushed branch through `8e76a74`; PR #10 CI run `34718102794`
  passed all `check` steps. Final wrapup review found two follow-ups before
  merge: release notes need full last-tag scope, and PR body needs latest
  documentation-hygiene receipt. Inspecting both now; do not merge yet.
- 2026-09-12. Refreshed PR #10 summary and validation with source `0.1.2`,
  release-note test repair, full local gate, and prior receiver cold-cache
  evidence. Preparing final handoff commit before pushing branch.
- 2026-09-12. Pre-push review: PR #10 remains open and merge-clean, with
  prior CI green. Local branch is three commits ahead and clean. Refresh PR
  summary for `0.1.2` and final gates, then push current branch for fresh CI.
- 2026-09-12. Final-handoff commit hook rejected an abbreviated commit
  identifier as a typo. Remove only that opaque identifier and retry; source
  content and release evidence remain unchanged.
- 2026-09-12. Committed release preparation
  (`chore(release): prepare v0.1.2`). It includes canonical release metadata,
  changelog notes, and durable release-note contract tests. Commit hooks
  passed. Next: commit final handoff record, push existing PR #10, and watch
  fresh CI.
- 2026-09-12. Final incremental documentation audit covered all 12
  human-written paths since `b1a9fccc`. Release table/body, backend contract,
  CI comments, test intent, and incident handoff agree. No stale claims,
  duplicate source-of-truth, or marker change found. Ready for separate
  `0.1.2` release-preparation commit.
- 2026-09-12. Final source CI-equivalent gate passed for `0.1.2`: release
  checks, all-system evaluation, all 21 flake checks, package builds, command
  smoke, exact `nix-nrf 0.1.2` output, shell boundaries, OpenOCD source
  compatibility, and generated-consumer checks. No SDK/bootstrap download ran.
- 2026-09-12. Updated stale release-note tests. Release manifest check,
  22-test source suite, and sandboxed `release-consistency` derivation now
  pass for `0.1.2`. Starting final all-system and full flake checks.
- 2026-09-12. Found stale release-specific assertions in
  `tests/unit/test_release.py`, contrary to its canonical-version policy.
  Replace them with stable public contract checks: nonempty current notes and
  `release.py notes` output exactly matching current release body.
- 2026-09-12. Release manifest check passed, but release unit suite failed
  two tests because fixtures expect previous `0.1.1` notes (`mkNrfShell` and
  `init-project`). This is expected release-test maintenance, not a supply
  regression. Inspecting tests before updating current-release assertions.
- 2026-09-12. Prepared source `0.1.2`: updated `release.json`, added table
  row and exact release body in `CHANGELOG.md`, and left `Unreleased` first.
  Starting release contract checks before final full gate.
- 2026-09-12. User approved source patch release `0.1.2`. Next: update
  release metadata and changelog, rerun release and full source gates, then
  commit separately before pushing existing PR #10.
- 2026-09-12. Committed live-handoff maintenance as `d5d4956`
  (`docs(nrfutil): maintain cold-cache handoff`). Commit hooks passed: secret,
  whitespace, typo, conventional-commit, and size checks. Next: ask source
  release version choice required by repo-wrapup.
- 2026-09-12. User approved cleanup of generated Python bytecode.
  Removed `scripts/__pycache__/release.cpython-314.pyc`. Source tree now has
  only intended live-handoff documentation changes.
- 2026-09-12. Post-gate status found generated, untracked
  `scripts/__pycache__/` from Python verification. It is outside source scope
  and blocks clean wrapup until user approves deleting it or keeping it.
- 2026-09-12. Full source CI-equivalent gate passed. OpenOCD sourced both
  recipes and reached expected no-probe boundaries. Generated consumer project
  evaluated and entered its shell. Documentation audit found no stale contract;
  it only replaced em-dash separators in this required live handoff.
- 2026-09-12. Package smoke tests and both development-shell checks passed.
  `nrfutil` reported 8.2.0; packaged `nix-nrf` reported current release 0.1.1.
  Clean-environment shell preserved host Nix, Node, Git, and Python behavior.
  Starting OpenOCD recipe and generated-project checks.
- 2026-09-12. Source release checks, all-system flake evaluation, full flake
  checks, and all CI package builds passed. Pre-commit, formatter, Nix, Python,
  shell, and workflow checks passed. Starting CI smoke, shell, OpenOCD parser,
  and initializer checks.
- 2026-09-12. Starting full source CI-equivalent gate after documentation
  cleanup. It evaluates flakes, builds packages, runs smoke and shell checks,
  and uses impossible probe serials for OpenOCD recipe parsing. It does not
  bootstrap an NCS SDK or change hardware.
- 2026-09-12. Documentation hygiene incremental audit started for all ten
  human-written paths changed since merge base `b1a9fccc`, plus this live
  handoff update. Existing managed baseline marker is valid; no full audit or
  marker change is needed.
- 2026-09-12. Started `repo-wrapup` for `nix-nrf-dev` at user request.
  Scope: source branch only. Next: verify repository truth and branch-wide
  documentation, run full gate, ask release-bump choice, then commit/PR/CI.
- 2026-09-12. Compared `nix-community/zephyr-nix` at `5ef0903`. It keeps
  multiple source-controlled SDK versions, hashes every versioned archive in
  JSON manifests, and maps `latest` to a reviewed alias, never a live remote
  value. Its `update-sdk` helper generates a chosen-version hash manifest;
  Renovate maintains flake locks weekly. Recommendation: treat sdk-manager as
  a tested compatibility baseline with reviewed update PRs, not an automatic
  per-release chase; full NCS bundle immutability is separate future work.
- 2026-09-12. Clarified scope: 1.16.1 is pinned `sdk-manager` client
  version, not an NCS v3.3.0 pin. `nrfutil` backend accepts each explicit
  stable NCS release available from Nordic's index; default bootstrap chooses
  newest compatible patched toolchain, while `toolchainBundleId` selects an
  exact bundle. sdk-manager upgrades are deliberate version/hash/compatibility
  changes, never automatic.
- 2026-09-12. Confirmed `v0.1.1` is already published at
  `41e27a9636444eb9542c7140a5bf8a40b12f4b89`. Merging source fix without a
  manifest bump would produce no new release; `0.1.2` is required to publish
  this repair.
- 2026-09-12. Release decision: recommend a `nix-nrf-dev` patch release
  `0.1.2` after source PR #10 merges. This fixes public fresh-shell behavior
  while preserving `mkNrfShell` API, NCS version, and toolchain contract. Do
  not bump receiver firmware `VERSION`: change is CI/dependency supply only;
  its workflow correctly skips release when `VERSION` is unchanged.
- 2026-09-12. Hosted evidence rechecked. Fresh workflow-dispatch run
  `34705924687` recorded an NCS cache miss, sdk-manager 1.16.1, and
  `72 PASS / 0 FAIL / 72 TOTAL`; it completed successfully. Current source PR
  #10 CI is green; receiver PR #12 tests and firmware are green, release
  skipped. `git diff --check` passes in both repositories; only this live
  handoff file remains locally modified.
- 2026-09-12. Receiver acceptance passed: exact `nix develop` toolchain
  command found `911f4c5c26`; `nix develop --command bash scripts/test-all.sh`
  ended `Gate complete: 72 PASS / 0 FAIL / 72 TOTAL`. Existing source and
  receiver implementation needs no additional code repair. Next: confirm
  hosted fresh-cache CI evidence and final worktree state.
- 2026-09-12. Source acceptance passed on current branch: `nix build
  .#nrfutil` and `nix flake check -L` both exited 0. Flake checks reported all
  checks passed; only dirty-tree warning came from this live handoff update.
  Starting receiver toolchain and canonical test-gate acceptance.
- 2026-09-12. Starting source acceptance: `nix build .#nrfutil`, then
  `nix flake check`. Receiver acceptance follows only if source passes.
- 2026-09-12. Inspected active branches. Source commit `2e6ac03` supplies
  sdk-manager 1.16.1 from versioned, fixed-hash Nordic archive; receiver
  commit `02d042f` locks it and uses public `mkNrfShell`. Receiver workflow
  asserts manager 1.16.1 and toolchain `911f4c5c26`. Running handoff
  acceptance commands next; no repair identified yet.
- 2026-09-12. Resumed implementation at user request. Next: inspect current
  source and receiver branches, then repair or verify immutable supply against
  handoff acceptance commands.
- 2026-09-12. Converted this document into live handoff at user request. No
  source, receiver, CI, or validation work ran in this turn.

## Historical resolution evidence

Source commit `2e6ac03` adds the repository-owned `nrfutil` composition in
`nix/backends/nrfutil/package.nix`. It combines the consumer's Nixpkgs core
with sdk-manager `1.16.1` from Nordic's versioned archive and fixed Nix hash.

At validation, receiver commit `02d042f` locked that source revision and
removed its local sdk-manager override. GitHub Actions run `34705924687` ran
after exact Nix and NCS cache misses, verified sdk-manager `1.16.1` and
toolchain `911f4c5c26`, passed `72 PASS / 0 FAIL / 72 TOTAL`, then passed the
nRF54L15 firmware job.

This record preserves the original diagnosis, constraints, and verification
boundary for future supply changes.

## Original goal

Fix PR #12 CI failure without hash-only workaround. Make Nix `nrfutil` supply reproducible on fresh GitHub runners.

## Original root cause

PR run `34668261245`, job `103484518928`, fails before NCS install, tests, firmware build, or release.

Old locked input:

- Receiver `flake.lock` pins `qarnet/nix-nrf-dev` at `e9d77367e334213417c10fa7a7ded3e9195f78c0`.
- Its `nix/nrfutil-core.nix` labels core as 8.1.1 but fetches mutable URL:
  `https://files.nordicsemi.com/artifactory/swtools/external/nrfutil/executables/x86_64-unknown-linux-gnu/nrfutil`
- Expected hash:
  `sha256-SAD4tx/uwMqvPBQ9KbC3/W8zxqJY2hDmYHQ/DbGJCgs=`
- Fresh runner got:
  `sha256-HPS9HT1k9DprlgLY2OjWR77A0m1Re6cv0VT5VUa1AmA=`

Nix correctly rejects changed upstream bytes. Both Nix-store and NCS caches missed, exposing stale mutable dependency.

The receiver's earlier standalone sdk-manager `1.16.1` download passed its
checksum. It was separate from the failed `nrfutil-core` derivation.

## Implementation scope

The fix spans:

1. `/home/thomas-workstation/repos/nix-nrf-dev`
2. `/home/thomas-workstation/repos/le-audio-receiver`

Source implementation used current `nix-nrf-dev` `main` architecture as its
baseline:

- `nix/flake/components.nix`
- `nix/backends/nrfutil/`
- `nix/flake/checks/nrfutil.nix`

Receiver update changed:

- `flake.lock`
- `flake.nix` only if current `mkNrfShell` API needs explicit compatible arguments.

## Constraints

- Do **not** replace old expected hash with CI `got` hash.
- Do **not** bypass `nix develop`, alter CI cache keys, pin a warm cache, or use `$RUNNER_TEMP` PATH ordering as workaround.
- Do **not** change firmware build, package, release, test-gate, nRF54L15 artifact, or `VERSION` behavior.
- Preserve exact NCS v3.3.0 / toolchain `911f4c5c26` contract.
- Preserve current public `mkNrfShell` behavior needed by receiver builds.

## Compatibility diagnosis

Before this fix, source composition used:

```nix
pkgs.nrfutil.withExtensions [ "nrfutil-sdk-manager" ]
```

That delegated the manager version to consumer Nixpkgs. At incident time:

- receiver follows pinned Nixpkgs 25.11, where nrfutil-sdk-manager is 1.8.0;
- nix-nrf-dev's then-current unstable pin had 1.15.0;
- receiver CI required 1.16.1.

Do not blindly update receiver lock to current nix-nrf-dev. Keep 1.16.1, or prove a deliberate replacement satisfies exact toolchain environment contract before changing it.

## Required outcome

Use versioned, content-pinned Nordic package archives or another immutable controlled source. No mutable `.../executables/.../nrfutil` endpoint.

## Validation

In `nix-nrf-dev`:

```sh
nix build .#nrfutil
nix flake check
```

In receiver after lock/API update:

```sh
nix develop --accept-flake-config --command bash -c \
  'nrfutil sdk-manager toolchain env --ncs-version v3.3.0 --as-script sh | grep -q 911f4c5c26'

nix develop --command bash scripts/test-all.sh
```

Expected canonical result:

```text
Gate complete: 72 PASS / 0 FAIL / 72 TOTAL
```

The source checks, receiver shell and full test gate, and a fresh GitHub
Actions cache-miss run all passed. No release ran because `VERSION` stayed
unchanged and the proof used a non-main dispatch.

## Decision boundary

Do not silently downgrade or land a cache-dependent workaround. If a future
manager change cannot satisfy the exact NCS/toolchain contract, stop and report
the command output with a compatibility decision.
