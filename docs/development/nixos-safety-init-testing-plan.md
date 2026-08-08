# NixOS Safety, Project Initialization, and Test Expansion Plan

Status: accepted implementation plan. Phase 0 (doctor CMSIS-DAP transport
preflight, PR #4/#5) is merged. Phase 1 (upstream udev provenance and public
NixOS API) is accepted and committed at `f69edeb`. Phase 2 (udev package,
`evalModules`, and full-system evaluation) is accepted and committed at
`9175995`. Phase 3 (NixOS VM clean-room udev activation) is accepted and
committed on this branch. Phase 4 (nrfutil versions command coverage) is
accepted and committed on this branch. Phase 5 (dynamic `init-project` app)
is accepted and committed on this branch. Phase 6 (nightly latest-NCS
initializer workflow) is accepted and committed on this branch (per
`docs/development/archive/latest-ncs-init-workflow-handoff.md`). Phase 7
(west metadata `lib.debug.runTests` gate) is accepted and committed on this
branch (per
`docs/development/archive/west-target-toolchain-consistency-handoff.md`).
Phase 8 (clean-room resource telemetry) is accepted and committed on this
branch as instrumentation only (per
`docs/development/archive/clean-room-telemetry-handoff.md`). No real
measurements are claimed by this phase; the real retained measurement run
remains separately approved and pending, and the 25 GiB free-space guard is
unchanged. Phase 9 (umockdev udev semantics gate) is accepted and committed
on this branch (per
`docs/development/archive/udev-umockdev-semantics-handoff.md`).

Branch: `feat/nixos-safety-and-init`, rebased onto `main` at `a3fedcb`
(after the CMSIS-DAP transport and hardware-preflight work from PR #4/#5
merged).

This plan records the agreed direction for:

- transparent and least-intrusive NixOS udev integration;
- explicit upstream OpenOCD rule provenance and the required `plugdev` setup;
- a parameterized `nix run` project initializer without a stale NCS version;
- deterministic and live nrfutil version-discovery coverage;
- meaningful `lib.debug.runTests`, `lib.evalModules`, full NixOS evaluation,
  and NixOS VM tests;
- nightly latest-NCS project-generation validation;
- measured clean-room resource reporting; and
- a bounded umockdev feasibility spike.

## 1. Decisions and invariants

### 1.1 OpenOCD source ownership

- Keep `nix/hardware/openocd.nix` on the current pinned `pkgs.fetchgit`
  design. Do not add an OpenOCD Git submodule.
- Keep `fetchSubmodules = true`; OpenOCD requires its own jimtcl and
  libjaylink submodules.
- `packages.<system>.udev-rules` remains a thin relocation package built from
  the pinned OpenOCD output. It must contain the exact upstream
  `contrib/60-openocd.rules`, not a hand-maintained copy.
- Documentation must name the upstream file and pinned OpenOCD revision.
- Existing byte-identity coverage remains load-bearing.

Current source pin at plan creation:

```text
https://git.code.sf.net/p/openocd/code
da3920b0a52dc2d394afb222c688dac7e57acc1b
```

### 1.2 Udev module boundary

- Remove `nixosModules.default`.
- Publish only `nixosModules.udevRules`.
- Do not keep a compatibility alias unless user reverses this explicit
  decision before implementation.
- Module stays rules-only. It may set only `services.udev.packages`.
- Module must not create groups, modify users, install CLI tools, add systemd
  services, or add shell hooks.
- Direct `services.udev.packages` configuration is primary and most
  transparent NixOS installation path. Named module is convenience path.

### 1.3 `plugdev` is explicit host policy

Upstream `60-openocd.rules` assigns:

```udev
MODE="660", GROUP="plugdev", TAG+="uaccess"
```

NixOS does not guarantee that `plugdev` exists. Current workstation does not
have it. With systemd-udevd's early name resolution, missing `plugdev` can
cause the upstream rule lines to be rejected.

Every NixOS installation/remediation example must therefore show both:

```nix
users.groups.plugdev = {};
users.users.<username>.extraGroups = ["plugdev"];
```

and either direct package configuration or the named module import.

Group creation remains user-owned host policy, not module behavior. Docs must
also require logout/login or reboot after adding group membership, followed by
probe replug and `nix-nrf doctor`.

