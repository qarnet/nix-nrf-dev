# Product backlog

[Backlog.md](https://backlog.md) stores product work as Markdown. This document
defines the repository contract; use the CLI's board and task list as item views.

## Tooling and storage

The CLI is pinned through `backlog-md` in `flake.nix` and `flake.lock`. It is
available in the default contributor shell and an SDK-free product shell:

```bash
nix develop .#product -c backlog --version
nix develop .#product -c backlog board
nix develop .#product -c backlog task list -s Ready --plain
nix develop .#product -c backlog doctor
nix develop .#product -c backlog browser
```

Do not install it globally. Product work does not require Nordic bootstrap,
probe access, or firmware installation. The browser is a local tool; do not
expose it to a network. Automatic browser opening, commits, and remote operations
are disabled. If port 6420 is occupied by another repository, select another
port through the CLI's documented options.

Before a read-only `nix flake check --no-build` on a cold store, run:

```bash
nix eval --raw .#devShells.x86_64-linux.product.drvPath >/dev/null
```

Pinned bun2nix imports a checked-in `deps.nix` through a nested source path.
Nix's read-only evaluation can compute that path without copying it into the
store, then fail with `path '...-cache-entry-creator' is not valid`. Writable
SDK-free evaluation materializes those source paths; it does not build the CLI,
install an SDK/toolchain, or change dependency pins. CI runs this before its
read-only all-systems gate. A warm local store can mask the issue.

`backlog.config.yml` selects `docs/product/backlog`:

```text
tasks/          active items, including items awaiting Review
completed/      verified Done items, retained as history
archive/tasks/  dropped items, retained as history
```

Drafts are not part of this workflow. The CLI owns IDs, status transitions,
filenames, and moves. Use `backlog task create`, `edit`, `complete`, and `archive`;
do not allocate IDs or move task files by hand. Never reuse or renumber IDs.
Description, plan, notes, and evidence may be edited as Markdown.

## Vocabulary

- IDs: `PB-001`, `PB-002`, and so on, allocated by the CLI.
- Statuses: `Backlog`, `Ready`, `In Progress`, `Blocked`, `Review`, `Done`.
- Priorities: `P0` urgent or actively blocking; `P1` near-term work; `P2` useful
  planned work and the default; `P3` speculative or deliberately deferred.
- Types: `feature`, `bug`, `research`, `refactor`, `tech-debt`, `docs`.
- Size labels: `size:S` localized, `size:M` several components, `size:L`
  cross-cutting. Omit an unsupported estimate in Backlog; set it before Ready.
- Area labels: `area:nrfutil`, `area:west`, `area:toolchain`, `area:openocd`,
  `area:rtt`, `area:debug`, `area:flpr`, `area:serial`, `area:nix`, `area:cli`,
  `area:testing`, `area:ci`, `area:release`, `area:documentation`, `area:security`.

Types distinguish new capabilities, incorrect behavior, investigations,
behavior-preserving restructuring, maintenance, and documentation deliverables.
Use native `dependencies` only for true sequencing. Link related independent
work in the Description. Qualify cross-repository IDs with their repository.

## Item structure

Descriptions use these subsections in order:

1. `### Problem`
2. `### Desired outcome`
3. `### Scope / Non-goals`
4. `### Technical context`
5. `### Open questions`

Cite verified source paths and versions in Technical context. Keep unresolved
questions visible instead of inventing requirements. Acceptance criteria state
observable outcomes and the smallest public-boundary verification that catches
regression. Safety and validation belong in the relevant item's acceptance,
not optional follow-up work.

Use Implementation Plan, Implementation Notes, and Final Summary for execution.
Record commands, outcomes, limitations, and hardware evidence there. A detailed
research note alone does not make an item Ready.

## Lifecycle and evidence

Normal progression is Backlog to Ready to In Progress to Review or Done.
In Progress can move to Blocked and back. Dropped is not a status: the human
decides to drop an item, its Final Summary records why, and the CLI archives it.

Agents may manage status as part of requested work, including refinement to
Ready and verified completion. That permission does not authorize unrequested
implementation, product changes, commits, PRs, or hardware operations.

- **Ready:** understandable problem, explicit outcome, bounded scope and
  non-goals, observable acceptance, known dependencies, size set, and no open
  product question requiring the implementer to invent behavior. Establish
  readiness before implementation; an underspecified item stays Backlog.
- **Blocked:** a concrete external or technical obstacle is recorded in Notes.
  Missing specification alone is not Blocked.
- **Review:** implementation and acceptance evidence are recorded, relevant
  repository gates pass, required docs are updated, and direction or review
  remains pending. Do not mark failed or unperformed acceptance as passed.
- **Done:** acceptance is demonstrated, relevant repository gates pass, Final
  Summary records verification, and the CLI sets Done and moves the item to
  completed. No commit, PR, merge, or release is required for this transition.
  Git publication and releases remain separate actions. Agents never merge PRs.

Default work-in-progress limit is one item unless parallel work is explicitly
intended. Reopen work through the CLI when needed; preserve history.

Relevant gates come from [CONTRIBUTING.md](../../CONTRIBUTING.md). Use real
encoded traffic for protocol behavior, subprocess boundaries for command
behavior, and approved hardware tests for probe/target claims. Mock launch
arguments do not prove non-halting attachment or successful capture. When
required hardware validation is unavailable, record the blocker rather than
claiming Done. Research items can finish with sourced findings and a decision
without pretending to have performed hardware validation.

Firmware fixtures must be small and test-owned. Production firmware, DMA
recorders, application schemas, and fault policy remain in consumer projects.
Flashing, erasing, recovery, and intrusive target control require explicit
approval; backlog priority is not that approval.

## Ownership

Product-owned fields are title, priority, type, intended behavior, scope,
non-goals, and acceptance text. Do not silently change them during execution.
Execution owns plans, notes, summaries, checkbox state, and evidence. Status
is agent-manageable under the definitions above. Size, area, and dependencies
may be corrected from repository evidence, with the reason recorded.

## Adoption and research migration

Setup compared local repositories on 2026-09-25 after fetching both named
references. `serial-mcp` remote main at `a76f02fe` supplied the pinned Nix CLI,
storage layout, vocabulary, and section ownership conventions. Its dirty local
main was eight commits behind and was not fast-forwarded over ongoing work.
`karnetvr-infra` local main at `9b2d95d` was eleven commits ahead of remote with
no incoming commits. Its **uncommitted** product contract supplied the newer
evidence-gated lifecycle, separating Done from commits and PRs. Neither
reference worktree was changed.

Both use Backlog.md revision `3c7fde65e28a6e5e154f63126957649514eee370`.
Keep upstream's Nixpkgs pin: serial-mcp documents an install-check incompatibility
when replacing it with a newer consumer Nixpkgs. This repository adds the tool
only to contributor shells, not `mkNrfShell` consumer packages.

The initial [RTT/debug research](../development/rtt-debug-research.md) was
converted into PB-001 through PB-022 after inspecting le-audio-receiver.
The research document retains sources, receiver evidence, and a coverage map;
the task files own current priorities, dependencies, scope, and acceptance.
Use the CLI for current status. Receiver tooling and FLPR investigation are
near-term work; profiling and SWO/trace remain later research. The older
[roadmap](../development/roadmap.md) retains unrelated proposals rather than
duplicating migrated item status.
