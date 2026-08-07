> **Archived**: this handoff described the completed final verification phase
> of the repository refactor. See `docs/development/architecture.md` for the
> current architecture; the archive README holds the full index.

# Repository Refactor Phase 5 — Final Architecture Verification Handoff

## Goal

Finish refactor with current architecture documentation, stale maintainer/CI
text fixes, complete package verification, dead-file audit, and final workspace
cleanup. Archive refactor plans after completion.

No backend behavior changes.

## Scope

In scope:

- Add current architecture/ownership document.
- Update README and CONTRIBUTING maintainer guidance.
- Make CI's “Build packages” step build every unique public package output.
- Correct current output/check documentation.
- Audit every current source/test/workflow/manual harness for ownership/use.
- Archive completed master refactor plan and this handoff.
- Run final test/build/smoke/dry-run gate.
- Remove regenerated ignored local artifacts safely after final commit.

Out of scope:

- Feature/backend/API behavior.
- New dependencies/check outputs.
- Real clean-room, hardware, release, PR, or push.

## Architecture document

Add `docs/development/architecture.md` as current maintainer reference.

Required sections:

1. Public entry points:
   - root `flake.nix`;
   - `nix/flake/per-system.nix`;
   - `lib.<system>.mkNrfShell`;
   - `packages.nix-nrf`;
   - NixOS module/template.
2. Construction flow:
   - `nix/flake/components.nix` composition root;
   - packages/checks/dev-shell modules;
   - plain Nix imports, no flake-parts.
3. Backend ownership:
   - dispatcher `nix/backends/default.nix`;
   - nrfutil and west directories, responsibilities, no cross-import rule.
4. Shared ownership:
   - `nix/commands`, `nix/hardware`, `nix/lib`;
   - backend command injection into `nix-nrf`;
   - exact bootstrap path shared with doctor.
5. Script layout under `bin/` and why commands install only to libexec.
6. Tests:
   - flake checks split by domain;
   - unit fixture boundaries;
   - manual clean-room/west/hardware harnesses and approval boundaries.
7. Adding/changing:
   - new west metadata release;
   - new backend;
   - new shared command;
   - new check without growing root flake.
8. Invariants:
   - nrfutil default;
   - required ncsVersion;
   - shell entry non-mutating;
   - no backend silently falls back;
   - no real workspace downloads in normal checks;
   - hardware/real clean-room requires explicit approval.

Keep concise; link detailed current backend status docs rather than duplicate
their proof logs.

## README / CONTRIBUTING corrections

README:

- Add short “Repository architecture” maintainer section linking architecture
  doc and naming `nix/flake`, `nix/backends`, `nix/commands`, `nix/hardware`,
  `nix/lib`, `bin`, and tests.
- Update checks output description to include all 14 current names, notably
  `nix-nrf-help`, `doctor-udev-wiring`, and fixture safety under
  `west-bootstrap-tests`.
- Do not expand public usage prose unnecessarily.

CONTRIBUTING:

- Link architecture doc for source ownership.
- Correct stale “tests/hardware once it exists” wording: it exists and remains
  explicit/manual hardware work.
- Keep actual commands and clean-room warning unchanged.
- Reflow overlong path lines where formatter does not handle Markdown.

## CI package build correction

Current CI step says “build all packages” but omits
`packages.west-zephyr-sdk-v3_3_0`. Add:

```text
.#west-zephyr-sdk-v3_3_0
```

to same `nix build -L` command and document it as west backend SDK package.
Do not build `packages.default` separately because it aliases `nix-nrf`.

No other workflow changes.

## Dead/unneeded file audit

Before declaring cleanup complete, verify:

- every `nix/**/*.nix` file is imported by root construction, another current
  module, or is a public module source;
- every `bin/**/*` command is packaged by exactly one Nix command module;
- every `tests/unit/*.py` and fixture is wired to a flake check;
- clean-room, west-backend, and hardware harnesses are referenced by current
  docs/workflows;
- workflows, templates, TCL recipes, sources.md, treefmt, lock file, and status
  docs remain load-bearing;
- no empty source directories or duplicate old files remain;
- no current non-archive docs point to archived old source paths as current
  architecture.

If a file appears unused, trace references and report before deletion. Delete
no uncertain tracked file. Expected result from current inventory: no further
tracked code/test deletion.

## Complete refactor archive

After implementation passes:

```text
docs/development/archive/repository-refactor-plan.md
docs/development/archive/repository-refactor-phase-5-handoff.md
```

move with `git mv` into `docs/development/archive/`. Update archive README with
master plan and Phase 5 entries. `docs/development/architecture.md` becomes
current replacement. Repair links.

Final active development docs:

```text
architecture.md
roadmap.md
nrfutil-backend-status.md
sdk-nrf-feasibility-draft.md
west-backend-status.md
```

## Verification

```bash
nix fmt
actionlint .github/workflows/*.yml
python3 tests/unit/test_nix_nrf_bootstrap.py
python3 tests/unit/test_nix_nrf_west_bootstrap.py
python3 tests/unit/test_nix_nrf_west_versions.py
python3 tests/unit/test_nix_nrf_doctor.py
python3 tests/unit/test_west_workspace_fixture.py
nix flake check -L
nix build -L \
  .#openocd-master-unwrapped \
  .#openocd-master \
  .#nrfutil \
  .#nix-nrf \
  .#udev-rules \
  .#west-zephyr-sdk-v3_3_0
nix run .#openocd-master -- --version
nix run .#nrfutil -- --version
nix run .#nix-nrf -- --help
nix run .#nix-nrf -- versions --help
nix run .#nix-nrf -- probes --help
nix run .#nix-nrf -- bootstrap --help
nix run .#nix-nrf -- doctor --help
NIX_NRF_WEST_DRY_RUN=1 bash tests/west-backend/run.sh
NIX_NRF_CLEAN_DRY_RUN=1 bash tests/clean-room/run.sh
bash -n tests/hardware/run.sh
```

Verify flake output/check/package names identical to Phase 4 baseline. Verify
root `flake.nix` remains thin and no moved implementation leaks back into it.

After tracked commit, safely remove regenerated exact ignored artifacts using
Phase 4 safeguards; final `git status --short` and relevant
`git status --ignored --short` must be clean.

## Constraints

- No feature/API/backend logic change.
- No new flake input/check/output name.
- No real clean-room/hardware/workflow dispatch, network bootstrap, developer
  NCS, sudo, store deletion, push, merge, amend, PR, force-push, attribution.

## Commits

Handoff first:

```text
docs(refactor): define final verification phase
```

Passing final cleanup:

```text
docs(repo): document cleaned architecture
```

Return architecture summary, CI/doc corrections, full used/kept audit, tests,
commits, artifact cleanup proof, blockers/deviations, final status, and whether
refactor plan is fully complete.