### 1.4 Workstation migration is deferred

- Do not alter `/home/thomas-workstation/nixos-config-flake` during repository
  implementation phases.
- Do not remove current `99-local.rules` entries before an explicit,
  separately approved workstation migration.
- Current generic upstream `*CMSIS-DAP*` match should cover XIAO and Raspberry
  Pi Debug Probe USB/tty/hidraw nodes once `plugdev` exists.
- Current manual catalog also contains entries absent upstream, including
  older or development-era devices. No claim is made that those remain
  necessary; no entries are removed without observed need and verification.
- Safe later migration: add upstream package + explicit `plugdev` while
  retaining manual rules, rebuild, re-login/reboot, replug, verify, run doctor
  and hardware workflow, then consider deduplication separately.

### 1.5 Project initialization

- Replace static template onboarding with `nix run ...#init-project`.
- Standard `nix flake init -t` is not parameterized and cannot perform
  Jinja-like replacement. Do not pretend otherwise.
- Initial implementation uses a small Python stdlib renderer, not Jinja,
  Cookiecutter, Copier, or runtime template hooks.
- Initializer accepts explicit CLI inputs and writes a concrete NCS version.
  Generated projects never contain `ncsVersion = "latest"`.
- No silent fallback from failed latest lookup to a hard-coded version.
- Exact version remains an offline generation path.
- Generated files are collision-checked before any write; no `--force` in
  initial implementation.

Target public UX:

```sh
nix run github:qarnet/nix-nrf-dev#init-project -- ./my-project
nix run github:qarnet/nix-nrf-dev#init-project -- \
  ./my-project --backend nrfutil --ncs-version latest
nix run github:qarnet/nix-nrf-dev#init-project -- \
  ./my-project --backend nrfutil --ncs-version v3.3.0
nix run github:qarnet/nix-nrf-dev#init-project -- \
  ./my-project --backend west --ncs-version v3.3.0
```

Default directory may be `.`, default backend is `nrfutil`, and default NCS
selection is latest stable for nrfutil unless user supplies an exact version.
Interactive prompting is optional follow-up, not required for first release.

### 1.6 Version-support claims

- Remove stale static `v3.3.0` from generated-user onboarding.
- Keep version-specific values that are truthful support/test boundaries:
  west metadata, dogfood shells, hardware harnesses, clean-room tests, package
  names, and release-specific fixtures.
- nrfutil initializer may select latest stable release advertised as remotely
  installable by Nordic sdk-manager.
- west initializer may select only releases present in
  `nix/backends/west/versions.nix`; it must never select Nordic global latest
  when local west metadata lacks that release.
- Docs distinguish "latest advertised through nrfutil" from "hardware-tested
  repository baseline" and "west-supported metadata releases".

### 1.7 Normal checks remain deterministic

- Normal `nix flake check` performs no live Nordic network query, SDK/toolchain
  installation, hardware access, mutable west update, or firmware flash.
- Live Nordic index checks run only in scheduled/manual workflow with explicit
  inconclusive-network semantics.
- NixOS VM udev tests stay offline and small. They are not SDK clean-room
  tests.
- Real hardware and full SDK bootstrap remain explicit manual workflows.

## 2. Scope

### In scope

- Complete and publish current doctor hardware-preflight addition in PR #4.
- Rename NixOS module and update all live references/remediation.
- Document upstream rule provenance, direct-package installation, and
  mandatory `plugdev` setup.
- Strengthen udev package/module/evaluation/VM proof.
- Add deterministic nrfutil versions delegation and real forced-offline
  failure checks.
- Add optional live Nordic index workflow.
- Replace static project template with parameterized initializer app.
- Add nightly latest-stable generation/evaluation/dev-shell validation.
- Add one meaningful `lib.debug.runTests` metadata consistency gate.
- Add clean-room size/time/free-space evidence.
- Run bounded umockdev feasibility spike.

### Out of scope

- OpenOCD Git submodule or vendored upstream source.
- Editing upstream `60-openocd.rules` in place.
- Automatically creating `plugdev` or modifying users from
  `nixosModules.udevRules`.
- Workstation NixOS rebuild, udev reload, udev trigger, group mutation, or
  manual-rule cleanup during repository phases.
