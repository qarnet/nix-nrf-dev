# Repository Architecture

Current maintainer reference for the nix-nrf-dev repository after the
repository refactor. Backend-specific proof and behavior details live in
`docs/development/west-backend-status.md` and
`docs/development/nrfutil-backend-status.md`; this document describes
ownership and construction only.

## 1. Public entry points

- Root `flake.nix` — thin flake: inputs, `eachSystem supportedSystems`
  (`supportedSystems = [ "x86_64-linux" ]`) delegating to
  `nix/flake/per-system.nix`, plus the non-system `nixosModules.udevRules`
  output.
- `nix/flake/per-system.nix` — per-system construction: configured Nixpkgs
  (allowUnfree + SEGGER acceptance), components, formatter/pre-commit,
  checks, dev shells, and the `apps.init-project` output.
- `lib.<system>.mkNrfShell` — public dev-shell factory (dispatcher
  `nix/backends/default.nix`), exported via `nix/flake/per-system.nix`
  `lib` output.
- `packages.<system>.nix-nrf` — standalone CLI facade (`nix run .# -- ...`).
- `apps.<system>.init-project` — dynamic project initializer app
  (`nix run .#init-project -- ./my-project`), backed by the
  `nix/init-project/` module. Generates a consumer flake pinned to a
  concrete NCS release (never `latest`); see `docs/backends.md`.
- `nixosModules.udevRules` — convenience module that sets only
  `services.udev.packages = [ self.packages.<system>.udev-rules ]`; it never
  creates the `plugdev` group or modifies users. Direct
  `services.udev.packages` configuration is the primary documented path
  (`docs/hardware.md`).

## 2. Construction flow

- `nix/flake/components.nix` is the single per-system composition root: it
  builds OpenOCD (wrapped/unwrapped), udev rules, the composed nrfutil, the
  standalone `nix-nrf` dispatcher, west metadata/builders, the public
  `mkNrfShell`, and the `initProject` package.
- `nix/init-project/default.nix` packages the initializer script with the
  exact packaged nrfutil store executable, the west metadata key list, and
  the skeleton under `$out/share/nix-nrf/init-project`; `per-system.nix`
  publishes only `apps.<system>.init-project` (no `packages.init-project`).
- `nix/flake/dev-shells.nix` composes `mkNrfShell` into the `default` and
  `clean-env-test` shells.
- `nix/flake/checks/*.nix` build the check derivations; `checks/default.nix`
  composes them (duplicate keys are a Nix attrset construction error).
- Plain Nix imports throughout; no flake-parts or other framework.

## 3. Backend ownership

- `nix/backends/default.nix` — public `mkNrfShell` dispatcher: argument
  signature, supported-backend list, required `ncsVersion`, west release
  validation, west-only rejection of `toolchainBundleId` / non-default
  `nrfutilPackage`, and dispatch. It constructs nothing.
- `nix/backends/nrfutil/` — default backend: `default.nix` (entry point over
  internal deps incl. the shared nix-nrf constructor), `shell.nix` (scoped
  toolchain-env shell, lazy bootstrap west wrapper, non-mutating hook),
  `bootstrap.nix` (SDK/toolchain bootstrap command module).
- `nix/backends/west/` — experimental hybrid backend: `default.nix`
  (metadata-selected Python, exact Zephyr SDK, west bootstrap/versions
  command modules, backend-aware nix-nrf, doctor label), `shell.nix` (public
  west dev shell), `bootstrap.nix`, `versions.nix`, `versions-command.nix`,
  `zephyr-sdk.nix`.
- No backend imports implementation details from the other backend; shared
  code receives backend commands/configuration as explicit arguments.

## 4. Shared ownership

- `nix/commands/` — `default.nix` (backend-aware `nix-nrf` dispatcher),
  `doctor.nix`, `probes.nix`. Backend constructors inject exact command
  module store paths (`versionsCommand`, `bootstrapCommand`); the doctor and
  the dispatcher share one identical bootstrap store path per shell.
- `nix/init-project/` — the public initializer: `default.nix` (packaging and
  exact-store wrapper wiring), `skeleton/flake.nix.in` (render template with
  `@BACKEND@`/`@NCS_VERSION@` placeholders replaced by `json.dumps` string
  literals) and `skeleton/.envrc` (`use flake`). The script owns CLI/version
  resolution, sdk-manager schema validation, semantic-max selection, and the
  collision/symlink-safe filesystem algorithm; it never executes hooks or
  generated commands.
- `nix/hardware/` — `openocd.nix` (from-source OpenOCD build) and
  `udev-rules.nix` (relocation package for the pinned 60-openocd.rules).
- `nix/lib/mk-python-command.nix` — narrow packaging helper for the internal
  Python command modules: install to `$out/libexec/nix-nrf/<destination>`,
  patch shebang, single ordered `wrapProgram`. Callers own every wrapper
  argument.
