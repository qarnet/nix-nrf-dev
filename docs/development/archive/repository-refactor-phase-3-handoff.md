> **Archived**: this handoff described a completed phase of the repository
> refactor. It is kept as historical evidence; see
> `docs/development/archive/repository-refactor-plan.md` for the archived plan and the
> archive README for the full index.

# Repository Refactor Phase 3 — Shared Components and Deduplication Handoff

## Goal

Give shared CLI/hardware code explicit homes, move backend command scripts under
backend ownership, deduplicate five Python command wrappers, and replace two
copies of fake west workspace setup with one test fixture creator.

Backend state machines and public behavior must not change.

## Current state

Phase 2 established:

```text
nix/backends/default.nix
nix/backends/nrfutil/{default,shell,bootstrap}.nix
nix/backends/west/{default,shell,bootstrap,versions,versions-command,zephyr-sdk}.nix
```

Still mixed at Nix root:

```text
nix/nix-nrf.nix
nix/nix-nrf-doctor.nix
nix/nix-nrf-probes.nix
nix/openocd-master.nix
nix/nrf-udev-rules.nix
```

Five modules duplicate `runCommand` + script install + `patchShebangs` +
`wrapProgram` + Python environment cleanup. West quoting and shell-boundary
checks duplicate the same fake workspace/requirements/venv structure.

## Scope

In scope:

- Shared Nix command and hardware module moves.
- Backend/shared command script moves without renaming script basenames.
- Narrow shared Python-command packaging helper.
- Shared fake west workspace fixture creator.
- Import/test/current-doc/comment updates.

Out of scope:

- Backend state-machine or CLI behavior changes.
- Public output/check names.
- Shell/package option changes.
- Flake dependency/input changes.
- Historical docs archive/deletion (Phase 4).
- Workflow/template/harness behavior changes.

## Exact target files

Move:

```text
nix/nix-nrf.nix              -> nix/commands/default.nix
nix/nix-nrf-doctor.nix       -> nix/commands/doctor.nix
nix/nix-nrf-probes.nix       -> nix/commands/probes.nix
nix/openocd-master.nix        -> nix/hardware/openocd.nix
nix/nrf-udev-rules.nix        -> nix/hardware/udev-rules.nix

bin/nix-nrf-bootstrap         -> bin/backends/nrfutil/nix-nrf-bootstrap
bin/nix-nrf-west-bootstrap    -> bin/backends/west/nix-nrf-west-bootstrap
bin/nix-nrf-west-versions     -> bin/backends/west/nix-nrf-west-versions
bin/nix-nrf-doctor            -> bin/commands/nix-nrf-doctor
bin/nix-nrf-probes            -> bin/commands/nix-nrf-probes
```

Add:

```text
nix/lib/mk-python-command.nix
tests/fixtures/west-workspace.py
```

Remove old empty root paths/directories after all imports migrate.

Keep script basenames and shebang/content unchanged except comments referring
to source paths. Basename stability minimizes unnecessary source-store drift.

## `mk-python-command.nix` exact responsibility

API:

```nix
mkPythonCommand {
  pname = "nix-nrf-doctor";
  script = ../../bin/commands/nix-nrf-doctor;
  destination = "doctor";
  wrapperArgs = [
    [ "--set" "NAME" value ]
    [ "--unset" "PYTHONPATH" ]
    [ "--prefix" "PATH" ":" path ]
  ];
}
```

Helper owns only:

1. `pkgs.runCommand pname`;
2. `nativeBuildInputs = [ pkgs.makeWrapper pkgs.python3 ]`;
3. install executable script at `$out/libexec/nix-nrf/${destination}`;
4. `patchShebangs` exact destination;
5. flatten and shell-escape ordered `wrapperArgs`;
6. call `wrapProgram` once.

Use ordered list-of-lists, not an attrset, so current wrapper argument order is
explicit and stable. Assert `pname`, `destination`, script, and every flattened
wrapper argument are strings/path-compatible. Do not add runtime inputs,
standalone `$out/bin` commands, default environment variables, dynamic command
discovery, or backend policy.

Callers own all wrapper arguments, including explicit `PYTHONPATH` and
`PYTHONHOME` unsets. This keeps differences visible:

- nrfutil bootstrap: nrfutil path + optional selector defaults;
- west bootstrap: selected Python + version/requirements/constraints;
- west versions: sorted text/JSON lists;
- doctor: exact bootstrap, label, optional NCS/udev paths;
- probes: OpenOCD/coreutils PATH prefixes.

Preserve current derivation `pname`, libexec destination, wrapper variable
values, and argument ordering for each module.

## Shared command ownership

`nix/commands/default.nix` remains backend-aware dispatcher. Update imports:

- probes: `./probes.nix`;
- doctor: `./doctor.nix`;
- default bootstrap: `../backends/nrfutil/bootstrap.nix`.

