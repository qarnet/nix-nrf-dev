> **Archived**: this handoff described a completed phase of the repository
> refactor. It is kept as historical evidence; see
> `docs/development/repository-refactor-plan.md` for the current plan and the
> archive README for the full index.

# Repository Refactor Phase 2 — Backend Separation Handoff

## Goal

Separate nrfutil and west implementation modules physically and logically while
preserving public `mkNrfShell` behavior exactly.

Phase 1 already reduced root `flake.nix` from 1172 to 66 lines and established
`nix/flake/` modules. This phase changes internal source ownership only. Shared
CLI/hardware modules and command scripts remain in current locations until
Phase 3.

## User-observable behavior proved unchanged

- Omitted backend and explicit `backend = "nrfutil"` produce identical shell
  derivations.
- Public `backend = "west"` produces the same shell derivation and command
  behavior as before.
- `ncsVersion` remains required.
- Backend validation/errors, shell hooks, wrappers, package lists, bootstrap
  semantics, CLI help, output names, and all checks remain unchanged.

Smallest public boundary: compare nrfutil and west shell drvPaths before/after,
then run existing selector, west-boundary, bootstrap, doctor, and full flake
gates.

## Scope

In scope:

- Move backend-owned Nix modules into `nix/backends/<backend>/`.
- Split current 392-line `nix/mk-nrf-shell.nix` into dispatcher plus two backend
  constructors/shells.
- Update flake/check/shared-dispatcher imports and current active documentation.
- Preserve all scripts at current `bin/` paths.

Out of scope:

- Shared command/hardware module moves.
- Python command wrapper abstraction.
- Fake workspace fixture deduplication.
- Completed handoff archive/docs cleanup.
- Any behavior, output, test, workflow, template, or backend-support change.

## Exact target files

Add/move:

```text
nix/backends/default.nix
nix/backends/nrfutil/default.nix
nix/backends/nrfutil/shell.nix
nix/backends/nrfutil/bootstrap.nix
nix/backends/west/default.nix
nix/backends/west/shell.nix
nix/backends/west/bootstrap.nix
nix/backends/west/versions.nix
nix/backends/west/versions-command.nix
nix/backends/west/zephyr-sdk.nix
```

Remove after imports migrate:

```text
nix/mk-nrf-shell.nix
nix/nix-nrf-bootstrap.nix
nix/nix-nrf-west-bootstrap.nix
nix/west-backend/
```

Keep this phase:

```text
nix/nix-nrf.nix
nix/nix-nrf-doctor.nix
nix/nix-nrf-probes.nix
nix/openocd-master.nix
nix/nrf-udev-rules.nix
bin/*
```

## Architecture decisions

### Public dispatcher: `nix/backends/default.nix`

Own only:

- unchanged public function argument signature;
- supported backend list;
- required/common argument forwarding;
- west release validation and west-only rejection of `toolchainBundleId` /
  non-default `nrfutilPackage`;
- exact dispatch to backend constructor.

Do not construct wrappers, packages, CLI modules, SDKs, or shell hooks here.
`builtins.functionArgs` must still show required `ncsVersion` and all current
optional arguments/defaults.

### nrfutil backend

`nix/backends/nrfutil/default.nix` receives internal dependencies (`pkgs`,
OpenOCD, default nrfutil, udev rules, shared `nix-nrf` constructor) and returns
a constructor accepting normalized public shell options.

`shell.nix` owns all current nrfutil branch behavior:

- nrfutil exact executable/package override;
- shell-specific `nix-nrf` construction;
- toolchain selector/description;
- auto/manual bootstrap wrapper paths;
- scoped `toolchain env` evaluation;
- multilib/OpenOCD PATH ordering;
- non-mutating shell hook and project `scripts/bin` handling.

`bootstrap.nix` is a pure move of current `nix/nix-nrf-bootstrap.nix`; it still
packages `bin/nix-nrf-bootstrap` at the same libexec path with the same
derivation name and wrapped environment.

### west backend

`nix/backends/west/default.nix` receives west metadata and internal builders,
then owns all current west branch construction:

