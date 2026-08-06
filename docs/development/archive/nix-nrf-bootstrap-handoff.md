# `nix-nrf bootstrap` Phase Handoff

## Goal

Add explicit and lazy SDK/toolchain bootstrap for the `nrfutil` backend:

```text
nix-nrf bootstrap [--yes] [--check] [--print-sdk-path]
```

`west` must ensure configured NCS SDK source and selected toolchain exist before
loading Nordic's scoped toolchain environment. Shell entry remains
non-mutating. Normal CI never downloads SDK/toolchain bundles.

## Grounding and corrected assumptions

Installed package is nrfutil 8.2.0 with sdk-manager. Read-only live help and
JSON established:

- SDK + newest matching toolchain:
  `nrfutil sdk-manager install <version>`.
- SDK source only:
  `nrfutil sdk-manager sdk install <version>`.
- Exact toolchain:
  `nrfutil sdk-manager toolchain install --toolchain-bundle-id <id>`.
- Installed SDK state:
  `nrfutil sdk-manager list --json --skip-overhead`, with
  `versions[].version`, `sdkStatus`, `dirNames[]`, `toolchainStatus`, and
  `toolchainPath`.
- Selected toolchain readiness:
  `nrfutil sdk-manager toolchain env --ncs-version <version> --as-script sh`
  or exact `--toolchain-bundle-id <id>`.
- Configured root:
  `nrfutil sdk-manager config show --json --skip-overhead`, field
  `default.install_dir`; null means Linux default `$HOME/ncs`.
- sdk-manager has **no `--yes` option**. `nix-nrf bootstrap --yes` is this
  repository's confirmation bypass and must never be forwarded to nrfutil.
- Re-running install skips existing components, but the release selector may
  install a newer compatible patched toolchain when Nordic publishes one.
  Exact `toolchainBundleId` remains deterministic.

Official reference:

- Nordic “Installing SDKs and toolchains”:
  <https://docs.nordicsemi.com/bundle/nrfutil/page/nrfutil-sdk-manager/guides/sdk_manager_installing.html>
- Nordic “Managing SDKs and toolchains directly”:
  <https://docs.nordicsemi.com/bundle/nrfutil/page/nrfutil-sdk-manager/guides/sdk_manager_managing_directly.html>
- Nordic scripting output:
  <https://docs.nordicsemi.com/bundle/nrfutil/page/guides/scripting.html>
- Installed NCS docs:
  `/home/thomas/ncs/v3.3.0/nrf/doc/nrf/installation/install_ncs.rst`.

Current code:

- `nix/nix-nrf.nix`: fixed `versions`/`probes` dispatcher.
- `nix/mk-nrf-shell.nix`: required `ncsVersion`, optional
  `toolchainBundleId`, scoped `west` wrapper, fragile shell-hook SDK-path
  derivation.
- `docs/development/clean-bootstrap-versioning-plan.md`: accepted lazy
  bootstrap direction, but still uses old standalone `nrf-bootstrap` naming
  and incorrectly implies sdk-manager itself accepts `--yes`.

## Exact implementation

### Bootstrap command module

Add `bin/nix-nrf-bootstrap`, a Python command module, and
`nix/nix-nrf-bootstrap.nix`, an internal derivation installed at:

```text
$out/libexec/nix-nrf/bootstrap
```

Do not add standalone `nrf-bootstrap` or another public package output.

`nix/nix-nrf-bootstrap.nix` takes:

```nix
{
  pkgs,
  nrfutilPackage,
  ncsVersion ? null,
  toolchainBundleId ? null,
}:
```

Patch Python shebang and wrap command with exact selected nrfutil path in
`NIX_NRF_NRFUTIL`. When non-null, set configured defaults through
`NIX_NRF_NCS_VERSION` and `NIX_NRF_TOOLCHAIN_BUNDLE_ID`. Unset
`PYTHONHOME`/`PYTHONPATH` as probe module does.

Python CLI options:

- `--ncs-version VERSION`: defaults to `NIX_NRF_NCS_VERSION`; required at
  runtime when package has no configured default.
- `--toolchain-bundle-id ID`: defaults to
  `NIX_NRF_TOOLCHAIN_BUNDLE_ID`; omission selects newest compatible patched
  toolchain for NCS release.
- `--yes`: approve required downloads without prompt.
- `--check`: inspect only; never install or mutate.
- `--print-sdk-path`: on success print only absolute SDK root to stdout.
- `--quiet`: suppress normal status messages; errors remain visible.
- `-h`/`--help`: `argparse` help with `prog="nix-nrf bootstrap"`.

Internal environment:

- `NIX_NRF_NRFUTIL` is required and points to exact store executable.
- `NIX_NRF_BOOTSTRAP_YES=1` is equivalent to `--yes`. No other value grants
  approval.