- Automatic latest SDK/toolchain download in hosted nightly CI.
- Updating west backend to a newer NCS release without its own source/hash and
  build proof.
- Full CMSIS-DAP/SWD software emulator.
- Linux USB gadget implementation unless umockdev proves insufficient and a
  later decision explicitly approves that scope.

## 3. Phase 0 — finish current doctor preflight PR

### Goal

Land real-hardware doctor preflight before architectural work branches from
updated `main`.

### Existing changes on `fix/doctor-cmsis-dap-transports`

- `tests/hardware/preflight_xiao.py`
- `tests/unit/test_preflight_xiao.py`
- `tests/hardware/run.sh`
- `nix/flake/checks/core.nix`
- `nix/flake/checks/default.nix`
- `tests/hardware/README.md`
- `docs/hardware.md`

### Acceptance behavior

Before any OpenOCD probe session, build, flash, or recovery path, manual
hardware workflow finds XIAO serial `8EE9B3FF` in `nix-nrf doctor --json` and
requires explicit CMSIS-DAP v2 bulk USB access (`access_method = "usb"`,
`fallback = false`, accessible USB node). Hosted CI tests parser contract with
canned JSON; manual hardware runner proves physical boundary.

### Verification

```sh
python3 tests/unit/test_preflight_xiao.py
python3 tests/unit/test_nix_nrf_doctor.py
bash -n tests/hardware/run.sh
nix build -L .#checks.x86_64-linux.preflight-xiao-tests
nix flake check --all-systems --no-build -L
nix flake check -L
git diff --check
```

After commit/push and green PR CI, manually dispatch hardware workflow. Do not
merge automatically.

## 4. Phase 1 — upstream udev provenance and public NixOS API

### Goal

Make global/root-level system effect explicit, narrow, reproducible, and
accurately documented.

### Files

- `flake.nix`
- `nix/hardware/udev-rules.nix`
- `nix/flake/per-system.nix`
- `bin/commands/nix-nrf-doctor`
- `tests/unit/test_nix_nrf_doctor.py`
- `tests/unit/test_preflight_xiao.py`
- `README.md`
- `docs/hardware.md`
- `docs/development/architecture.md`
- `docs/development/nrfutil-backend-status.md`

### Changes

1. Publish only `nixosModules.udevRules`; remove `nixosModules.default`.
2. Keep module body limited to `services.udev.packages`.
3. Make direct package configuration primary documentation:

   ```nix
   services.udev.packages = [
     nix-nrf-dev.packages.${pkgs.stdenv.hostPlatform.system}.udev-rules
   ];
   ```

4. Show `users.groups.plugdev` and explicit user membership in both direct and
   module examples.
5. Explain logout/login or reboot, rebuild, probe replug, then doctor.
6. State exact upstream source and pin. Explain generic `*CMSIS-DAP*` coverage
   and that upstream device list is authoritative for this package.
7. Update doctor remediation from `nixosModules.default` to explicit group +
   direct package and named-module alternatives. Never mutate system or run
   sudo.
8. Update live tests that assert remediation strings. Leave archive files
   historical.

### Acceptance behavior

- Adding flake input alone changes nothing.
- Direct package line activates only packaged upstream udev rule.
- Named module is equivalent convenience and contributes no host policy beyond
  package list.
- Missing `plugdev` requirement is visible before user rebuilds.

### Verification

```sh
nix flake show
python3 tests/unit/test_nix_nrf_doctor.py
python3 tests/unit/test_preflight_xiao.py
nix flake check --all-systems --no-build -L
nix flake check -L
git diff --check
```

Search live files for stale `nixosModules.default`; only archive history may
retain it.

## 5. Phase 2 — udev package, `evalModules`, and full-system evaluation

### Goal

Prove executable safety contract at pure evaluation and derivation boundaries.

### Files

- new `nix/flake/checks/udev-module.nix`
- `nix/flake/checks/core.nix`
- `nix/flake/checks/default.nix`
- `nix/flake/per-system.nix`
- possibly focused fixture files under `tests/udev/`

### Checks

1. **Package shape:** package contains exactly
   `lib/udev/rules.d/60-openocd.rules` and no binaries, services, hooks, or
   second rule file.
2. **Upstream identity:** retain byte-for-byte comparison with pinned OpenOCD
   output.
