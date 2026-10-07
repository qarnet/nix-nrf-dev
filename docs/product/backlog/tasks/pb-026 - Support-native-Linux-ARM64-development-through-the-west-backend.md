---
id: PB-026
title: Support native Linux ARM64 development through the west backend
status: Blocked
assignee: []
created_date: '2026-10-04 12:25'
updated_date: '2026-10-06 07:31'
labels:
  - 'size:L'
  - 'area:west'
  - 'area:toolchain'
  - 'area:nix'
  - 'area:ci'
  - 'area:testing'
dependencies:
  - PB-001
references:
  - 'https://github.com/qarnet/nix-nrf-dev/issues/11'
priority: p1
type: feature
ordinal: 24000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

GitHub issue 11 requests Linux ARM64 support. Published outputs, SDK assets, multilib defaults, initializer templates and CI assume amd64. Native Pi experiments proved package/compiler/firmware feasibility, but Nordic's ARM64 toolchain index is empty and SDK-manager installation is unavailable.

### Desired outcome

Publish coherent x86_64-linux and aarch64-linux outputs. Preserve amd64 behavior and qualify native NCS v3.4.1 firmware development through west on ARM64, with platform-appropriate defaults and explicit unsupported Nordic-managed workflow errors. User-approved baseline migration and optional Python groups are owned by PB-001; earlier v3.3.0 reports are historical only.

### Scope / Non-goals

Two Linux hosts; per-host pinned sdk-manager 1.16.1/Zephyr SDK 1.0.1 assets; host-aware multilib; native package/tool execution; portable west initializer outputs; per-host repository/initializer presets; public factory keeps nrfutil default but rejects it on ARM64 without fallback; standalone Nordic bootstrap rejects unavailable host before acquisition. Preserve per-user managed paths and existing-workspace check-only ownership. Port tests and fix framed socket regression. CI uses one shared gate followed by native amd64/arm64 matrix, both gating trusted-main release, with bounded ARM64 VM software-emulation startup and native qualification. PB-001 supplies the explicitly approved v3.4.1 migration and optional requirement groups. No Docker implementation, /opt migration, Python lock/environment-manager redesign, further SDK release upgrade, new debugger/hardware guarantees, release bump or Git publication implied.

### Technical context

Issue https://github.com/qarnet/nix-nrf-dev/issues/11; docs/adr/0001-select-native-backends-explicitly.md records native backend policy. Native build and failed Nordic toolchain experiments informed this item; Notes retain their outcomes. Exact constructors/guards: flake.nix, nix/backends/default.nix, nix/backends/nrfutil/package.nix, nix/backends/west/{versions,shell,zephyr-sdk}.nix; initializer skeleton; checks and CI. Main base 78df6f5.

### Open questions

None blocking this bounded scope. Python completeness/reproducibility improvements and Docker remain separate work; current readiness limits must be documented, not presented as full bundle parity. Hosted CI evidence requires separately authorized publication; record that limit if unavailable.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Both declared Linux system output sets evaluate through the public flake; native package builds and real executable/compiler object probes pass, preserving exact sdk-manager pin and amd64 asset selection.
- [x] #2 Public ARM64 west shell builds v3.4.1 single-image/sysbuild firmware with imported manifests and linked module evidence; source/config/Git state and parent environment remain unchanged. Relevant amd64 regressions pass.
- [x] #3 Unavailable ARM64 nrfutil firmware factory/bootstrap requests and unsupported multilib requests fail clearly before source acquisition or Python repair; supported requests select explicit tools without silent fallback.
- [x] #4 Packaged initializer chooses a usable host preset; west-generated projects expose working outputs on both hosts; unsupported requests preserve destination state and do not perform remote resolution.
- [x] #5 All applicable repository gates pass natively on both hosts, including real framed OpenOCD traffic, source routing and original udev VM assertions; unavailable backend checks become explicit refusal coverage rather than being waived.
- [x] #6 CI graph has shared prerequisite plus independent native matrix entries with fail-fast disabled; checks/packages/smoke coverage has no silent omissions and both native entries gate trusted-main release without privileged fork execution.
- [x] #7 User/contributor docs describe actual host/backend/version/tool boundaries, per-user and workspace Python ownership, qualification evidence and known Python/GDB limits without claiming Nordic ARM64 bundle or hardware parity.
- [x] #8 Public scoped west exposes core commands before SDK/Python readiness without implicit bootstrap; explicit workspace operations respect selected workspace/conflicts and propagate real exit status. SDK extensions retain source/tool/Python readiness and no silent fallback. Public subprocess regressions prove missing, partial, ready and recovery states.
- [x] #9 General west help/failures and nix-nrf doctor expose core available, extensions discovered and command ready as distinct states, without importing arbitrary extension code in read-only doctor or claiming all commands ready from baseline imports. Structured/human diagnostics and parent-environment/source preservation pass regressions.
- [ ] #10 Portable real-SDK qualification resolves the selected west manifest/configuration and effective extension registry across supported backend/host and all four application layouts, accounts for every declaration including shadowed/missing entries, and loads each effective command parser through the public wrapper in its selected Python/tool environment. Registry discovery and per-command activation have separate evidence; no sample command proxies for availability. Optional offline ncs-sbom smoke is separate from the availability verdict. Missing files/dependencies/commands fail qualification explicitly; no hardware/network-dependent execution or hidden skips. Qualification passes or concrete upstream/environment blockers remain recorded.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Centralize host/backend capability policy and add native fixed assets; preserve amd64 defaults, fail unavailable ARM64 Nordic firmware and multilib paths before acquisition. Verify both-system evaluation and package/compiler behavior. 2. Make packaged initializer/presets host-aware and west templates portable; verify generated native consumer entry and destination-preserving failures. 3. Port backend/source checks, correct TCP frame consumption, validate host-specific asset coverage and bounded ARM64 VM startup without weakening udev assertions. Run local full gates and Pi native gates. 4. Split CI into shared prerequisite plus native matrix using reusable check/package/smoke coverage; validate topology and release dependency. 5. Transfer intended changes into a fresh Pi checkout, rerun real single/sysbuild imported-module builds and amd64 regression qualification using approved prepared sources; retain source/environment/ELF and resource evidence. 6. Update user/contributor docs and backlog evidence; no commit/push/PR or hardware actions without separate approval.