All status, prompt, and nrfutil progress goes to stderr. stdout stays empty
unless `--print-sdk-path` succeeds; then it contains one absolute path plus
newline. This allows safe shell command substitution.

### State detection

Implement small testable functions; do not put all logic in `main`.

1. Run exact nrfutil executable:
   `sdk-manager list --json --skip-overhead`.
2. Parse either one JSON object or JSON-lines output and locate object with
   `versions`.
3. Match exact `version == ncsVersion` and `sdkStatus == "installed"`.
4. Select first `dirNames[]` path that exists and contains `zephyr/`. Treat
   missing/stale paths as SDK missing.
5. Determine toolchain readiness by running `sdk-manager toolchain env` with
   exact configured selector and `--as-script sh`. Exit 0 means selected
   toolchain exists; nonzero means missing/unavailable.
6. Determine display destination from
   `sdk-manager config show --json --skip-overhead` field
   `default.install_dir`; when null on supported Linux, use `$HOME/ncs`.

Malformed JSON, missing expected shapes, or failed read-only commands produce a
clear `nix-nrf bootstrap:` error and exit 1. Do not silently assume missing and
start a download when state cannot be read.

### Install decisions

If SDK and selected toolchain are ready: no install command, exit 0.

If `--check` and either component is missing: report missing components unless
quiet, never prompt/install, exit 1. If SDK path exists, still emit it when
`--print-sdk-path` was requested, while retaining exit 1 because full selection
is not ready.

Before mutation print selected NCS version, selector, missing components,
destination, and large-download warning.

Approval:

- approve when `--yes` or `NIX_NRF_BOOTSTRAP_YES=1`;
- otherwise, if stdin and stderr are TTYs, prompt on stderr and accept only
  case-insensitive `y`/`yes`;
- otherwise print exact remediation
  `nix-nrf bootstrap --yes` or `NIX_NRF_BOOTSTRAP_YES=1 west ...`, then exit 2;
- decline exits 2 without mutation.

Install matrix:

- No exact bundle: when either component is missing, run exactly
  `nrfutil sdk-manager install <ncsVersion>`.
- Exact bundle: if SDK missing, run exactly
  `nrfutil sdk-manager sdk install <ncsVersion>`; if toolchain missing, run
  exactly `nrfutil sdk-manager toolchain install --toolchain-bundle-id <id>`.
  Run only missing actions.

Do not pass repository `--yes`, `--check`, `--quiet`, or `--print-sdk-path` to
nrfutil. Route child stdout to helper stderr so command-substitution stdout
remains machine-readable. Preserve child stderr. Any child nonzero exits 1.

After actions, rerun state detection. Success requires SDK path and selected
toolchain ready. Otherwise report incomplete installation and exit 1.

Exit contract:

- 0: configured selection ready, including successful install.
- 1: missing during `--check`, unreadable state, command failure, or incomplete
  post-install state.
- 2: CLI usage error, noninteractive approval required, or user declined.

### Dispatcher

Extend `nix/nix-nrf.nix` arguments:

```nix
ncsVersion ? null,
toolchainBundleId ? null,
```

Import bootstrap module internally. Add:

- `nix-nrf bootstrap ...` delegation;
- `nix-nrf help bootstrap` delegation;
- top-level help entry.

Base `packages.nix-nrf` passes null defaults, so this works explicitly:

```bash
nix run .# -- bootstrap --ncs-version v3.3.0 --check
```

`mkNrfShell` passes its selected values, so inside shell this works:

```bash
nix-nrf bootstrap
```

### `mkNrfShell` and west lifecycle

Add public argument:

```nix
autoBootstrap ? true
```

Pass `ncsVersion` and `toolchainBundleId` into shell-specific `nix-nrf`.

Before loading toolchain environment, `west` performs:

- `autoBootstrap = true`: invoke exact shell-specific
  `nix-nrf bootstrap --print-sdk-path`. This checks every invocation, installs
  only if missing and approved, and returns SDK root.
- `autoBootstrap = false`: invoke
  `nix-nrf bootstrap --check --quiet --print-sdk-path`; on nonzero, print that
  automatic bootstrap is disabled and exact remediation `nix-nrf bootstrap`,
  then exit without mutation.

On success export `ZEPHYR_BASE="$sdk_path/zephyr"` inside west process, then
load existing scoped toolchain env and execute real west. Reject empty/non-dir
path before running west.

Shell hook remains non-mutating. Replace fixed-parent/fixed-`$HOME/ncs`
discovery with exact shell-specific:

```text
nix-nrf bootstrap --check --quiet --print-sdk-path
```