3. **Required group declaration:** static rule inspection confirms upstream
   file references `GROUP="plugdev"`; this supports docs/remediation contract
   without altering file.
4. **`lib.evalModules` isolation:** declare only
   `services.udev.packages`, evaluate `nixosModules.udevRules`, and require
   exactly one expected package. Assert the module's exact public option AND
   observable config surfaces (only `services.udev.packages` after excluding
   module-system internals — a self-declared extra option or smuggled config
   path widens either surface and fails) and prove a synthetic undeclared
   config definition is rejected by the enabled `_module.check`.
5. **No-import negative:** same minimal evaluator without module yields empty
   package list.
6. **Full `nixosSystem`:** named module and direct package configurations
   contribute equivalent nix-nrf-owned udev package path exactly once.
7. Do not assert entire NixOS udev package list is otherwise empty; NixOS adds
   its own generated udev/hwdb packages.

### Verification

```sh
nix build -L .#checks.x86_64-linux.udev-rules
nix build -L .#checks.x86_64-linux.udev-module-eval
nix build -L .#checks.x86_64-linux.nixos-module
nix flake check --all-systems --no-build -L
nix flake check -L
```

## 6. Phase 3 — NixOS VM clean-room udev activation

### Goal

Boot minimal NixOS machine and prove direct least-intrusive configuration
activates upstream rule without installing unrelated project tools.

### Files

- new `nix/flake/checks/udev-vm.nix`
- `nix/flake/checks/default.nix`
- `nix/flake/per-system.nix`

### VM configuration

- `pkgs.testers.runNixOSTest`.
- Explicit `users.groups.plugdev = {}`.
- Dedicated normal test user in `plugdev`.
- Direct `services.udev.packages = [ nrfUdevRules ]`; do not use named module
  in primary VM because direct form is documented least-intrusive path.
- No nrfutil, nix-nrf, OpenOCD, NCS, west workspace, or hardware passthrough.

### VM assertions

- Machine boots and `systemd-udevd` is active.
- `plugdev` exists and test user is member.
- `/etc/udev/rules.d/60-openocd.rules` exists and resolves to expected package
  content.
- Rule remains byte-identical to package/upstream copy.
- `nix-nrf`, `nrfutil`, and OpenOCD are absent from normal system PATH.
- No nix-nrf-specific systemd service exists.

Before implementation, verify exact pinned-systemd behavior and availability
of `udevadm verify`; use it only if its exit semantics are confirmed. Do not
invent brittle assertions over unrelated baseline NixOS services.

Pinned behavior verified: `udevadm verify --resolve-names=early` on the
packaged rule fails without `plugdev` and passes once the group exists
(systemd 261.1 on the pinned nixpkgs rev), so the VM deliberately runs it
against the activated rule to prove NSS group resolution. The final test
proves activation and a clean system only; it does not add a synthetic USB
device or any USB-gadget/device-event semantics.

### Verification

```sh
nix build -L .#checks.x86_64-linux.udev-vm
nix flake check -L
```

Record runtime and closure size before deciding whether VM belongs in every PR
gate or a dedicated hosted check job. Default preference: normal flake check if
runtime stays reasonable.

## 7. Phase 4 — nrfutil versions command coverage

### Goal

Test all public nrfutil-backed `nix-nrf versions` boundaries without relying
on live network in normal checks.

### Files

- `nix/flake/checks/nrfutil.nix`
- `nix/flake/checks/default.nix`
- focused fake/test scripts if separation improves readability

### Deterministic fake-boundary check

Construct purpose-specific fake `nrfutilPackage`, then instantiate real
`nix/commands/default.nix`. Execute packaged `nix-nrf`, not shell fragments.

Required cases:

- success: exact argv `sdk-manager search ...`, arbitrary quoting preserved,
  stdout/stderr and exit 0 preserved;
- simulated remote-index/network failure: exact streams and exit 1 preserved;
- CLI failure: exit 2 preserved;
- arbitrary nonstandard failure: exit code preserved, not remapped;
- `versions --help` and `help versions`: exact
  `sdk-manager search --help` delegation.

Use existing `nrfutilPackage` construction seam. Do not add runtime PATH or
environment override that weakens exact-store-package production behavior.

### Real forced-offline check

