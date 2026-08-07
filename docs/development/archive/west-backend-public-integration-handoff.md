# Public `west` Backend Integration Handoff

## Goal

Promote the proven hybrid west environment into the public
`lib.<system>.mkNrfShell` API:

```nix
devShells.default = nix-nrf-dev.lib.${system}.mkNrfShell {
  backend = "west";
  ncsVersion = "v3.3.0";
};
```

Nix continues to own the exact Zephyr SDK, host tools, and Python interpreter.
The mutable west workspace and version-local venv continue to own NCS source,
west, and workspace Python requirements. Public `nix-nrf bootstrap`,
`nix-nrf versions`, and `nix-nrf doctor` become backend-aware. The existing
`nrfutil` backend remains the default and must not change behavior.

Phase 1 proof is complete in commits `1747fbe` and `a782846`; see
`docs/development/west-backend-status.md`. This phase is API integration, not a
second environment experiment.

## User-observable acceptance

1. `mkNrfShell { backend = "west"; ncsVersion = "v3.3.0"; }` evaluates and
   supplies the proven west environment without putting nrfutil on `PATH` or
   using sdk-manager.
2. Shell entry is read-only. It reports readiness and exports `ZEPHYR_BASE`
   only when the workspace is ready.
3. `nix-nrf bootstrap` owns west workspace/venv setup. It prompts before the
   multi-GiB mutation; `--yes` or `NIX_NRF_BOOTSTRAP_YES=1` approves it;
   `--check` is read-only; `--print-sdk-path` prints the workspace root only
   when ready.
4. `autoBootstrap = true` keeps current public semantics: first `west`
   invocation runs backend bootstrap, prompting when setup is missing, then
   builds after setup succeeds. `autoBootstrap = false` checks only and prints
   `Run: nix-nrf bootstrap` without mutation.
5. `nix-nrf versions` in a west shell lists repository-supported west backend
   metadata versions; `--json` emits a JSON string array. It never invokes
   nrfutil.
6. `nix-nrf doctor` checks the same west bootstrap command through its
   read-only `--check --quiet --print-sdk-path` contract and uses a west-specific
   environment label in human messages. Existing JSON field names stay stable.
7. Existing nrfutil shells, CLI behavior, tests, template, and default backend
   remain unchanged.

Smallest public-boundary regression: instantiate a west `mkNrfShell` with a
fake ready HOME, enter it through `nix develop --ignore-env`, run its public
`nix-nrf` and scoped `west`, and prove exact workspace/toolchain variables plus
absence of `nrfutil`.

## Scope

In scope:

- Public `backend = "west"` selector for metadata-supported NCS releases.
- Backend-aware shell-specific `nix-nrf versions`, `bootstrap`, and `doctor`.
- Existing shared `packages`, `inputsFrom`, `name`, `withMultilib`,
  `extraShellHook`, and `autoBootstrap` options for west.
- Removal of temporary public `nix-nrf-west-setup` command and
  `devShells.west-prototype` output.
- Evaluation, fixture, shell-boundary, docs, and full flake gates.

Out of scope:

- Changing default backend from `"nrfutil"`.
- Supporting another NCS release or host platform.
- Immutable NCS repositories or a fully Nix-built Python environment.
- Changing west workspace revision automatically beyond existing `west
  update` behavior.
- Hardware flashing/debugging or another multi-GiB clean-home proof.
- Removing the proven per-version Zephyr SDK package output.
- CI workspace downloads, caching, or scheduled workflows.
- `sdk-nrf` resurrection.

## Grounded current state

- `nix/mk-nrf-shell.nix` currently accepts only `"nrfutil"`; it owns the
  nrfutil scoped west wrapper and shell hook.
- `nix/west-backend/environment.nix` contains the proven west shell, but is a
  fixed prototype: Python 3.12 and shell name are hardcoded, setup helper is a
  standalone package, and auto-bootstrap/public shell options are absent.
- `bin/nix-nrf-west-setup` + `nix/nix-nrf-west-setup.nix` implement the proven
  mutable workspace/venv state machine.
- `nix/nix-nrf.nix` currently constructs nrfutil versions/bootstrap internally.
  Probe and doctor commands are already independent modules; doctor accepts an
  exact bootstrap executable path.
- `bin/nix-nrf-doctor` always invokes bootstrap read-only as
  `--check --quiet --print-sdk-path`, which is the reusable backend contract.
- `nix/west-backend/versions.nix` supports only `v3.3.0`, Zephyr SDK 0.17.0,
  Python 3.12, exact SDK assets, requirement paths, and
  `cbor2==5.9.0` constraint.
- Real proof: setup 436 s, build 18 s, workspace 6.4 G, build 29 M, non-empty
  ELF/domains.yaml, no nrfutil; exact evidence in west backend status doc.

## Exact implementation shape

### 1. Make `mkNrfShell` dispatch both backends

Modify `nix/mk-nrf-shell.nix` without changing its public argument names.

- Supported list becomes `[ "nrfutil" "west" ]`; `"sdk-nrf"` remains
  rejected.
- Keep all current nrfutil code and behavior intact. Use a final backend branch
  rather than duplicating public API parsing.