User-approved command-layer expansion: 1. Add shared west core dispatcher/metadata inspector, bind workspace-dependent core operations without SDK readiness, retain selected backend extension execution and source checks. 2. Expose three-state diagnostics in general help/failures and doctor with command-specific readiness unverified unless checked. 3. Add real-west synthetic self/import/Zephyr-only/disabled/missing-dependency/state-recovery tests across layouts and supported backends, including explicit local-only init/update and non-mutation boundaries. 4. Add exhaustive opt-in real SDK command help catalog plus offline SPDX-tag SBOM output validation to portable qualification runners; run prepared environments on amd64 and Pi, record all upstream/dependency failures rather than waive. 5. Run relevant native gates, update caller docs/evidence; same branch/change, no open PR currently, no unrequested publication or hardware work.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PB-025 Docker backend created as deferred P3 Backlog. Research and Pi prototype evidence establish ready scope; production implementation now authorized. Python profile/lock/prefix redesign remains excluded. Repository contract overrides skill PR-gated Done default: evidence determines lifecycle; Git publication remains separately authorized.

Intended implementation qualification: both-system public evaluation passed; all six package outputs build natively on amd64 and Pi ARM64. New west-sdk-native-probes compiles ARM/RISC-V ELF32 objects, checks machine headers, and executes plain GDB on both hosts; sdk-manager remains 1.16.1. Packaged refusal/default/initializer gates pass on both hosts. Fresh portable imported-workspace qualification passed four amd64 builds/four negative checks (/tmp/opencode/pb026-amd64-imported-workspace/result.json), plus two native ARM64 west builds/two negative checks with linked source_import_fixture_value and preserved source/Git/config state (Pi ~/nix-nrf-experiments/pb026-native-imported-workspace/result.json; total 675.27s, builds 149.95s/161.94s). Public generated west projects evaluate both hosts and enter natively with clean parent environment/no SDK acquisition; evidence /tmp/opencode/pb026-amd64-consumer/result.json and Pi pb026-native-consumer/result.json. CI partition/topology regression and actionlint pass: shared prerequisite, complete dynamic native checks/packages, fail-fast false, trusted-main release requiring both hosts. Hosted workflow not run; publication remains unauthorized. Full amd64 gate passes; Pi full native gate passes with KVM (pb026-native-all-gates-verified.json, 325.81s), before latest test-only coldplug adjustment. TCG acceptance still unproved: 300s control/450s service/900s device budgets alone failed at root-label deadline. Bounded debug trace shows all-object module/driver flood outranks worker dispatch; actual-device coldplug improves dispatch and root-label discovery. Latest ARM64 VM candidate uses --type=devices in initrd and stage 2 while retaining every original assertion; full forced-TCG trial pb026-tcg-device-coldplug is running. No hardware operations, commits, pushes, release bump, or dependency-pin changes. Local Pi evidence copies retained under /tmp/opencode/pb026-evidence.