Backend constructors receive/import this shared dispatcher from
`nix/commands/default.nix`. Doctor and dispatcher continue sharing one exact
bootstrap command store path.

Hardware modules move without behavior changes. `nix/flake/components.nix`
becomes only construction site for wrapped/unwrapped OpenOCD, udev rules,
standalone dispatcher, backend metadata/builders, and public shell factory.

## Shared west fixture

Add `tests/fixtures/west-workspace.py`, stdlib-only. Public CLI:

```text
west-workspace.py --workspace PATH --mode stdout
west-workspace.py --workspace PATH --mode log
```

Both modes create the same ready structure currently duplicated in
`nix/flake/checks/west.nix`:

- `.west/config`;
- `nrf/west.yml`;
- `zephyr/zephyr-env.sh`;
- Zephyr/NCS/MCUboot requirement roots and west constraints;
- executable `.venv/bin/python`, `pip`, and `west`.

`stdout` mode matches quoting gate behavior: Python/pip return success; west
prints version for `--version`, otherwise prints argv + `ZEPHYR_BASE`.

`log` mode matches boundary gate behavior: executables append exact current
messages/environment to `$HOME/venv.log`; west returns version on `--version`.

Fixture must:

- resolve workspace to absolute path;
- refuse `/`, current HOME, existing non-empty directories, or paths escaping
  requested workspace through symlinks;
- create only inside requested workspace;
- never delete, run network, invoke pip/west, or touch real SDK state.

Replace only duplicated creation blocks in west quoting/boundary checks. Keep
all behavior assertions in Nix checks unchanged. Add `pkgs.python3` to quoting
check native inputs as needed. Existing checks are fixture acceptance; no unit
test of fixture internals is required unless implementation adds parsing/state
logic beyond this contract.

## Current references to update

- Nix imports in backends, flake components, and checks.
- Unit-test fallback script paths.
- Check source paths.
- `treefmt.nix` Python formatter comment.
- Active README/roadmap/status/feasibility/refactor docs.
- Current source/test headers.

Leave completed historical handoffs unchanged; Phase 4 archives them.
Intentional assertions that removed old public command names stay absent remain.

## Baseline and expected derivation behavior

Before edits record:

```bash
nix flake show --json > /tmp/opencode/refactor-p3-flake-before.json
nix eval --raw .#devShells.x86_64-linux.default.drvPath \
  > /tmp/opencode/refactor-p3-nrfutil-shell-before.txt
nix eval --impure --raw --expr '
  let flake = builtins.getFlake (toString ./.);
  in (flake.lib.x86_64-linux.mkNrfShell {
    backend = "west";
    ncsVersion = "v3.3.0";
  }).drvPath
' > /tmp/opencode/refactor-p3-west-shell-before.txt
```

Output/check/package names must remain identical. Command-module and shell
drvPaths may change because wrapper derivations are deliberately centralized.
Attempt to preserve them through same pnames, script basenames, destinations,
and ordered wrapper arguments, but do not force identity by retaining duplicate
code. If paths change, compare generated wrappers and runtime behavior; explain
exact structural cause. Unexpected environment/content differences are defects.

## Verification

```bash
nix fmt
python3 tests/unit/test_nix_nrf_bootstrap.py
python3 tests/unit/test_nix_nrf_west_bootstrap.py
python3 tests/unit/test_nix_nrf_west_versions.py
python3 tests/unit/test_nix_nrf_doctor.py
nix build -L .#checks.x86_64-linux.bootstrap-tests
nix build -L .#checks.x86_64-linux.bootstrap-quoting
nix build -L .#checks.x86_64-linux.doctor-tests
nix build -L .#checks.x86_64-linux.doctor-udev-wiring
nix build -L .#checks.x86_64-linux.west-bootstrap-tests
nix build -L .#checks.x86_64-linux.west-versions-tests
nix build -L .#checks.x86_64-linux.west-backend-quoting
nix build -L .#checks.x86_64-linux.west-shell-boundary
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

Also:

- inspect all generated command wrappers for expected set/unset/prefix values;
- compare flake output-name JSON exactly;
- grep current source/tests for old root module/script paths;
- confirm historical-doc-only leftovers are intentional.

## Constraints

- `git mv` tracked files.
- No backend logic/CLI text/state transition change.
- No public output/check rename or new check.
- No flake input/lock change.
- No historical docs archive yet.
- No ignored artifact deletion yet.
- No real clean-room, network workspace bootstrap, developer NCS, hardware,
  push, merge, amend, PR, force-push, sudo, or attribution.

## Commits

Handoff:

```text
docs(refactor): define shared component phase
```

Implementation:

```text
refactor(nix): share command packaging and fixtures
```

Return moves, duplicate-line reduction, helper API, fixture behavior, wrapper
comparison, output/baseline comparison, tests, commits, blockers/deviations,
and final status.