- For `backend = "west"`, resolve `ncsVersion` from
  `nix/west-backend/versions.nix`. Unknown release fails evaluation and names
  supported west versions.
- Reject non-null `toolchainBundleId` for west with an exact backend-specific
  error.
- Reject a non-default `nrfutilPackage` override for west instead of silently
  ignoring it. Compare derivation output paths safely at evaluation.
- Honor `autoBootstrap`, `name`, `packages`, `withMultilib`, `extraShellHook`,
  and `inputsFrom` for both backends.
- West remains x86_64-linux only through existing clear evaluation failure.

Do not evaluate nrfutil-specific command construction in the selected west
branch. Nix laziness plus explicit backend branching must keep west's shell and
shell-specific `nix-nrf` free of runtime nrfutil/sdk-manager use.

### 2. Make Python package selection metadata-driven

Modify `nix/west-backend/versions.nix` and metadata schema gate in `flake.nix`.

- Add a package attribute name such as `pythonPackage = "python312"` beside
  display version `python = "3.12"`.
- West shell/setup construction selects `pkgs.${metadata.pythonPackage}` and
  fails clearly if missing.
- `nix/west-backend/environment.nix` accepts `pythonPackage`; remove direct
  `pkgs.python312` use.

Release-specific Python package choice must not move into generic builder code.

### 3. Turn temporary setup helper into west bootstrap backend

Rename:

```text
bin/nix-nrf-west-setup              -> bin/nix-nrf-west-bootstrap
nix/nix-nrf-west-setup.nix          -> nix/nix-nrf-west-bootstrap.nix
tests/unit/test_nix_nrf_west_setup.py -> tests/unit/test_nix_nrf_west_bootstrap.py
checks.west-setup-tests              -> checks.west-bootstrap-tests
```

Command remains internal at `$out/libexec/nix-nrf/bootstrap`; do not install a
standalone `$out/bin/nix-nrf-west-*` command.

Public invocation is only:

```text
nix-nrf bootstrap [--workspace PATH] [--yes] [--check]
                  [--quiet] [--print-sdk-path]
```

Behavior stays identical to proven helper except:

- Program/error prefix becomes `nix-nrf bootstrap`.
- `--print-workspace` becomes `--print-sdk-path`; printed path is west
  workspace root (`.../ncs/<version>`), which contains `zephyr/` and satisfies
  doctor/shared shell contract.
- Approval environment variable becomes shared
  `NIX_NRF_BOOTSTRAP_YES=1`; remove `NIX_NRF_WEST_SETUP_YES`.
- Internal wrapped metadata variables may retain `NIX_NRF_WEST_*` names but
  use `BOOTSTRAP`, not `SETUP`, where naming appears in new code.
- Preserve exact cbor2 constraint, command ordering, absolute path handling,
  no-delete/no-reset safety, stdout contract, exit codes, and check timeouts.

Do not add migration aliases for experimental command names. Remove old paths
and references.

### 4. Inject backend commands into `nix-nrf`

Refactor `nix/nix-nrf.nix` to accept optional exact `versionsCommand` and
`bootstrapCommand` inputs.

- When omitted, construct/use current nrfutil versions and bootstrap exactly as
  today. Standalone `packages.nix-nrf` remains nrfutil-backed.
- When provided by west shell, dispatcher and help use those exact store paths;
  do not construct or reference nrfutil bootstrap/version commands.
- Probe command remains shared.
- Doctor receives selected exact bootstrap command.

Add `nix/west-backend/versions-command.nix` (or equivalent small packaged
command) with contract:

```text
nix-nrf versions          # one supported west version per line, sorted
nix-nrf versions --json   # JSON string array, sorted
nix-nrf versions --help   # backend-specific help, exit 0
```

Unknown/options combinations exit 2. Values come only from sorted attr names
of `versions.nix`; do not duplicate `v3.3.0` in script source.

### 5. Reuse doctor with backend-specific label

Modify `nix/nix-nrf-doctor.nix` and `bin/nix-nrf-doctor` minimally.

- Add wrapped `environmentLabel`, default `"SDK/toolchain"` for compatibility.
- West shell passes `"west workspace/Zephyr SDK"`.
- Human headings, status, remediation, and help use label.
- Preserve JSON field names/schema and exit semantics; only message strings may
  reflect selected label.
- Doctor continues to call bootstrap only with
  `--check --quiet --print-sdk-path`; never mutate.

Add fixture coverage proving custom label and exact read-only bootstrap argv.
Keep all existing doctor tests unchanged/passing where default label applies.

### 6. Adapt west shell implementation

Modify `nix/west-backend/environment.nix` into reusable public backend shell.
Inputs include selected metadata, metadata-selected Python package, exact SDK,
west bootstrap command, shell-specific backend-aware `nix-nrf`, and public
shell options.

- Remove hardcoded `name = "west-prototype"` and Python package.
- Package list: SDK, selected Python, host tools, optional multilib, scoped west
  wrapper, OpenOCD, backend-aware nix-nrf, then caller packages.
