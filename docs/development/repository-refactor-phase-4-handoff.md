# Repository Refactor Phase 4 — Documentation and Artifact Cleanup Handoff

## Goal

Declutter active documentation, remove safe generated workspace artifacts,
ignore Ruff cache explicitly, and remove unused workflow `NIX_PATH` channel
configuration while preserving all current code, tests, public outputs, and
historical records.

## Scope

In scope:

- Move completed plans/handoffs into `docs/development/archive/`.
- Add archive index and repair links.
- Keep active status/roadmap/feasibility/refactor documents at current paths.
- Add `.ruff_cache/` to `.gitignore`.
- Remove verified ignored local artifacts by exact path.
- Remove unused `nix_path` inputs from Nix-install workflow steps.
- Sweep active docs/comments for current architecture paths.

Out of scope:

- Code/Nix/backend/test behavior changes.
- Deleting historical tracked documents.
- Removing current test harnesses, workflows, templates, TCL, sources, status
  docs, package outputs, or checks.
- Real clean-room/hardware execution.

## Historical documents to archive

Use `git mv` into `docs/development/archive/`:

```text
backend-selector-handoff.md
clean-room-build-handoff.md
nix-nrf-bootstrap-handoff.md
nix-nrf-cli-phase-1-handoff.md
nix-nrf-cli-phase-2-handoff.md
nix-nrf-cli-plan.md
nix-nrf-doctor-handoff.md
phase-1-clean-shell-handoff.md
sdk-nrf-prototype-handoff.md
west-backend-environment-handoff.md
west-backend-public-integration-handoff.md
repository-refactor-phase-2-handoff.md
repository-refactor-phase-3-handoff.md
repository-refactor-phase-4-handoff.md
```

These describe completed or superseded work. Preserve content except link-path
repairs and an optional short archive header where status would otherwise be
ambiguous. Do not rewrite old code paths in historical narrative.

Add `docs/development/archive/README.md` with grouped index:

- original shell/backend selector;
- nix-nrf CLI/bootstrap/doctor;
- clean-room proof;
- west prototype/public integration;
- superseded pure sdk-nrf prototype;
- repository refactor phases.

Index states archived documents are historical evidence, not current API docs,
and points to current README/status/feasibility/refactor docs.

## Active documents kept in place

```text
docs/development/clean-bootstrap-versioning-plan.md
docs/development/nrfutil-backend-status.md
docs/development/west-backend-status.md
docs/development/sdk-nrf-feasibility-draft.md
docs/development/repository-refactor-plan.md
```

`clean-bootstrap-versioning-plan.md` mixes accepted design and proof history but
is still referenced by README/current nrfutil status; keep it active this phase.

Update links from active files to archived files, including:

- README west environment and superseded sdk-nrf prototype references;
- goals west environment reference;
- west status prototype/integration handoff references;
- clean bootstrap plan reference to bootstrap handoff;
- any archived document linking another moved document.

Run a repository link-path sweep; every literal `docs/development/*.md` path
must exist after moves. Planned future paths in feasibility draft may remain
nonexistent only when clearly labeled future outputs.

## Unneeded items: exact decisions

Keep:

- `sources.md` (user-authored source inventory);
- all unit/clean-room/west/hardware tests;
- all three workflows;
- templates, TCL recipes, flake checks, package outputs;
- both current backend status docs;
- `sdk-nrf-feasibility-draft.md` as requested non-binding future plan;
- root `.envrc`.

Remove only generated ignored workspace artifacts:

```text
result
result-*
.ruff_cache/
.direnv/
.pre-commit-config.yaml
```

Before removal:

- prove each path is ignored with `git check-ignore`;
- prove every `result*` is a symlink; refuse real files/directories;
- prove `.pre-commit-config.yaml` is a symlink;
- list `.ruff_cache` and `.direnv` only to validate exact path/type;
- never follow/delete symlink targets;
- use explicit paths, not `git clean`, wildcard expansion without inspection,
  recursive repository-wide removal, or Nix store deletion.

Remove local artifacts after tracked commits/tests so generated hook/cache state
remains available during implementation. Final status should show no ignored
artifact entries above. They may regenerate on later `direnv`/build use.

Add to `.gitignore`:

```text
.ruff_cache/
```

## Workflow cleanup

Remove `nix_path:` from `cachix/install-nix-action` in:

```text
.github/workflows/ci.yml
.github/workflows/clean-room.yml
.github/workflows/hardware.yml
```

Grounding: repository contains no `<nixpkgs>` or `NIX_PATH` consumer; all
commands use flake inputs/lock. Current hardware value also differs from other
workflows (`nixos-25.11` vs `nixos-unstable`) despite being irrelevant to flake
evaluation. Removing all three avoids false version authority; do not replace
with another channel.

Keep install action version, GitHub token, Cachix, triggers, runner labels,
timeouts, and commands unchanged.

## Active architecture sweep

Current non-archive docs/source comments should use:

```text
nix/flake/
nix/backends/{nrfutil,west}/
nix/commands/
nix/hardware/
nix/lib/mk-python-command.nix
bin/backends/{nrfutil,west}/
bin/commands/
tests/fixtures/west-workspace.py
```

Historical archive may retain old paths as narrative. Links must still resolve.

## Verification

```bash
nix fmt
actionlint .github/workflows/*.yml
nix flake check -L
nix build -L \
  .#openocd-master-unwrapped \
  .#openocd-master \
  .#nrfutil \
  .#nix-nrf \
  .#udev-rules \
  .#west-zephyr-sdk-v3_3_0
NIX_NRF_WEST_DRY_RUN=1 bash tests/west-backend/run.sh
NIX_NRF_CLEAN_DRY_RUN=1 bash tests/clean-room/run.sh
bash -n tests/hardware/run.sh
```

Also verify:

- flake output/check/package names remain identical to Phase 3 baseline;
- no broken literal local markdown paths (excluding clearly future planned
  outputs);
- active docs have no stale current source paths;
- archive contains every moved historical document exactly once;
- `git status --ignored --short` has none of exact generated artifact paths
  after safe local cleanup;
- tracked worktree clean after commit.

## Constraints

- No historical document deletion.
- No code/test/output behavior change.
- No workflow execution/dispatch, network bootstrap, real clean-room, hardware,
  sudo, Nix store deletion, push, merge, amend, PR, force-push, or attribution.

## Commits

Handoff:

```text
docs(refactor): define repository cleanup phase
```

Tracked cleanup after gates:

```text
chore(repo): archive plans and remove stale wiring
```

Local ignored artifact removal occurs after commit and is reported, not
committed.

Return moved/kept/removed inventory, link sweep, workflow rationale, tests,
commits, local cleanup proof, blockers/deviations, and final status.