- Default nrfutil bootstrap module lives at
  `nix/backends/nrfutil/bootstrap.nix`; `nix/commands/default.nix` imports
  it unless a west `bootstrapCommand` is injected.

## 4a. Release ownership

- `release.json` (repo root) — the canonical nix-nrf-dev project version
  manifest: strict stable SemVer (`MAJOR.MINOR.PATCH`, no leading `v`, no
  prerelease/build metadata), independent from NCS versions. It must be a
  JSON object with exactly the `version` key so no second release authority
  can appear silently.
- `nix/release.nix` — pure loader validating the manifest; its `version` is
  embedded into every `nix-nrf` dispatcher instance (standalone, nrfutil
  shell, west shell) and reported via `-V`/`--version` (also
  `passthru.version` on the `nix-nrf` derivation). No version literal is
  duplicated in Nix source.
- `scripts/release.py` + `tests/unit/test_release.py` — the fail-closed
  release/changelog consistency utility (check/version/notes commands,
  stdlib only) and its contract regression suite, covering every negative
  manifest/changelog element. Wired as `checks.<system>.release-consistency`
  (via `nix/flake/checks/release.nix`) and as the named direct CI gate;
  `nix/flake/checks/core.nix` proves the packaged `nix-nrf` reports exactly
  the manifest version.
- `.github/workflows/release.yml` — the trusted-main reusable release
  workflow (`workflow_call` only; no event triggers): `prepare` (read-only)
  validates and stages the notes artifact, `publish` (contents: write, no
  checkout, no project code) creates the `v<version>` tag/Release at the
  exact prepared SHA, fails closed on a conflicting/annotated tag, finishes
  leftover drafts, and no-ops on an already published version. Reachable
  only from the gated `release` caller job in `.github/workflows/ci.yml`
  (trusted push to main after the `check` job); PRs can never publish.

## 5. Script layout under `bin/`

- `bin/backends/nrfutil/nix-nrf-bootstrap`,
  `bin/backends/west/nix-nrf-west-bootstrap`,
  `bin/backends/west/nix-nrf-west-versions` — backend command scripts.
- `bin/commands/nix-nrf-doctor`, `bin/commands/nix-nrf-probes` — shared
  command scripts.
- `bin/commands/nix-nrf-init-project` — the standalone public initializer
  script, packaged by `nix/init-project/default.nix` (the only script
  installed as a public `$out/bin` command).
- Script basenames are stable; each shared/backend script is packaged by
  exactly one Nix command module and installed **only** under
  `$out/libexec/nix-nrf/` (no standalone `$out/bin` commands) so public
  invocation stays exclusively through the `nix-nrf` facade.

## 6. Tests

- Flake checks split by domain: `nix/flake/checks/` — `backend-selector.nix`
  (evaluation gate), `nrfutil.nix` (bootstrap tests + quoting + shell
  boundary), `west.nix`
  (bootstrap/versions/metadata/quoting/shell-boundary + pure
  `lib.debug.runTests` bidirectional declared-target/toolchain-archive
  consistency per release), `core.nix`
  (doctor/help/probes/udev wiring, fake-OpenOCD flash-recipe semantic tests,
  + public NixOS module evaluation), `udev-module.nix` (isolated
  `lib.evalModules` gate proving `nixosModules.udevRules` exposes exactly the
  `services.udev.packages` option AND observable config surfaces — an extra
  declared option or smuggled config path widens either asserted tree and
  fails — that a synthetic undeclared config definition is rejected by the
  enabled `_module.check`, and that the module contributes exactly the
  expected package with an empty list when not imported), `udev-vm.nix`
  (booted NixOS VM clean-room gate: direct `services.udev.packages`
  activation of the packaged rule under real systemd-udevd with explicit
  `plugdev`, proving activation and an otherwise clean system — no project
  tools or units — plus synthetic positive/negative CMSIS-DAP rule semantics
  replayed via umockdev against real `udevadm test`, with no real daemon
  hotplug or hardware), and `init-project.nix`
  (deterministic fake-boundary suite run twice: raw source standalone and
  the packaged public binary constructed with a fake nrfutil search package
  as `nrfutilPackage` and the real west metadata).
  `nix/flake/checks/default.nix`
  composes the exact check set.
- Unit tests in `tests/unit/` run fake-boundary subprocess suites (sandboxed
  stdlib) wired into the corresponding checks; `tests/fixtures/`
  `west-workspace.py` is the shared fake workspace creator covered by
  `tests/unit/test_west_workspace_fixture.py` inside `checks.west-bootstrap-tests`,
  and `nrfutil-search.py` is the deterministic sdk-manager-search fake behind
  `checks.init-project-tests` (also reused by the raw-source unit run).
- `tests/tcl/test_flash_recipes.tcl` sources the real `tcl/` flash recipes
  under tclsh with fake OpenOCD commands and asserts command order, argument
  preservation (incl. paths with spaces), conditionals, and UICR safety
  branches (`checks.flash-recipe-tests`); real-OpenOCD CI steps only gate
  source/syntax compatibility.
