# Phase 1 Handoff — Clean Shell Composition and Regression Gate

## Goal

Harden `mkNrfShell` as the reusable base for hybrid Nordic projects. Add
standard `inputsFrom` composition and executable regression coverage proving
that Nordic sdk-manager variables remain scoped away from unrelated tools.

## Grounding evidence

- `nix/mk-nrf-shell.nix:7-14` documents why global sdk-manager evaluation is
  unsafe and scopes it to the `west` wrapper.
- `nix/mk-nrf-shell.nix:73-84` currently creates `pkgs.mkShell` with packages
  but no `inputsFrom` argument.
- `flake.nix:97-99` exports `mkNrfShell`; this public API must remain backward
  compatible.
- `flake.nix:108-114` dogfoods `mkNrfShell` for the default development shell.
- `.github/workflows/ci.yml:54-56` only checks that a few shell tools exist; it
  does not verify shell cleanliness or execute Node.
- `README.md:37-41` promises that `PYTHONHOME`, `PYTHONPATH`,
  `LD_LIBRARY_PATH`, and `GIT_EXEC_PATH` do not poison external tools.
- Reproduced consumer failure: Nordic's Brotli 1.0.7 shadows Nix's Brotli and
  causes Node 24 to report
  `undefined symbol: BrotliEncoderAttachPreparedDictionary`.

## In scope

### 1. Public `mkNrfShell` composition API

Edit `nix/mk-nrf-shell.nix`:

- Add `inputsFrom ? []` beside existing optional arguments.
- Pass `inputsFrom` unchanged to `pkgs.mkShell` using `inherit`.
- Preserve all existing defaults and behavior for consumers that omit it.
- Update the usage comment to show that hybrid consumers may pass derivations
  through `inputsFrom`.

Do not invent an `extraAttrs` escape hatch or change the existing `packages`,
`withMultilib`, `extraShellHook`, `ncsVersion`, or `name` semantics.

### 2. Dedicated clean-environment test shell

Edit `flake.nix`:

- Keep `devShells.default` unchanged in behavior.
- Add `devShells.clean-env-test` built through `mkNrfShell`.
- Use a descriptive name such as `nix-nrf-dev-clean-env-test`.
- Set `withMultilib = false` to keep this test shell small.
- Include `pkgs.nodejs`, `pkgs.git`, and `pkgs.python3` in `packages`.
- This shell exists to exercise actual shell-hook behavior and dynamic
  linking; do not replace it with a sandboxed `runCommand` that bypasses the
  shell hook.

### 3. CI regression gate

Edit `.github/workflows/ci.yml` after the existing devshell tool check:

- Enter `.#clean-env-test` with `nix develop`.
- Use `sh -ceu` and fail if any of `LD_LIBRARY_PATH`, `PYTHONPATH`, or
  `GIT_EXEC_PATH` contains `ncs/toolchains`.
- Require `PYTHONHOME` to be empty/unset.
- Execute all of:
  - `nix --version`
  - `node --version`
  - `git --version`
  - `python3 -c 'import json'`
- Keep shell quoting readable and robust under `set -u`.

Checking executable startup is mandatory. Variable assertions alone do not
prove compatible dynamic libraries were selected.

### 4. Documentation

Edit `README.md`:

- Add `inputsFrom` to the documented `mkNrfShell` signature/output table.
- Add a short hybrid-consumer example using `inputsFrom = [ myPackage ];`.
- Preserve the existing scoped-environment explanation.

Edit `CONTRIBUTING.md` if needed so local validation includes the clean-shell
command. Keep documentation concise and executable.

Keep this handoff document in the commit as implementation provenance.

## Out of scope

- Do not edit the pre-existing root goals document; it was untracked user
  work at the time.
- Do not add a generic `nrf-env` wrapper.
- Do not package the full NCS toolchain hermetically.
- Do not change `west`, OpenOCD, nrfutil, probe detection, TCL, flashing, or
  hardware behavior.
- Do not modify consumer repositories.
- Do not update dependency pins unless required by the scoped change; report
  such a requirement instead of doing it silently.

## Validation

Run from `/home/thomas-workstation/repos/nix-nrf-dev`:

```bash
nix fmt
nix flake check -L
pre-commit run --all-files
nix develop .#clean-env-test --command sh -ceu '
  case "${LD_LIBRARY_PATH:-}" in *ncs/toolchains*) exit 1;; esac
  case "${PYTHONPATH:-}" in *ncs/toolchains*) exit 1;; esac
  case "${GIT_EXEC_PATH:-}" in *ncs/toolchains*) exit 1;; esac
  test -z "${PYTHONHOME:-}"
  nix --version
  node --version
  git --version
  python3 -c "import json"
'
```

Also verify existing consumers remain source-compatible by evaluating:

```bash
nix flake show
nix develop --command sh -c 'command -v west && command -v openocd && command -v nrf-probes'
```

No hardware run is required because this phase does not alter firmware or
flashing paths.

## Repository and commit constraints

- Follow `CONTRIBUTING.md` and Conventional Commits.
- Do not stage or modify the pre-existing untracked root goals document.
- Inspect `git status`, `git diff`, and `git log --oneline -10` before commit.
- Stage only files in this handoff's scope.
- Commit completed work before returning. Suggested message:
  `feat(shell): add clean hybrid shell composition`
- Do not push, merge, amend, force-push, open a PR, or add attribution footers.

## Return recap

Return:

1. Files changed.
2. API and behavior changes.
3. Every validation command and result.
4. Commit hash and message.
5. Any blocker or deviation.
6. Suggested Phase 2 follow-up.
