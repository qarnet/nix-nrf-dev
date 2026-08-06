# Backend Selector Phase Handoff

## Goal

Add a stable backend selector to `mkNrfShell` without changing current shell
behavior. Current and default backend is `"nrfutil"`. Reserve `"sdk-nrf"` as
documented future direction, but reject it until implemented.

## Grounding

- `nix/mk-nrf-shell.nix` currently accepts `ncsVersion`, `name`, `packages`,
  `withMultilib`, `extraShellHook`, and `inputsFrom`; all behavior is the
  nrfutil/sdk-manager path.
- `flake.nix` constructs and exports `mkNrfShell` per system and uses it for
  both dogfood shells.
- `templates/default/flake.nix` and `README.md` show consumer calls.
- `docs/development/clean-bootstrap-versioning-plan.md` records the supported
  nrfutil backend and future Nix-native sdk-nrf backend.
- `goals.md` item 3.1 records future Nix-native sdk-nrf work.

## Exact API decision

Add optional argument:

```nix
backend ? "nrfutil",
```

Accepted values in this phase:

```text
nrfutil
```

Default omission and explicit `backend = "nrfutil"` must produce unchanged
shell behavior.

Any other value, including future `"sdk-nrf"`, must fail at Nix evaluation
with concise message containing invalid value and supported values. Preferred
shape:

```text
mkNrfShell: unsupported backend 'sdk-nrf'; supported backends: nrfutil
```

Do not silently fall back to nrfutil. Do not accept aliases such as `"nix"`,
`"ncs"`, or `"hermetic"`.

## In scope

### `nix/mk-nrf-shell.nix`

- Add `backend ? "nrfutil"` near `ncsVersion`.
- Document `nrfutil` as current implementation.
- Force backend validation when returned shell derivation is evaluated.
- Preserve every existing nrfutil code path unchanged after validation.
- Add backend to shell banner only if doing so does not break existing tests;
  preferred banner is:

  ```text
  <name> shell (backend nrfutil, NCS <version>, toolchain env scoped to west)
  ```

### `flake.nix`

- Dogfood explicit `backend = "nrfutil"` in `devShells.default` and
  `devShells.clean-env-test` so repository exercises public option.
- Add evaluation-level check covering:
  1. omitted backend evaluates,
  2. explicit `"nrfutil"` evaluates,
  3. unsupported `"sdk-nrf"` does not evaluate.
- Implement check as normal `checks` derivation using `builtins.tryEval` or an
  equally local Nix evaluation mechanism. Do not add shell-script parsing of
  source text.
- Avoid building full SDK or running network bootstrap.

### Consumer documentation

Update:

- `README.md`
- `templates/default/flake.nix`
- `nix/mk-nrf-shell.nix` usage comment

Show:

```nix
devShells.default = nix-nrf-dev.lib.${system}.mkNrfShell {
  backend = "nrfutil";
  ncsVersion = "v3.3.0";
};
```

Add `backend` to documented signature table. Explain:

- `"nrfutil"` uses Nordic sdk-manager and is only implemented backend.
- `"sdk-nrf"` is reserved for future Nix-native environment and currently
  fails evaluation.
- `ncsVersion` remains per-project and customizable; v3.3.0 is tested default,
  not architecture lock. (Superseded by the later Nixpkgs nrfutil migration:
  `ncsVersion` is now a required argument with no default.)

### Design and roadmap documentation

Update:

- `docs/development/clean-bootstrap-versioning-plan.md`
- `goals.md`

Use exact backend names:

```text
nrfutil
sdk-nrf
```

Document version direction:

- sdk-nrf backend must use version metadata keyed by NCS release.
- Each entry derives west manifest, Nordic Zephyr revision, Zephyr SDK release
  and targets, Python requirements, and host-tool versions from that release.
- One tested default is convenience only.
- Supporting multiple releases is a core acceptance criterion; future backend
  must not encode v3.3.0 as sole architecture.
- v3.3.0 remains first proof target because installed source and hardware test
  evidence exist, not because backend is permanently tied to it.

Replace any proposed backend name `"nix"` or standalone library name
`ncs-nix` with `"sdk-nrf"` where referring to this future backend. Preserve
official term “nRF Connect SDK (NCS)” when discussing product generally.

## Public-boundary verification

Smallest regression boundary is Nix evaluation of consumer-visible
`mkNrfShell` calls.

Required checks:

```bash
nix fmt
nix flake check -L
nix develop --command sh -c 'command -v west && command -v nrfutil && command -v openocd && command -v nrf-probes'
nix develop .#clean-env-test --command sh -c 'command -v west && command -v nrfutil'
```

Also verify unsupported backend fails. This may be covered by flake check, but
run direct expression if needed:

```bash
nix eval --impure --expr '
  let
    flake = builtins.getFlake (toString ./.);
    system = builtins.currentSystem;
  in
    (flake.lib.${system}.mkNrfShell { backend = "sdk-nrf"; }).drvPath
'
```

Expected: non-zero evaluation with unsupported-backend message.

## Constraints

- Do not implement sdk-nrf backend.
- Do not alter current nrfutil wrapper/bootstrap behavior.
- Do not add automatic downloads.
- Do not change version defaults in this phase.
- Do not package toolchains or Python environments.
- Do not modify hardware behavior, OpenOCD, TCL, or probe detection.
- Keep `inputsFrom`, package composition, scoped environment, and shell hooks
  backward compatible.
- Do not overwrite or remove user-authored `sources.md` or roadmap work.
- Do not commit, push, amend, or open a PR; user requested implementation but
  did not request a commit.

## Executor return

Return concise recap with:

- files changed,
- API and observable behavior,
- tests/commands run and results,
- deviations or blockers,
- current git status.

Escalate instead of guessing if backend validation cannot be covered without
evaluating unsupported shell during normal flake evaluation, if existing checks
conflict with this API, or if implementation would require broader refactor.