Run packaged nrfutil in isolated HOME/NRFUTIL_HOME against unreachable loopback
SDK and toolchain index URLs. Require non-success and network/index download
diagnostic from nrfutil itself. Do not perform a separate global connectivity
probe.

### Verification

```sh
nix build -L .#checks.x86_64-linux.nrfutil-versions-boundary
nix build -L .#checks.x86_64-linux.nrfutil-search-offline
nix flake check -L
```

## 8. Phase 5 — dynamic `init-project` app

### Goal

Generate consumer project from explicit runtime inputs and latest Nordic
metadata without static template drift.

### Files

- new `bin/commands/nix-nrf-init-project`
- new Nix packaging module under `nix/commands/` or dedicated initializer
  directory selected during phase grounding
- `nix/flake/components.nix`
- `nix/flake/per-system.nix`
- generated skeleton source directory
- new public-boundary unit test under `tests/unit/`
- new flake check module/wiring
- `flake.nix` and removal/retirement of `templates/default`
- `README.md`, `docs/backends.md`, `docs/development/architecture.md`
- `.github/workflows/ci.yml` template-init replacement

### CLI contract

- positional destination, default `.`;
- `--backend nrfutil|west`, default `nrfutil`;
- `--ncs-version VERSION|latest`, default `latest` for nrfutil;
- optional `--non-interactive` accepted for CI clarity; first version does not
  prompt unless explicit interactive support is implemented and tested;
- no overwrite/force;
- concise stderr diagnostics and success summary naming destination, backend,
  and resolved concrete release.

### Latest resolution

For nrfutil, invoke exact packaged:

```sh
nrfutil sdk-manager search --json --skip-overhead
```

Parse with Python stdlib. Select semantic maximum among entries satisfying:

- `sdkType == "nrf"`;
- strict stable `vMAJOR.MINOR.PATCH`;
- remote SDK available;
- at least one remote toolchain available;
- no unstable/preview/RC version.

Do not trust response order. Failed network/index lookup aborts generation;
exact `--ncs-version` bypasses network and remains offline-capable.

For west, `latest` means semantic maximum in
`nix/backends/west/versions.nix`, never global Nordic latest.

### Filesystem safety

- Resolve and validate all arguments before writing.
- Render complete output into temporary location.
- Reject any target path collision before creating destination files.
- Reject symlink traversal outside destination.
- Atomically rename when creating new destination directory.
- For existing empty/unrelated directory, exclusive-create generated files and
  remove only files created by failed invocation.
- No hooks or generated-command execution.

### Public-boundary tests

- explicit exact nrfutil release, no network;
- latest stable selection from fake search JSON with newer RC/preview present;
- remote SDK unavailable;
- no remote toolchain;
- malformed JSON/schema;
- empty/no-stable result;
- simulated network failure;
- west latest constrained to local metadata;
- invalid backend/version;
- destination collision and symlink escape;
- generated flake contains concrete version and expected backend;
- generated project evaluates and dev shell realizes through current checkout.

### Static template migration

Remove static template from primary onboarding. If `templates.default` is
removed, update all public outputs/docs/CI in same phase. Do not leave a hidden
hard-coded version in a nominally dynamic path.

### Verification

```sh
python3 tests/unit/test_nix_nrf_init_project.py
nix build -L .#checks.x86_64-linux.init-project-tests
nix run .#init-project -- /tmp/nix-nrf-init-test --backend nrfutil --ncs-version v3.3.0
nix flake check -L path:/tmp/nix-nrf-init-test \
  --override-input nix-nrf-dev path:$PWD
nix flake check --all-systems --no-build -L
nix flake check -L
```

Use safe script-created temporary paths in actual implementation; command above
is illustrative and must not delete caller paths.

## 9. Phase 6 — nightly latest-NCS initializer workflow

### Goal

Detect drift between real Nordic latest-stable metadata, initializer behavior,
generated Nix, and shell construction without downloading SDK/toolchain.

### Files

- new `.github/workflows/latest-ncs-init.yml`
- initializer status/output contract if workflow needs machine-readable result
- documentation of nightly claim and inconclusive state

### Trigger and isolation

- nightly schedule away from top of hour plus `workflow_dispatch`;
- read-only repository permissions;
- `ubuntu-latest`, finite timeout, concurrency cancellation;
- isolated HOME and NRFUTIL_HOME under runner temp;
- existing Nix/Cachix setup;
- no cache of Nordic user state or SDK installation.

