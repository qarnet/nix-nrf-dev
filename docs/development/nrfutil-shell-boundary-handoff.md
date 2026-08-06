# Public nrfutil shell-boundary regression handoff

## Goal

Add normal, network-free flake coverage for public
`mkNrfShell { backend = "nrfutil"; ... }` shell orchestration. Existing tests
prove bootstrap command logic, but shell hook and scoped `west` wrapper are
otherwise proven only by manual multi-gigabyte clean-room run.

## Scope

### In scope

- Add `checks.nrfutil-shell-boundary` in `nix/flake/checks/nrfutil.nix`.
- Instantiate public `mkNrfShell`, not backend module directly.
- Use one Nix-built fake `nrfutilPackage`, temporary state, and fake real `west`.
- Exercise shell hook and scoped wrapper as subprocess boundaries.
- Pass `mkNrfShell` into nrfutil check module from
  `nix/flake/per-system.nix`.
- Export check explicitly from `nix/flake/checks/default.nix`.
- Update README check list/count and architecture test ownership.

### Out of scope

- Real Nordic downloads, mutable developer `$HOME`, network, hardware, flashing,
  or real sdk-manager state.
- Changing production shell, bootstrap, dispatcher, or wrapper behavior unless
  test exposes genuine contract bug. Escalate before production changes.
- Re-testing bootstrap parser/install matrix exhaustively; existing
  `tests/unit/test_nix_nrf_bootstrap.py` owns that.
- West-backend shell behavior; `checks.west-shell-boundary` owns it.
- NixOS module, template, TCL recipe, or platform-output changes.
- New inputs or dependencies.

## Grounded gap

- `nix/backends/nrfutil/shell.nix` lines 70-129 build scoped `west` wrapper:
  bootstrap, SDK path validation, scoped toolchain env, optional multilib PATH,
  project OpenOCD precedence, and real-west discovery.
- Same file lines 143-187 build non-mutating shell hook and `ZEPHYR_BASE`
  derivation.
- `checks.bootstrap-tests` runs raw bootstrap command with fake nrfutil but does
  not instantiate or invoke public shell wrapper/hook.
- Manual `tests/clean-room/run.sh` proves real path but is approval-gated,
  multi-GiB, and absent from PR checks.
- `checks.west-shell-boundary` establishes repository pattern: instantiate
  public shell, select packaged commands from `nativeBuildInputs`, run against
  fake mutable boundaries, and assert user-observable behavior.

## Fake boundary design

Define test-only fake nrfutil derivation inside `nix/flake/checks/nrfutil.nix`.
Python stdlib implementation is preferred for JSON and shell quoting; embed it
in Nix via `pkgs.writeTextFile` with executable destination `/bin/nrfutil` and
shebang `${pkgs.python3}/bin/python3`.

Runtime environment:

- `FAKE_NRFUTIL_STATE`: required temp state directory.
- `FAKE_NRFUTIL_SDK_PATH`: selected SDK root.
- `FAKE_NRFUTIL_REAL_WEST_BIN`: directory containing fake real `west`.
- Optional `FAKE_NRFUTIL_FAIL_ENV_CALL`: positive call number on which
  `toolchain env` fails.

State files:

- `sdk-ready`: SDK installed; fake list reports selected version and
  `FAKE_NRFUTIL_SDK_PATH`.
- `toolchain-ready`: toolchain env succeeds.
- `commands.log`: every argv, one JSON array per line.
- `env-count`: number of `toolchain env` calls.
- `installs.log`: mutating install argv only.

Required fake sdk-manager behavior:

1. `list --json --skip-overhead`: emit installed-version JSON only when
   `sdk-ready` exists; version comes from `NIX_NRF_NCS_VERSION`; otherwise emit
   empty stdout (matching fresh sdk-manager state).
2. `config show --json --skip-overhead`: emit a valid default install root
   derived from SDK path parent.
3. `toolchain env <selector> --as-script sh`: increment `env-count`; fail on
   configured call or when `toolchain-ready` absent; otherwise emit shell-safe
   exports that prepend fake-real-west bin and set markers
   `FAKE_TOOLCHAIN_ENV=1`, `PYTHONHOME=fake-toolchain-pythonhome`, and
   `GIT_EXEC_PATH=fake-toolchain-git`.
4. Combined `install <version>`: log mutation, create SDK `zephyr/`,
   `sdk-ready`, and `toolchain-ready`; no network.
5. Exact-bundle `sdk install` / `toolchain install` may be supported minimally
   if needed by selected scenarios; log and create corresponding readiness.
6. Unexpected argv: clear stderr and nonzero exit.

Fake real west logs JSON containing argv plus `ZEPHYR_BASE`,
`FAKE_TOOLCHAIN_ENV`, `PYTHONHOME`, `GIT_EXEC_PATH`, and `PATH`, then exits 0.

## Public shell instances

Construct through supplied `mkNrfShell`:

1. `readyShell`: backend nrfutil, `ncsVersion = "v3.3.0"`, fake nrfutil,
   `withMultilib = false`, caller name, `pkgs.hello`, `inputsFrom` fixture with
   `pkgs.ripgrep`, and extra hook marker.
2. `noAutoShell`: same selector/fake package, `autoBootstrap = false`,
   `withMultilib = false`.
3. `bundleShell`: exact bundle ID containing spaces and both quote kinds,
   fake package, `withMultilib = false`. NCS value may also contain spaces and
   quotes; fake derives version from exported wrapper environment.

Select shell-specific `nix-nrf` and wrapper `west` from each shell's
`nativeBuildInputs` by package name, matching established west-boundary style.
Also assert fake nrfutil package is included and repository default nrfutil is
not substituted.

## Required behavior and assertions

### Ready shell hook

- Source exact `shellHook` in subprocess with isolated ready HOME/state.
- Output names caller shell and nrfutil backend.
- Exports exact `$FAKE_NRFUTIL_SDK_PATH/zephyr` as `ZEPHYR_BASE`.
- Runs only read-only list/toolchain-env probes; `installs.log` absent/empty.
- Does not eval toolchain script into parent shell: `PYTHONHOME`,
  `GIT_EXEC_PATH`, and `FAKE_TOOLCHAIN_ENV` remain unset after sourcing.
- Extra hook marker executes.
- Caller `hello` and `inputsFrom` ripgrep membership evaluate true;
  `withMultilib = false` excludes multilib GCC.

### Ready scoped west wrapper

- Run exact packaged wrapper with representative args.
- Fake real west receives exact argv.
- Real west sees exact SDK-derived `ZEPHYR_BASE`.
- Real west sees toolchain markers, proving env is scoped inside wrapper child.
- First PATH entry reaching real west is project `openocd-master` bin; fake real
  west bin remains present so discovery works.
- Fake nrfutil log proves both bootstrap readiness and wrapper env calls use
  `--ncs-version v3.3.0 --as-script sh`.
- No install occurred for ready state.

### Lazy bootstrap

- Start `readyShell` from empty state with approval env
  `NIX_NRF_BOOTSTRAP_YES=1`.
- Wrapper invokes combined fake `install v3.3.0`, then reaches fake west.
- SDK/zephyr and readiness markers created under isolated temp root.
- Exactly expected install recorded; no real download/state.

### `autoBootstrap = false`

- Ready state still reaches fake west.
- Missing state exits nonzero, prints existing
  `automatic bootstrap is disabled (autoBootstrap = false)` and
  `Run: nix-nrf bootstrap` remediation.
- Missing-state path creates no SDK/state install and logs no mutation.

### Wrapper failures

- Configure fake env call 2 to fail: bootstrap readiness call 1 succeeds,
  wrapper's actual env load fails. Assert nonzero plus existing
  `toolchain env ... failed`, selected-toolchain context, and bootstrap
  remediation; fake west not invoked.
- Ready toolchain env with empty fake-real-west directory: assert existing
  `real west not found in the NCS toolchain env` and nonzero.

### Exact selector quoting

- Run bundle shell ready path.
- Fake nrfutil JSON argv log proves exact NCS version and exact bundle value
  survive as single argv elements—no quote artifacts or shell injection.
- Every toolchain-env call uses `--toolchain-bundle-id <exact-value>`, never
  `--ncs-version`.
- Fake west receives representative args unchanged.

Do not assert private derivation identity, helper-call counts beyond externally
needed first/second env failure setup, or copied production constants.

## Nix wiring

- Extend `nix/flake/checks/nrfutil.nix` args to `{ pkgs, nrfutil, mkNrfShell }`.
- Add returned key `nrfutil-shell-boundary`.
- Pass `mkNrfShell` from `nix/flake/per-system.nix`.
- Explicitly inherit key in `nix/flake/checks/default.nix`.
- Keep all temp state under check build directory; set isolated `HOME`.
- Check must not access host HOME, USB, network, or SDK.

## Verification

```sh
nix build .#checks.x86_64-linux.nrfutil-shell-boundary -L
nix flake check --all-systems --no-build -L
nix flake check -L
```

## Acceptance

- New check proves listed public shell behavior through real generated hook,
  dispatcher/bootstrap module, scoped wrapper, fake nrfutil, and fake west.
- Lazy bootstrap test is fake-only and network-free.
- Both selector modes preserve exact argv.
- Failure paths preserve existing remediation and exit nonzero.
- Existing checks pass; check count/docs match.
- No production changes unless escalated and approved after test exposes bug.

## Executor instructions

Implement handoff exactly. Stop and escalate if public shell cannot be tested
without production API invention, if observed behavior contradicts documented
contract, or if two materially different attempts fail. Do not weaken tests,
use real sdk-manager state, or expand scope. After verification inspect status,
diff, and recent log; stage intended files and commit concise conventional
message. Do not push, amend, open PR, or add attribution. Return changed files,
behavior, exact test results, commit hash/message, blockers, deviations, and
follow-up.