- Propagate `inputsFrom` and append `extraShellHook` after backend hook.
- Do not expose bootstrap helper separately on PATH.
- Shell hook invokes `nix-nrf bootstrap --check --quiet --print-sdk-path` and
  stays read-only.
- `autoBootstrap = true` wrapper invokes
  `nix-nrf bootstrap --print-sdk-path`; setup prompts when missing.
- `autoBootstrap = false` wrapper invokes
  `nix-nrf bootstrap --check --quiet --print-sdk-path` and reports automatic
  bootstrap disabled plus `Run: nix-nrf bootstrap` on failure.
- Wrapper exports `ZEPHYR_BASE=$workspace/zephyr`, exact Nix SDK variables,
  prepends venv only inside west process, keeps project OpenOCD first, and execs
  exact venv west.
- Banner names backend `west`, NCS version, Zephyr SDK, Python, and bootstrap
  mode. No prototype wording.

### 7. Flake outputs and temporary prototype removal

Modify `flake.nix`:

- Pass west metadata/internal constructors into public `mkNrfShell` as needed.
- Remove `devShells.west-prototype`; public tests instantiate `mkNrfShell` with
  `backend = "west"`.
- Keep `packages.west-zephyr-sdk-v3_3_0` in this phase; update wording from
  temporary prototype to west backend SDK package.
- Rename setup checks/files to bootstrap names.
- Convert existing west quoting check to instantiate public `mkNrfShell` and
  preserve quote/path sensitivity.
- Keep real `tests/west-backend/run.sh` as historical/manual proof harness but
  update it to public shell/API names. Do not run it this phase.

## Validation

### Evaluation selector gate

Extend `checks.backend-selector` to prove:

1. omitted backend still equals valid nrfutil behavior;
2. explicit nrfutil evaluates;
3. west + v3.3.0 evaluates;
4. west unknown version fails and error is manually spot-checked;
5. sdk-nrf remains rejected;
6. west + non-null toolchainBundleId fails;
7. west + non-default nrfutilPackage fails;
8. west autoBootstrap omitted/true/false evaluate;
9. required ncsVersion remains required.

### Fixture tests

Rename/update west bootstrap suite and retain all 32 current cases. Add cases
for:

- public program prefix;
- `NIX_NRF_BOOTSTRAP_YES` approval;
- removed old approval variable has no effect;
- `--print-sdk-path` exact stdout;
- no installed standalone temporary command.

Add versions command fixture/check for text, JSON, help, sorted metadata, and
unknown option exit 2. Extend doctor fixture for west label/read-only argv.

### Public shell boundary check

Use a fake-ready workspace and fake venv executables without network. Through
public `mkNrfShell { backend = "west"; ... }`, prove:

- shell hook does not mutate;
- exact default workspace has no quote artifacts;
- `nix-nrf versions` reports v3.3.0 and JSON parses;
- `nix-nrf bootstrap --check --print-sdk-path` returns exact workspace;
- `nix-nrf doctor` invokes read-only west bootstrap (hardware may use existing
  test override/skip mechanism);
- scoped west reaches exact venv west and exports expected variables;
- `autoBootstrap = false` missing state refuses without mutation;
- `nrfutil` and `nix-nrf-west-setup` are absent from PATH;
- caller `packages`, `inputsFrom`, `extraShellHook`, name, and disabled
  multilib behavior propagate at least once across existing/public checks.

Normal tests must not run west update, pip, or workspace downloads.

## Documentation

Update:

- `README.md`: Backends, Bootstrap, CLI, outputs, and west proof sections.
  Show public consumer snippet. Mark west experimental and v3.3.0/x86_64-only;
  keep nrfutil default/recommended fallback.
- `docs/development/west-backend-status.md`: mark public selector integrated,
  replace temporary command/prototype shell names, preserve proof history.
- `docs/development/nrfutil-backend-status.md`: replace stale claim that only
  nrfutil is implemented; keep nrfutil behavior/status unchanged.
- roadmap item 3.1: rename direction to hybrid west backend and record public
  integration. Do not claim fully hermetic workspace or hardware parity.
- `tests/west-backend/README.md` and harness comments/commands: public API.

Template stays `backend = "nrfutil"` because default/recommended backend does
not change.

## Verification commands

```bash
nix fmt
python3 tests/unit/test_nix_nrf_west_bootstrap.py
python3 tests/unit/test_nix_nrf_doctor.py
nix build -L .#checks.x86_64-linux.backend-selector
nix build -L .#checks.x86_64-linux.west-backend-quoting
nix build -L .#checks.x86_64-linux.west-bootstrap-tests
nix flake check -L
```

Also run focused clean-environment public west shell checks created above. Do
not run `tests/west-backend/run.sh` without new explicit approval.

## Commit and recap

Commit this handoff separately before implementation:

```text
docs(west): plan public backend integration
```

Commit passing implementation:

```text
feat(west): expose public shell backend
```

Do not push, merge, amend, open a PR, flash hardware, use developer NCS state,
or include attribution. Return files changed, API behavior, tests/commands and
results, exact commits, blockers, deviations, and confirmation that nrfutil
behavior/default remain unchanged.