Final TCG diagnosis: device-only coldplug plus removal of stage-2 synchronous SetChildrenMax startup control boots through root mount and guest backdoor (~1072s), but the unchanged original udevadm control --reload assertion fails with "Failed to issue io.systemd.service.Reload() varlink call: Timer expired" (pb026-tcg-stage2-no-control, 1227.71s). A bounded udevadm settle --timeout=300 fails its initial varlink Ping (pb026-tcg-coldplug-settled, 1418.12s); unsuccessful settle workaround removed. Existing guest assertions remain intact. No more blind timeout increases; current obstacle is pinned systemd/QEMU TCG control responsiveness, not firmware compilation. PB-026 Blocked pending deeper source-level diagnosis or explicitly approved isolated KVM CI infrastructure design. Never silently omit ARM64 VM gate or expose personal Pi/privileged self-hosted runner to untrusted fork PR code. Docs now state native host/backend/API/version/Python ownership, withMultilib limits, GDB/hardware non-claims, immutable Nix SDK acquisition versus mutable bootstrap, and old-tag support limits. Native firmware/package/compiler/generated-consumer acceptance remains passed; AC5 remains unchecked. Docker PB-025 stays deferred. Hosted execution/publication still unauthorized; no commits/push/PR/hardware actions performed.

Final recorded code state: nix flake check -L passes on amd64 and native Pi ARM64. Pi report pb026-native-final-recorded-state.json returns 0 in 145.43s; original udev VM assertions pass under KVM in 36.48s. Formatting/actionlint/pre-commit/backlog checks pass, and git diff --check is clean. KVM ACL restored; no QEMU or test runner remains active. Software-emulated control responsiveness remains the sole unchecked acceptance criterion (AC5). Evidence copies /tmp/opencode/pb026-evidence retain firmware, compiler/CI, consumer, package, and failed TCG reports/raw logs. Six of seven acceptance criteria demonstrated; status remains Blocked, not Review/Done.

User selected continued hosted-TCG diagnosis, not KVM infrastructure redesign. Source-level cause found and reproduced without VM boot: systemd 261.1 udev_rules_parse_file saves stats keyed by ConfFile.original_path; config_get_stats_by_path scanner returns resolved-parent paths. On a symlinked rules directory, real pinned shared-library enumeration/stat comparison reports original_equal=0 and resolved_equal=1; direct-directory control reports both=1, empty and /dev/null masks excluded. Tiny diagnostic /tmp/opencode/udev-stat-probe.{c,nix}; Nix output /nix/store/z3k4s33n5iv36f62gihb2rv5i9nzgyyf-udev-stat-path-probe. Added test-image-only nix/flake/checks/udev-systemd.nix to save stats under c->result; same systemd version/source pin/existing patches, no consumer package change. NixOS systemd.package applies selected package to both stage 2 and initrd. Patched amd64 package builds, 44-rule install check passes, amd64 original udev VM assertions and pre-commit pass. Native ARM64 patched-package build pb026-systemd-stat-path-build running with bounded build timeout/retained telemetry; full forced TCG rerun must follow successful native build. AC5 still unchecked; no completion claimed.

Hosted-TCG design retained. Confirmed stat-key repair passes complete forced-TCG udev VM gate: pb026-tcg-stat-path-repair.json returns 0 in 1518.35s (script 1485.34s), every original reactivity, byte-identical activation, group-resolution, positive/control synthetic-rule, and clean-system assertion passes. Unchanged udevadm control --reload now succeeds. No larger guest deadline or skipped assertion added for repair. Native ARM64 same-version package build passes in 1461.71s with four per-command build cores; exact NixOS image/driver including existing audit compatibility patch builds in 1516.47s. Temperature/no-throttle telemetry retained. KVM ACL restored and QEMU stopped. Remaining action is final full-gate rerun/docs/evidence reconciliation before Review; all seven acceptance criteria now demonstrated, but no GitHub hosted run/publication claimed.

User approved core west before SDK/Python readiness and three visible states, with doctor/docs references. Scope expanded explicitly; prior build-focused acceptance evidence retained, new AC8-10 initially unchecked. Installed v3.3.0 registrations include dangling suit-manifest implementation and prepared Python lacks some optional command dependencies; full-catalog gate must report these as failures. Command discovery must use resolved manifests rather than directory presence or a hand-maintained command list.

