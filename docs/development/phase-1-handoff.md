# Phase 1 handoff — Repo hygiene foundations

## Phase goal

Lay the non-tooling foundations for a nix-community-standard flake library
repo: MIT LICENSE, a dogfood direnv `.envrc` at the repo root, a `.gitignore`
entry for the future auto-generated pre-commit config, and a short
CONTRIBUTING.md. No flake changes, no formatting, no CI in this phase.

## In scope

Create four files / edits:

1. `LICENSE` (new) — standard MIT license text.
2. `.envrc` (new, at repo root) — single line `use flake`.
3. `.gitignore` (edit existing) — append `.pre-commit-config.yaml`.
4. `CONTRIBUTING.md` (new) — short contributor guide.

## Out of scope

- Any change to `flake.nix`, `flake.lock`, `treefmt.nix`, `nix/**`, `bin/**`,
  `tcl/**`, `templates/**`.
- No formatting run (that is phase 3).
- No pre-commit hooks installed yet (phase 2 wires git-hooks.nix; this phase
  predates it, so commits here are written manually in Conventional Commits
  style — see below).
- No `.github/` workflows (phase 4).

## Files and exact contents

### 1. `LICENSE` (new)

Standard MIT license. Use exactly this text (the SPDX headers already present
in `bin/nrf-probes` and `tcl/*.tcl` declare MIT, so this makes the repo-level
license explicit):

```
MIT License

Copyright (c) 2026 qarnet

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

The copyright holder is `qarnet` (the GitHub org that owns this repo). Year is
2026 (matches the repo's first commit date range and today's date).

### 2. `.envrc` (new, at repo root)

A single line:

```
use flake
```

This is the same content as `templates/default/.envrc`. The two files are
intentionally separate: the root one dogfoods the dev shell on this repo
itself; the template one ships with `nix flake init -t` for consumers. Do NOT
modify or remove `templates/default/.envrc`.

### 3. `.gitignore` (edit existing)

Current contents (verify by reading the file first):

```
result
result-*
.direnv/
```

Append one line so the final file reads:

```
result
result-*
.direnv/
.pre-commit-config.yaml
```

`.pre-commit-config.yaml` is auto-generated at runtime by git-hooks.nix (added
in phase 2) and must never be committed.

### 4. `CONTRIBUTING.md` (new)

Short, factual, matches the repo's real structure and the conventions adopted
in the broader plan. Use exactly this content:

```markdown
# Contributing to nix-nrf-dev

## Development environment

```bash
direnv allow     # or: nix develop
```

The shell provides `openocd` (master build), `nrf-probes`, `nrfutil`, the
scoped `west` wrapper, and the NCS toolchain (via nrfutil sdk-manager for the
configured NCS version).

## Before committing

Formatting and lint hooks run automatically via `pre-commit` (wired through
`git-hooks.nix`). To run them manually:

```bash
nix fmt                       # format all files (alejandra for Nix, black for Python)
nix flake check -L             # run all checks in a sandbox
pre-commit run --all-files      # run hooks without committing
```

## Commit messages

This repo uses [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): description
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `ci`,
`perf`, `build`. Scope is optional but encouraged (e.g. `flake`, `tcl`,
`nrf-probes`, `ci`).

Examples:

- `feat(nrf-probes): add --find flag`
- `fix(tcl): correct nRF5340 UICR address`
- `docs(readme): document scoped toolchain env`
- `chore(flake): add treefmt-nix and git-hooks.nix`

## Bumping the openocd pin

`nix/openocd-master.nix` pins a specific upstream `openocd` revision. To bump:

1. Find a newer revision at <https://github.com/openocd-org/openocd> that has
   the nRF53/nRF54L support you need.
2. Update `rev` in `nix/openocd-master.nix`.
3. Update `hash` (run `nix build .#openocd-master-unwrapped` — Nix will print
   the correct `sha256-...` hash for the failed fetch; paste it in).
4. Run `nix build .#openocd-master-unwrapped -L` and `nix build .#openocd-master -L`.
5. Verify on hardware that the flash recipes still work (see
   `tests/hardware/` once it exists).

## Adding a flash recipe

Flash recipes live in `tcl/`. Each recipe is a standalone TCL file sourced by
openocd. To add one:

1. Add `tcl/<chip>_flash.tcl` with the flashing procs.
2. Document it in `README.md` under "Flash recipes (`tcl/`)".
3. If the chip needs probe identification, ensure `bin/nrf-probes` knows its
   family signature (DPIDR → AP IDR map → FICR PART/VARIANT).

## CI and the openocd-master build

`openocd-master` is built from source in CI on every PR and nightly, cached
via [Cachix](https://app.cachix.org) under the `qarnet` cache. The first build
takes ~10 minutes; subsequent builds pull from the cache in under a minute.

Hardware integration tests run on a self-hosted GitHub Actions runner with
CMSIS-DAP probes and target boards attached. See
`tests/hardware/README.md` (added in a later phase) for runner setup and the
test procedure.

## What this repo is not

This is a Nix flake library, not a firmware project. The `tcl/` recipes and
`bin/nrf-probes` are reusable tools consumed by other repos; they are not
flashed here. Do not add board-specific firmware or build artifacts.
```

## Constraints and invariants

- Conventional Commits: this phase's commit is the **first** Conventional
  Commit in the repo. Use exactly `chore: add LICENSE, root envrc,
  contributing guide` (no scope needed for a multi-file hygiene commit).
- Do NOT modify any existing file other than `.gitignore`.
- Do NOT remove `templates/default/.envrc`.
- Do NOT run `nix fmt` — there is no formatter wired yet (phase 2/3).
- Do NOT push, do NOT open a PR, do NOT amend. Commit locally only.

## Verification

Before committing, verify:

1. `ls LICENSE` shows the file exists.
2. `cat .envrc` shows `use flake`.
3. `git check-ignore .pre-commit-config.yaml` prints `.pre-commit-config.yaml`
   (confirms the gitignore entry works).
4. `cat CONTRIBUTING.md` shows the content above.
5. `git status` shows exactly: `LICENSE` (new), `.envrc` (new),
   `.gitignore` (modified), `CONTRIBUTING.md` (new), and this handoff file
   (`docs/development/phase-1-handoff.md`, new — keep it staged; it is part of
   the commit).
6. `git diff -- .gitignore` shows only the one appended line.

## Commit

Stage only the intended files:

```bash
git add LICENSE .envrc .gitignore CONTRIBUTING.md docs/development/phase-1-handoff.md
```

Commit with:

```
chore: add LICENSE, root envrc, contributing guide
```

(Conventional Commits style — no scope for this multi-file hygiene commit.)

## Recap required from executor

Return a concise summary including:

- Files changed (with status: new/modified).
- The exact commit hash and message.
- Output of the six verification commands.
- Any deviation from this handoff and why.
- `git status` and `git log --oneline -3` after commit.
- Any blockers encountered.

Do not push. Do not open a PR. Do not amend.