### Workflow behavior

1. Run initializer with `--backend nrfutil --ncs-version latest` into runner
   temp.
2. Capture resolved concrete release from machine-readable output or generated
   flake.
3. Verify strict stable version and generated concrete pin.
4. Evaluate generated flake against current checkout.
5. Realize and enter generated dev shell.
6. Verify `nrfutil`, `nix-nrf`, OpenOCD, and west commands exist.
7. Verify isolated HOME has no NCS installation before/after shell entry.
8. Run read-only bootstrap check; require expected "not ready" outcome naming
   resolved release and no installation.

### Failure classification

- Nordic DNS/timeout/connection/HTTP 5xx or explicit remote-index unavailable
  after bounded retries: workflow warning, summary says **inconclusive**, exit
  success so external outage does not block repository work.
- Search success with malformed JSON/schema, no stable remotely installable
  release, or wrong selection: fail.
- Initializer, generated-version assertion, flake evaluation, shell realization,
  or non-mutating boundary failure: fail.
- Never silently substitute repository-tested v3.3.0.

### Supported claim

Nightly pass proves latest stable advertised by real sdk-manager can be selected,
rendered into valid project, evaluated, and entered as non-mutating shell.
It does not prove SDK/toolchain download or firmware build.

## 10. Phase 7 — meaningful `lib.debug.runTests`

### Goal

Use Nix's pure test helper on genuine untested metadata consistency, not as
ceremonial duplication.

### Files

- `nix/flake/checks/west.nix` or new focused pure-check module
- `nix/flake/checks/default.nix`

### Tests

Run `lib.debug.runTests` over west release metadata and require:

- every declared `zephyrSdk.targets` entry has matching toolchain archive in
  `assets."x86_64-linux".toolchains`;
- every listed toolchain target is declared in `zephyrSdk.targets`.

Convert non-empty failure list into failed flake-check derivation with useful
expected/result diagnostics. Do not duplicate existing `tryEval` backend
selector tests, which remain stronger for expected evaluation failures.

### Verification

```sh
nix build -L .#checks.x86_64-linux.west-target-toolchain-consistency
nix flake check --all-systems --no-build -L
nix flake check -L
```

## 11. Phase 8 — clean-room resource telemetry

### Goal

Replace assumptions about "25 GiB SDK size" with measured evidence. Current
25 GiB value is a conservative free-space guard for SDK source, toolchain,
nrfutil state, extraction overhead, Nix closures, build tree, and safety
margin—not a measured SDK-only size.

### Files

- `tests/clean-room/run.sh`
- `tests/clean-room/README.md`
- `.github/workflows/clean-room.yml`

### Measurements

- filesystem free space before bootstrap;
- free space after bootstrap and after build;
- `$HOME/ncs` size;
- `$HOME/.nrfutil` size;
- build tree size;
- relevant Nix closure sizes where stable and meaningful;
- bootstrap and build elapsed time;
- retained evidence in logs/workflow summary.

Do not lower `NIX_NRF_CLEAN_MIN_FREE_GIB` until at least one complete retained
run establishes peak requirements with margin. Keep clean-room workflow manual
and self-hosted. Do not combine this with offline NixOS udev VM.

### Verification

```sh
NIX_NRF_CLEAN_DRY_RUN=1 bash tests/clean-room/run.sh
bash -n tests/clean-room/run.sh
nix flake check -L
```

Real bootstrap/build requires separate explicit approval.

## 12. Phase 9 — umockdev feasibility spike

### Goal

Determine whether real upstream rule semantics can be tested with synthetic
CMSIS-DAP device in isolated NixOS environment before considering kernel USB
gadget work.

### Initial scope

- Record or hand-construct XIAO-compatible umockdev fixture without modifying
  device.
- Reproduce USB parent and CMSIS-DAP interfaces needed for rule matching.
- Load real packaged `60-openocd.rules` in test environment with explicit
  `plugdev`.
- Trigger or replay device event.
- Observe whether real udev rule engine exposes expected mode/group/uaccess
  result.
- Document exact umockdev 0.19.x behavior and limitations.

### Decision gate

