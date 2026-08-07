# Repository Architecture Cleanup and Refactor Plan

Status: accepted direction, phased implementation. Preserve behavior before
adding features. Each phase must pass the full gate and commit independently.

## Goal

Make two proven backends easier to understand and maintain:

- `nrfutil`: Nordic sdk-manager workspace/toolchain backend;
- `west`: Nix Zephyr SDK/host tools/Python plus mutable west workspace/venv.

Backend-specific code should live under its backend. Shared CLI, hardware,
packaging helpers, flake wiring, and tests should have explicit shared homes.
`flake.nix` should describe inputs and delegate output construction, not contain
hundreds of lines of package/check implementation.

No user-visible behavior, output name, backend default, CLI contract, build
result, or workflow should change solely because of this refactor.

## Current evidence

- `flake.nix` is 1172 lines. Roughly 830 lines are check implementations.
- `nix/mk-nrf-shell.nix` is 392 lines and contains the complete nrfutil shell
  plus west backend construction/dispatch.
- Five Nix command modules repeat install/patch/wrap boilerplate.
- West quoting and shell-boundary checks duplicate fake workspace creation.
- West builder imports and selected v3.3.0 metadata are wired repeatedly in
  `flake.nix`.
- All current Nix and command files are load-bearing; old command names were
  already removed.
- Active repository has 14 flake checks and proven clean-room scripts for both
  backends. These are regression boundaries, not cleanup candidates.
- `docs/development/` mixes current status documents with completed handoffs.
- Local ignored `result*`, `.direnv`, `.pre-commit-config.yaml`, and
  `.ruff_cache` are generated artifacts; only `.ruff_cache/` is missing from
  root `.gitignore`.
- Untracked `docs/development/sdk-nrf-feasibility-draft.md` is a requested,
  active future-direction draft and should be kept.

## Target layout

Final shape, reached incrementally:

```text
nix/
├── flake/
│   ├── per-system.nix
│   ├── components.nix
│   ├── dev-shells.nix
│   └── checks/
│       ├── default.nix
│       ├── backend-selector.nix
│       ├── core.nix
│       ├── nrfutil.nix
│       └── west.nix
├── backends/
│   ├── default.nix                 # public mkNrfShell dispatcher
│   ├── nrfutil/
│   │   ├── default.nix
│   │   ├── shell.nix
│   │   └── bootstrap.nix
│   └── west/
│       ├── default.nix
│       ├── shell.nix
│       ├── bootstrap.nix
│       ├── versions.nix
│       ├── versions-command.nix
│       └── zephyr-sdk.nix
├── commands/
│   ├── default.nix                 # nix-nrf dispatcher
│   ├── doctor.nix
│   └── probes.nix
├── hardware/
│   ├── openocd.nix
│   └── udev-rules.nix
└── lib/
    └── mk-python-command.nix

bin/
├── backends/
│   ├── nrfutil/nix-nrf-bootstrap
│   └── west/{nix-nrf-west-bootstrap,nix-nrf-west-versions}
└── commands/{nix-nrf-doctor,nix-nrf-probes}

tests/
├── fixtures/west-workspace.py
├── unit/...
├── clean-room/...
├── west-backend/...
└── hardware/...
```

Exact names may change only when a Nix naming conflict demands it. Ownership
must remain obvious from paths.

Do not add `flake-parts` or another framework. Plain Nix imports are enough and
avoid a new dependency/API migration.

## Ownership rules

### Shared

- Public `mkNrfShell` argument validation and backend dispatch.
- `nix-nrf` dispatcher, probes, doctor, OpenOCD, udev rules.
- Python command packaging helper.
- Flake output assembly, formatting, pre-commit, and shared checks.
- Public CLI contracts and common test fixtures.

### nrfutil backend

- nrfutil package selection/override.
- sdk-manager bootstrap/state checks.
- toolchain-bundle selection.
- scoped Nordic toolchain environment.
- nrfutil-specific clean-room proof.

### west backend