User clarified availability testing must target cause, not ncs-sbom success. Approved resolved-registry primary boundary: west Manifest.from_topdir plus WestApp.load_extension_specs, effective names/owners, per-declaration structural diagnostics without imports in doctor, and separate isolated parser activation. Offline SBOM becomes --sbom-smoke only, with separate outcome excluded from availability verdict. Public shadowing regression compares doctor effective registry with actual west selection; topdir alone is not activation proof.

Resolved-registry implementation and public regressions pass: 23 source/workspace tests on both hosts, 30 doctor tests, complete native nix flake check -L on amd64 and Pi (Pi pb026-resolved-registry-final-native-v5.json, return 0, 771.89s, no throttling); git diff --check clean. Core routing fixes cover bundled flags, help syntax, core aliases, local-config foreign-workspace protection and cancellation (30s startup budget, unchanged 5s cancellation requirement). Doctor exposes west-filtered effective commands plus declaration/file/shadowing diagnostics without importing extension code; inspector failures now visible in human and JSON output.

Availability qualification is not universally passed. amd64 /tmp/opencode/pb026-resolved-registry-final-v5/result.json records 248 parser cases: west 28/124 fail, nrfutil 4/124 fail. Native ARM64 pb026-resolved-registry-v4/result.json records 28/124 failures. Each selected imported workspace resolves 31 registrations (10 Nordic, 21 Zephyr) across all four layouts; selected manifest/names/owners agree, source/config preservation passes, no SBOM smoke requested. Concrete blockers: stock v3.3.0 missing suit_manifest.py; caller-owned west Python on both hosts missing pygit2 (ncs-loot/compare/upmerger), usb (Thingy DFU/reset), natsort (Twister). Direct isolated imports confirm missing modules and working packaging.version. Earlier stock catalog additionally reports wget missing for five Matter ZAP commands; Matter explicitly excluded from imported fixtures. Pi v4 report conservatively marks structural partial discovery failed; final runner separates resolved registry from missing implementation/parser failure without relabeling old evidence. AC10 remains unchecked and item Blocked pending approved provisioning/upstream disposition; no silent waiver, SDK repair, package installation, hardware operation or publication.

User superseded v3.3.0 active baseline with v3.4.1 on both backends. PB-001 owns migration and refreshed qualification; prior v3.3.0 reports remain historical only. The session then paused for additional user information; its checkpoint has since been retired. No acceptance was rechecked from old evidence.

PB-001 completed migration acceptance with fresh v3.4.1 evidence. User-approved baseline fields/AC2 now identify3.4.1/SDK1.0.1; no old reports relabeled. Refreshed package/compiler/consumer/source/environment/native gates and imported-module builds pass both hosts. Python missing-import blockers resolved through explicit groups; remaining strict stock-SDK parser blocker is solely missing upstream suit_manifest.py (312amd64/156ARM64 cases,8/4failures). AC10 remains unchecked and status Blocked pending explicit upstream disposition; no change to SDK or silent waiver. Checksum/generator/action stages PB-030 through PB-033 remain Backlog.

Publication and bounded PR validation subsequently authorized. Draft PR https://github.com/qarnet/nix-nrf-dev/pull/13 publishes ca3adc160000cec6311a7b9452d94ed65692e12a and links issue #11. Hosted run 37537793047 passes shared checks and both native entries; release skipped. Independent clean Pi checkout passes full flake gate in 751.87s (state/pr13-clean-native-gates.json). Offline Pi nRF52840 SMP/MCUboot build passes in 351.61s; SDK debug-key signature, ZIP CRCs, packaged signed-image byte identity and tamper rejection pass (pr-smp-sign-package-verified/result.json). ARM/RISC-V gdb-py imports initialize on both hosts. These are narrow host/offline observations, not production signing or device update/debug acceptance. No firmware execution, RF, flashing, recovery or device lifecycle action performed.

Tagged upstream SUIT/history research narrows the missing helper's practical loss: init/review/check maintained template provenance, not signing, envelope generation or DFU transfer. Integrated Nordic SUIT support was removed in NCS 3.1.0; restoring the helper alone would not restore the legacy nRF54H20 workflow. docs/support-matrix.md records sources, lifecycle migration warnings and separate MCUboot/DFU/debug boundaries. AC10 remains unchecked; publication and this diagnosis do not waive the strict parser blocker.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
created: 2026-10-04 12:26
---
Refined from issue 11 and completed source/registry/Pi research. Native west path, preserved public defaults, explicit Nordic-backend refusal, per-user storage policy and three-job CI topology are decided. Size L reflects coherent cross-file platform/API/CI change; repository contract permits bounded L items without forced splitting. Docker PB-025 remains deferred and independent. Python environment redesign is excluded; document known readiness limits.
---
<!-- COMMENTS:END -->