- If deterministic and meaningful: promote to stable udev semantics check,
  using plain derivation or existing udev VM according to observed rule-dir
  requirements.
- If umockdev cannot exercise rule application: document blocker and stop.
- Do not automatically implement `dummy_hcd`, configfs, Raw Gadget, USB/IP, or
  CMSIS-DAP protocol emulator. Those require new explicit scope decision.

Doctor classification itself stays on fake sysfs/dev roots; umockdev must test
new public behavior (rule semantics), not duplicate existing doctor tests.

### Outcome

The spike was deterministic and meaningful, so the semantics gate now lives
in the existing `udev-vm` check (`nix/flake/checks/udev-vm.nix`) instead of a
second VM or new flake check key. The check drives the real activated
`/etc/udev/rules.d/60-openocd.rules` tree with two hand-constructed umockdev
USB fixtures through pinned `umockdev-run` (0.19.3) and pinned systemd's real
`udevadm test --action=add --json=short` (261.1), and asserts the parsed JSON
at the NixOS test-driver boundary. The positive CMSIS-DAP fixture proves
`GROUP="plugdev"`, `MODE="0660"`, and `uaccess` tag/current-tag plus the
queued uaccess builtin; the otherwise identical nonmatching control proves
absence of every project rule outcome. Full record:
`docs/development/archive/udev-umockdev-semantics-handoff.md`.

This is rule-engine simulation, not real hotplug: `udevadm test` never
executes `RUN` keys, so queued commands prove rule assignment and command
queuing, not resulting ACL application. No kernel device is added to the
VM's device graph, no `dummy_hcd`/configfs/Raw Gadget/USB/IP/gadget work is
involved, no hardware is touched, and no host/workstation configuration is
adopted. The `plugdev` gid and baseline node modes are dynamic and are not
pinned. Phase 10 remains deferred and all existing approval boundaries are
unchanged.

## 13. Phase 10 — deferred workstation adoption

This phase lives in `/home/thomas-workstation/nixos-config-flake`, not this
repository, and requires separate approval because it changes root-owned host
policy.

### Safe sequence

1. Pin/use reviewed nix-nrf-dev revision containing completed udev docs/tests.
2. Add explicit `plugdev` group and user membership.
3. Add upstream udev package through direct `services.udev.packages`.
4. Keep all existing manual rules for first activation.
5. Review `nixos-rebuild dry-activate`/build result before switch.
6. Rebuild, then logout/login or reboot.
7. Replug probes.
8. Verify rule path, group, device modes/ACLs, doctor JSON/human output, and
   read-only hardware preflight.
9. Run manual hardware workflow only with explicit flash approval.
10. Consider removing overlapping manual entries in a later separate change;
    retain manual-only devices until demonstrated obsolete.

No automatic udev reload, trigger, group mutation, rebuild, or hardware action
belongs in repository checks.

## 14. Branch and delivery strategy

1. Finish PR #4 on `fix/doctor-cmsis-dap-transports` first.
2. Merge PR #4 only after hosted CI and manually approved hardware workflow.
3. Rebase `feat/nixos-safety-and-init` onto updated `main`.
4. Execute phases in order with feature-orchestrator review gate after each
   Executor handoff.
5. Prefer phase-sized commits. Do not combine workstation configuration with
   repository PR.
6. Split into multiple PRs if review surface becomes too large:
   - udev API/safety/evaluation/VM;
   - nrfutil tests + initializer + nightly;
   - pure metadata + clean-room telemetry;
   - umockdev spike.

## 15. Final repository gate

After all accepted repository phases:

```sh
git diff --check
python3 tests/unit/test_nix_nrf_doctor.py
python3 tests/unit/test_preflight_xiao.py
python3 tests/unit/test_nix_nrf_init_project.py
bash -n tests/hardware/run.sh
bash -n tests/clean-room/run.sh
nix flake check --all-systems --no-build -L
nix flake check -L
```

Manually inspect:

- `nix flake show` public names;
- generated initializer project;
- NixOS instructions and doctor remediation;
- workflow permission/network semantics;
- absence of stale live `nixosModules.default` and static template onboarding;
- OpenOCD udev rule provenance and exact package contents.

Hardware workflow, full clean-room bootstrap, workstation rebuild, and udev
activation remain separate explicit approvals.