- version metadata and supported-version command.
- Zephyr SDK package assembly.
- mutable west workspace/venv bootstrap.
- west shell and scoped venv west wrapper.
- west-specific clean-room proof.

No backend imports implementation details from the other backend. Shared code
may receive backend commands/configuration as explicit arguments.

## Phases

### Phase 1 — Extract flake construction and checks

Shrink root `flake.nix` first without moving backend/command source files.
This is the lowest-risk seam: checks are already closed expressions.

Add:

```text
nix/flake/per-system.nix
nix/flake/components.nix
nix/flake/dev-shells.nix
nix/flake/checks/default.nix
nix/flake/checks/backend-selector.nix
nix/flake/checks/core.nix
nix/flake/checks/nrfutil.nix
nix/flake/checks/west.nix
```

Root `flake.nix` retains inputs, calls `eachDefaultSystem`, imports
`per-system.nix`, and retains small non-system template/NixOS-module outputs.
Target: approximately 80-140 lines, not an arbitrary one-line wrapper.

Preserve exact output/check names and all current gate behavior.

### Phase 2 — Separate backend implementations

Move nrfutil shell body out of `mk-nrf-shell.nix`. Move west modules and each
bootstrap wrapper into backend directories. Reduce public dispatcher to common
arguments, validation, restrictions, and backend constructor call.

Preserve:

- required `ncsVersion` function argument;
- default `backend = "nrfutil"`;
- omitted/explicit nrfutil derivation equality;
- west release/toolchainBundleId/nrfutilPackage validation;
- exact shell package composition and hooks;
- command store-path sharing between dispatcher and doctor.

No script moves yet if they would mix source relocation with Nix behavior.

### Phase 3 — Shared commands and deduplication

Move shared CLI/hardware modules into explicit directories. Add one small
`mk-python-command.nix` helper for repeated:

- script installation into `$out/libexec/nix-nrf/<command>`;
- shebang patching;
- exact wrapped environment variables;
- `PYTHONHOME`/`PYTHONPATH` removal.

Move backend scripts to backend-owned paths and shared scripts to command
paths. Replace duplicated fake west workspace heredocs with one fixture
creator used by quoting and public-boundary checks.

Keep helper narrow. Do not hide backend state machines behind a generic
framework.

### Phase 4 — Documentation and artifact cleanup

- Keep active docs in `docs/development/`:
  - backend status documents;
  - clean bootstrap/versioning status;
  - `sdk-nrf-feasibility-draft.md`;
  - this refactor plan while active.
- Move completed handoffs/plans to `docs/development/archive/`; preserve history
  rather than deleting it. Add archive README and update active links.
- Archive superseded `sdk-nrf-prototype-handoff.md`; keep feasibility draft as
  current non-binding direction.
- Keep `sources.md`, current harness docs, workflows, templates, TCL recipes,
  and all tests.
- Add `.ruff_cache/` to `.gitignore`.
- Remove ignored local build/result/cache artifacts only; never delete caller
  data, Nix store paths, or SDK workspaces.
- Review stale workflow comments and the hardware workflow's `nix_path`
  channel mismatch separately; change executable behavior only with evidence.

### Phase 5 — Final architecture verification

- Run every focused suite and `nix flake check -L`.
- Build all public packages named by CI.
- Enter default nrfutil shell and a fake-state public west shell.
- Run both clean-room harnesses in dry-run mode only.
- Compare flake output names with Phase 1 baseline.
- Verify no old source paths/names remain outside archived historical docs.
- Update README architecture/maintainer section with final paths.

No real SDK/workspace download, hardware operation, push, PR, release, or cache
publication is part of this refactor.

## Definitely not cleanup targets

- `tests/clean-room`, `tests/west-backend`, `tests/hardware`.
- Current unit tests and all flake regression checks.
- `docs/development/west-backend-status.md` and
  `docs/development/nrfutil-backend-status.md`.