- Manual harnesses require explicit approval and real resources:
  `tests/clean-room/run.sh` (real SDK bootstrap + blinky build),
  `tests/west-backend/run.sh` (real west workspace), `tests/hardware/run.sh`
  (self-hosted hardware runner). Dry runs are gated by
  `NIX_NRF_CLEAN_DRY_RUN=1` / `NIX_NRF_WEST_DRY_RUN=1`.
- Clean-room telemetry ownership: `tests/clean-room/run.sh` measures exact
  free KiB, mutable-path sizes, bootstrap/build elapsed seconds (inner
  lifecycle shells write epoch-second integers under
  `$CLEAN_HOME/.nix-nrf-clean-metrics/`), and the separately realized
  `clean-env-test` Nix closure. It writes at most one Markdown report, only
  via its telemetry functions, to the exact `NIX_NRF_CLEAN_TELEMETRY_FILE`
  path (absolute, existing parent, no overwrite, outside the clean home); the
  workflow summary retains the report while the mutable home remains cleaned.
- Hosted workflow ownership: `.github/workflows/latest-ncs-init.yml`
  ("Latest NCS initializer") is the only normal automated run that queries
  Nordic live. Its single `resolve` step runs the initializer with
  `--ncs-version latest` and an independent `timeout 90 nix run .#nrfutil --
  sdk-manager search --json --skip-overhead`, each with at most three bounded
  retries, classifies **only** Nordic sdk-manager transport/index outages as
  retryable/inconclusive (never generic Nix/GitHub failures, malformed data,
  no-stable-release, wrong selection, or generated-output mismatch), and
  recomputes the expected release with a standalone Python stdlib parser
  (never the initializer's parser). Validation steps run only on
  `result=pass`: generated-flake evaluation against the current checkout,
  no-mutation checks (no `$HOME/ncs`, no `zephyr` directory) before and after
  shell entry, the exact read-only `nix-nrf bootstrap --check` outcome
  (exit 1, "not ready; missing:", "no changes made (--check)"), and an nrfutil
  log scan rejecting any install invocation. HOME/NRFUTIL_HOME are isolated
  under a unique runner-temp path per run/attempt; the exact validation root
  is removed in the final `if: always()` step and no fixed shared path is ever
  deleted. An `if: always()` summary step reports PASS (resolved release),
  INCONCLUSIVE (bounded Nordic outage, successful exit), or FAILED (failing
  phase, from a phase-marker file written by each validation step).

## 7. Adding/changing

- New west metadata release: add an entry to
  `nix/backends/west/versions.nix` (version, Python, SDK assets, hashes,
  requirements, constraints); no builder or command code changes, and the
  initializer's west `latest` selection picks it up automatically.
- New backend: add `nix/backends/<name>/` with a constructor, register it in
  the dispatcher's supported list, and keep the no-cross-import rule.
- New shared command: add `bin/commands/<name>` + a module using
  `mk-python-command.nix`, and a dispatch case in `nix/commands/default.nix`.
- New check without growing root flake: add it to the appropriate module in
  `nix/flake/checks/` and name it in `checks/default.nix`.

## 8. Invariants

- `nrfutil` is the default backend; omitted and explicit `backend =
  "nrfutil"` produce identical derivations.
- `ncsVersion` is required for both backends (`mkNrfShell`); the initializer
  resolves `latest` to one concrete release, and generated projects never
  contain `ncsVersion = "latest"`.
- Shell entry stays non-mutating (read-only `--check` bootstrap path);
  mutation happens only through an explicit `nix-nrf bootstrap` invocation or
  the scoped `west` wrapper, and is approval-gated (interactive confirmation
  unless `NIX_NRF_BOOTSTRAP_YES=1` / `--yes`) when state is missing.
- No backend silently falls back: unsupported values fail Nix evaluation
  naming the supported list, and a failed initializer latest lookup aborts
  generation instead of substituting a hard-coded version.
- The initializer never overwrites (`--force` is rejected), never follows or
  overwrites a generated-target symlink, uses renameat2 RENAME_NOREPLACE for
  new destinations, and runs no hooks or generated commands.
- Normal checks never perform mutable NCS workspace `west update`, pip
  workspace setup, sdk-manager bundle installs, hardware access, or any live
  Nordic query (fake boundaries or dry runs only); fixed Nix fetch/build
  inputs — such as the west backend's exact Zephyr SDK package assets — may
  still be realized by normal builds and checks. Live Nordic index queries
  exist only in the scheduled/manual `latest-ncs-init.yml` workflow with
  explicit inconclusive-outage semantics; normal `ci.yml` remains
  deterministic and tests the explicit v3.3.0 baseline.
- Hardware and real clean-room runs require explicit user approval and are
  never part of the default gate.