- metadata selection already validated by dispatcher;
- metadata-selected Python package;
- exact Zephyr SDK package;
- west bootstrap and versions command modules;
- shell-specific backend-aware `nix-nrf` and doctor label;
- call to west `shell.nix`.

`shell.nix`, `versions.nix`, `versions-command.nix`, and `zephyr-sdk.nix` are
behavior-preserving moves of current west files. `bootstrap.nix` is a move of
current `nix/nix-nrf-west-bootstrap.nix`.

No west module imports nrfutil backend implementation. No nrfutil module imports
west implementation.

### Shared dispatcher interaction

`nix/nix-nrf.nix` remains shared. Update its default nrfutil bootstrap import
to `./backends/nrfutil/bootstrap.nix`. West continues injecting exact
versions/bootstrap command paths.

The `nix-nrf` dispatcher and doctor must keep one identical bootstrap store path
per shell.

### Flake components/checks

Update `nix/flake/components.nix` to import backend constructors/metadata from
new paths. It remains single per-system composition root.

Update direct test imports in:

- `nix/flake/checks/nrfutil.nix`;
- `nix/flake/checks/west.nix`.

Quoting gate must still inject fake SDK builder through public dispatcher.
Do not weaken or replace direct module checks.

## Active documentation updates

Update current/live path references only:

- `README.md`;
- `goals.md`;
- `docs/development/west-backend-status.md`;
- `docs/development/nrfutil-backend-status.md` when relevant;
- `docs/development/sdk-nrf-feasibility-draft.md` future shared path reference;
- source comments and current test comments.

Do not rewrite completed historical handoffs for old paths. Phase 4 will move
those documents into archive. Historical claims remain historical.

## Baseline before editing

Record under `/tmp/opencode`:

```bash
nix flake show --json > /tmp/opencode/refactor-p2-flake-before.json
nix eval --raw .#devShells.x86_64-linux.default.drvPath \
  > /tmp/opencode/refactor-p2-nrfutil-shell-before.txt
nix eval --impure --raw --expr '
  let flake = builtins.getFlake (toString ./.);
  in (flake.lib.x86_64-linux.mkNrfShell {
    backend = "west";
    ncsVersion = "v3.3.0";
  }).drvPath
' > /tmp/opencode/refactor-p2-west-shell-before.txt
nix eval --json .#packages.x86_64-linux --apply builtins.attrNames \
  > /tmp/opencode/refactor-p2-packages-before.json
nix eval --json .#checks.x86_64-linux --apply builtins.attrNames \
  > /tmp/opencode/refactor-p2-checks-before.json
```

## Verification

Focused first:

```bash
nix fmt
nix build -L .#checks.x86_64-linux.backend-selector
nix build -L .#checks.x86_64-linux.bootstrap-tests
nix build -L .#checks.x86_64-linux.bootstrap-quoting
nix build -L .#checks.x86_64-linux.west-bootstrap-tests
nix build -L .#checks.x86_64-linux.west-backend-quoting
nix build -L .#checks.x86_64-linux.west-shell-boundary
nix build -L .#checks.x86_64-linux.doctor-tests
```

Then:

```bash
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
```

Repeat baseline commands. Flake/package/check names, nrfutil shell drvPath, and
west shell drvPath must remain identical. If path-only source moves change a
derivation, inspect generated builder/environment differences and escalate
rather than normalizing drift.

Search current code/active docs for removed paths. Remaining hits must be only
completed historical handoffs or this plan's before-state explanation.

## Constraints

- Use `git mv` for tracked moves.
- No script move, helper abstraction, fixture change, check rename, new input,
  flake.lock edit, public behavior change, docs archive, local artifact cleanup,
  real clean-room run, network workspace download, or hardware.
- Preserve derivation names, executable paths, wrapper environment, package
  order, hook text, error/help text, and comments with their implementation.
- No push, merge, amend, PR, attribution, or destructive commands.

## Commits

Handoff first:

```text
docs(refactor): define backend separation phase
```

Passing implementation:

```text
refactor(backends): separate nrfutil and west modules
```

Return file moves, dispatcher/backend line counts, baseline comparison, tests,
commits, blockers, deviations, and final status.