- `packages.west-zephyr-sdk-v3_3_0` while west v3.3.0 is supported.
- OpenOCD/udev modules, workflows, templates, TCL recipes, `sources.md`.
- Historical old-name assertions proving removed commands stay absent.

## Phase 1 implementation handoff

### Goal

Extract per-system construction and all check implementations from root
`flake.nix` with zero behavior/output changes.

### Before editing

Record baseline under `/tmp/opencode`:

```bash
nix flake show --json > /tmp/opencode/nix-nrf-flake-before.json
nix eval --raw .#devShells.x86_64-linux.default.drvPath \
  > /tmp/opencode/nix-nrf-default-shell-before.txt
nix eval --json .#packages.x86_64-linux --apply builtins.attrNames \
  > /tmp/opencode/nix-nrf-packages-before.json
nix eval --json .#checks.x86_64-linux --apply builtins.attrNames \
  > /tmp/opencode/nix-nrf-checks-before.json
```

If CLI syntax differs in installed Nix, use an equivalent read-only eval and
record exact command.

### Extraction boundaries

`nix/flake/components.nix` receives `pkgs` and returns:

- OpenOCD wrapped/unwrapped;
- udev rules;
- nrfutil;
- standalone `nix-nrf`;
- west versions, selected repository test version/entry, SDK output, builders;
- public `mkNrfShell`.

Use one import of each builder where possible. Do not change derivation code.
Keep repository test version `v3.3.0` in this component module, not checks.

`nix/flake/dev-shells.nix` receives `pkgs`, `mkNrfShell`, and `pre-commit` and
returns current `default` and `clean-env-test` shells. Preserve arguments.

Checks:

- `backend-selector.nix`: selector/evaluation gate only.
- `west.nix`: west bootstrap, versions, metadata, quoting, shell-boundary.
- `nrfutil.nix`: nrfutil bootstrap and bootstrap quoting.
- `core.nix`: doctor, help wording, udev rule, doctor-udev wiring.
- `checks/default.nix`: composes named attrsets and rejects duplicate keys
  through normal Nix attrset construction (do not silently overwrite).

Move regression comments with implementations. Each check module receives only
explicit dependencies it uses. Avoid one giant `{ inherit (components) ...; }`
when a narrower attrset suffices.

`nix/flake/per-system.nix` receives `self`, `system`, `nixpkgs`, `treefmt-nix`,
and `git-hooks`; imports configured Nixpkgs, components, formatter/pre-commit,
checks, and dev shells; returns current `packages`, `lib`, `formatter`,
`checks`, and `devShells` attrsets.

Root `flake.nix` retains non-system outputs exactly:

- `templates.default`;
- `nixosModules.default` referencing
  `self.packages.${system}.udev-rules`.

### Constraints

- No new flake input/dependency.
- No backend/module/script moves this phase.
- No check deletion/renaming.
- No public package/devShell/lib output deletion/renaming.
- No help text, shell hook, wrapper, test, workflow, README, or behavior edits.
- Do not touch untracked `sdk-nrf-feasibility-draft.md` except include it in
  separate planning-doc commit with this file.
- Preserve `allowUnfree` and SEGGER acceptance exactly.
- Preserve all `self` wiring and exact west builder arguments.

### Verification

```bash
nix fmt
nix flake show --json > /tmp/opencode/nix-nrf-flake-after.json
nix eval --raw .#devShells.x86_64-linux.default.drvPath
nix eval --json .#packages.x86_64-linux --apply builtins.attrNames
nix eval --json .#checks.x86_64-linux --apply builtins.attrNames
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

Compare before/after output-name JSON exactly. Default shell `drvPath` should
remain identical; if extraction alone changes it, explain exact cause before
accepting. Do not normalize unexpected drift.

### Commits

Planning documents first:

```text
docs(refactor): plan repository architecture cleanup
```

Phase implementation after all gates pass:

```text
refactor(flake): extract per-system modules
```

Do not push, merge, amend, open PR, run real clean-room tests, access hardware,
or include attribution. Return files, line-count reduction, baseline comparison,
tests, commits, blockers, and deviations.