Capture output even when overall readiness exits 1, because helper may return
an installed SDK path while toolchain is missing. Export `ZEPHYR_BASE` only
when returned path contains `zephyr/`. Keep concise missing-path guidance.

Remove old duplicated install-remediation strings after west uses helper.

### Tests

Add `tests/unit/test_nix_nrf_bootstrap.py` using Python stdlib `unittest` and a
temporary fake `nrfutil` executable/state directory. Exercise command as a
subprocess through public-style args and environment; no network, real SDK, or
real nrfutil state.

Required cases:

1. Ready selection: exits 0, prints SDK path only when requested, performs no
   install.
2. Missing default SDK/toolchain + `--check`: exits 1, performs no mutation.
3. Missing default selection non-TTY without approval: exits 2, exact approval
   guidance, no install.
4. `--yes` default selector: invokes only combined install, rechecks, exits 0.
5. `NIX_NRF_BOOTSTRAP_YES=1`: same approval behavior.
6. Exact selector missing both: invokes SDK-only then exact-toolchain commands;
   never combined install.
7. Exact selector with only one component missing: invokes only missing action.
8. Malformed list/config JSON or failed state command: exits 1, never installs.
9. Failed install or incomplete post-install state: exits 1.
10. Missing configured/default NCS version: argparse-style exit 2.

Wire as `checks.bootstrap-tests` in `flake.nix` using sandboxed Python stdlib.
Test source file is `.py`, so Black formats it.

Add evaluation check coverage that omitted/explicit `autoBootstrap` values
evaluate without changing existing backend selector guarantees.

### CI and docs

Update `.github/workflows/ci.yml`:

- normal flake check runs fake bootstrap tests;
- smoke `nix run .#nix-nrf -- bootstrap --help` only;
- devshell verifies `nix-nrf bootstrap --help` but never invokes bootstrap
  without help/check against missing state;
- no normal PR job downloads SDK/toolchain bundles.

Update:

- `README.md` with explicit, lazy, manual mode, confirmation/env override,
  exact-bundle behavior, and shell re-entry note;
- `templates/default/flake.nix` with commented `autoBootstrap` option;
- `docs/development/clean-bootstrap-versioning-plan.md` to mark phase done,
  use unified `nix-nrf bootstrap`, distinguish repository `--yes` from Nordic
  arguments, record JSON fields/evidence, and remove disproven assumptions;
- `docs/development/nrfutil-backend-status.md`, `goals.md`, and relevant live
  command inventories.

Preserve completed historical handoffs as historical records.

## Scope

In scope:

- Internal bootstrap command and fake-boundary tests.
- Explicit/manual bootstrap.
- Lazy west integration and manual opt-out.
- SDK path discovery through sdk-manager JSON.
- Docs/CI/evaluation checks.

Out of scope:

- Real clean-home multi-gigabyte download/build; next phase.
- Caching SDK/toolchains in CI.
- Custom `ncsInstallDir`.
- Parallel-bootstrap locking; document as follow-up if sdk-manager does not
  serialize installs itself.
- Nix-native `sdk-nrf` backend.
- Flashing/hardware operations.
- `nix-nrf doctor`.

## Verification

Run:

```bash
nix fmt
nix flake check -L
nix build -L .#nix-nrf .#nrfutil
nix run .#nix-nrf -- bootstrap --help
nix run .#nix-nrf -- bootstrap --ncs-version v3.3.0 --check --print-sdk-path
nix develop --ignore-environment --command sh -ceu 'command -v nix-nrf; nix-nrf bootstrap --help >/dev/null; command -v west'
```

The real `--check` command above is read-only and should pass on current host's
already installed v3.3.0. It must never add `--yes` or install. All missing and
install paths are proven only with fake unit boundary during this phase.

Also verify evaluation for:

- `autoBootstrap = true` and omitted default;
- `autoBootstrap = false`;
- exact `toolchainBundleId` plus either bootstrap mode.

Acceptance:

- Shell entry never mutates.
- Missing `west` dependency triggers confirmation-aware lazy bootstrap when
  enabled and exact manual remediation when disabled.
- stdout path contract remains machine-readable.
- Exact bundle never downloads newest compatible toolchain accidentally.
- Fake boundary proves all lifecycle branches without network.
- Full non-hardware gate passes.

## Commit and recap

Inspect status, diff, and recent log. Stage only phase files. Commit passing
implementation separately from this planning commit with a concise Conventional
Commit such as:

```text
feat(cli): add lazy SDK bootstrap
```

Do not push, merge, amend, open a PR, run downloads/flashing, or add
attribution. Return changed files, behavior, all verification results, commit
hash/message, blockers, deviations, and explicit statement that no real SDK
download occurred.
