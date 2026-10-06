# Work session checkpoint

## Current draft PR validation state

User authorized committing, pushing, opening a draft PR linked to issue #11, and
full PR/manual Pi validation. Merge, release-version bump, flashing, recovery,
RF transmission and device lifecycle changes remain unauthorized. No firmware
is run as part of compile/sign/package qualification.

User resumed PB-001 on 2026-10-06. Fresh v3.4.1 qualification now passes 12 amd64
baseline builds and six ARM64 baseline builds, plus four amd64 and two ARM64
imported-workspace builds with original inputs unchanged. Both native full gates,
all six package outputs per host, generated consumer evaluation/entry and scoped
parent-environment identity checks pass. The latest Pi full-gate report is
`state/pb001-v341-final-native-gates-v3.json` (return 0, 90.25s, cached successful
native gates); consumer report `pb001-v341-native-consumer/result.json` passes.
PB-001 is Done with all four criteria verified and retained under backlog
`completed/`. PB-026 remains Blocked only on strict stock-SDK parser qualification
for the missing upstream suit-manifest implementation; its baseline fields now
identify v3.4.1. No session-owned verification jobs remain running.

Optional requirement readiness now verifies selected root distributions/version
specifiers, not only sentinel imports and pip consistency. Unselected module test
requirements are not implicitly enabled. Public regression uses actual installed
distribution metadata, successful pip check, a missing requested package, and
explicit offline wheel provisioning; workspace `--yes` remains check-only.

All 39 stock command registrations are accounted for in 312 amd64 and 156 ARM64
parser cases; only missing upstream suit-manifest fails (eight/four cases).
Preservation passes. This remaining upstream defect is not a migration failure or
a waived parser case. Current evidence and limitations are canonical in
`west-backend-status.md#v341-qualification` and product item notes.

Initial implementation is published as commit
`ca3adc160000cec6311a7b9452d94ed65692e12a` in draft
[PR #13](https://github.com/qarnet/nix-nrf-dev/pull/13), linked to issue #11.
[Hosted run 37537793047](https://github.com/qarnet/nix-nrf-dev/actions/runs/37537793047)
passes shared checks and both native CI entries; release is skipped. A separate
clean checkout of that commit passes the full Pi flake gate in 751.87s
(`state/pr13-clean-native-gates.json`), without throttling.

Manual Pi SMP/MCUboot compile/sign/package qualification passes in 351.61s.
Offline verification confirms the debug-key signature, ZIP CRCs, packaged-image
byte identity and rejection of a payload-bit flip. Both ARM/RISC-V Python-enabled
GDBs initialize on amd64 and ARM64. These observations do not qualify production
signing, device transfer, target attachment or recovery. Evidence and safety
limits are in [the support matrix](../support-matrix.md#manual-pr-validation).

No hardware operations occurred. PB-030/031/032/033 remain future work; the full
upstream-derived Python lock generator is not part of this completed migration.
Full branch-scoped documentation audit and follow-up publication/CI verification
remain to finish. Earlier pause snapshot below is historical and its resume
prohibition no longer applies. All remaining sections describe that pause state,
not current instructions or acceptance.

## Historical pause snapshot (not current instructions)

Work paused at the user's request on 2026-10-06. This file is a resumption
checkpoint, not an implementation plan or a passing acceptance report.

Subsequent read-only discussion is recorded in
`docs/development/nordic-artifact-metadata-research.md`. It verifies fixed-file
generation/installation, the west pin's Git history and anonymous Artifactory
API limits, and recommends maintainer-generated committed locks. It does not
authorize implementation or resume paused jobs.

Separate maintainer request authorized metadata indexing and backlog planning.
`scripts/nordic_artifact_catalog.py` now captures a bounded nine-source published
inventory as JSONL; initial 391-record snapshot is under
`docs/research/nordic-artifacts/2026-10-06/`. Its hardware-free HTTP/CLI gate
`nordic-artifact-catalog-tests` passes. PB-029 tracks broader acquisition research;
PB-030 through PB-033 track checksum validation, generation, manual workflow and
later scheduled proposals. AGENTS.md now records the west metadata discrepancy.
This separate work did not resume SDK provisioning or firmware qualification.

## Repository and permissions

- Repository: `/home/thomas/repos/nix-nrf-dev`.
- Branch: `plan/linux-aarch64-support`; main base `78df6f5`.
- Changes remain uncommitted. No push, PR, merge, release bump, flashing,
  recovery, or hardware operation is authorized or performed.
- User approved isolated v3.4.1 SDK/toolchain/Python provisioning and compile-only
  qualification on amd64 and `thomas-rpi4`, preserving existing environments.
- Do not restart jobs or make implementation changes until the user resumes work.
- PB-001 is In Progress, refined from nrfutil-only to both-backend v3.4.1 migration
  and optional Python requirements. PB-026 is Blocked; its previous v3.3.0
  qualification is historical, not acceptance of the new baseline. PB-025 Docker
  remains deferred.

## Implemented direction

- Active west metadata, repository shells, package output, compiler probes,
  qualification defaults, clean-room prerequisites and primary examples now
  select NCS v3.4.1 / Zephyr SDK 1.0.1 / Python 3.12 / initial west 1.5.0.
- Public package renamed to `west-zephyr-sdk-v3_4_1`; old active west metadata key
  removed. SDK GNU compiler root is `gnu/<target>` and CMake integration is
  `cmake/zephyr/gnu`. Python 3.12 library is supplied for GDB; Python-GDB runtime
  integration is not claimed.
- `pythonRequirementGroups = [ "ncs-extra" "ncs-ci" ];` is optional, west-only,
  validated configuration. SDK baseline requirements remain mandatory.
- Selected requirement paths resolve correctly for relocated/imported Nordic
  and Zephyr projects. Existing workspace Python remains check-only, even with
  `--yes`.
- Baseline and selected extra requirement files resolve in one pip invocation.
  Sequential installation caused a real `chardet`/`spsdk` conflict; readiness now
  includes non-mutating `python -m pip check`.
- Nordic's Python index had no usable ARM64 `pygit2>=1.15.0` distribution.
  The selected ncs-extra recipe explicitly seeds pygit2 from PyPI, then resolves
  SDK requirements jointly against their declared index. This is not a generic
  multi-index fallback. Documentation and regression review of this latest
  recipe still need finishing.
- Managed setup child processes clear inherited `ZEPHYR_BASE`, `Zephyr_DIR` and
  `WEST_CONFIG_LOCAL`, so old SDK context cannot redirect new initialization.
- v3.4.1 Nordic `VERSION` changed from scalar text to VERSION_MAJOR/MINOR,
  PATCHLEVEL, VERSION_TWEAK, EXTRAVERSION and VERSION_METADATA fields. Source
  resolver and local fixture preparation now normalize that format; `lts`
  metadata is not part of the configured release comparison.
- Registry-first qualification remains: doctor uses west's own resolved manifest
  and extension-spec loader without importing implementations; parser activation
  is a separate public-wrapper test. SBOM is opt-in `--sbom-smoke`, excluded from
  availability verdict.

## Verified official facts

- v3.4.1 release exists. v3.4 is five-year LTS and last NCS release branch
  supporting nRF52; nrf52840 is active in tagged release metadata.
- v3.4.1 still declares missing `scripts/west_commands/suit_manifest.py`.
  SDK migration does not fix this upstream registration defect.
- Current Nordic Linux ARM64 toolchain index is still empty, including v3.4.1.
  Native sdk-manager executable availability is not firmware-bundle availability.
- Linux amd64 v3.4.1 Nordic bundle is `8285d8ad56`, now installed in an isolated
  location. Toolchain env confirms its new `zephyr/gnu` layout.
- Keep `cbor2==5.9.0`: v3.4.1 still uses zcbor 0.8.1, incompatible with cbor2 6.x.

Official sources:

- https://github.com/nrfconnect/sdk-nrf/releases/tag/v3.4.1
- https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/doc/nrf/releases_and_maturity/releases/release-notes-3.4.1.rst
- https://github.com/nrfconnect/sdk-nrf/blob/v3.4.1/scripts/west-commands.yml
- https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v1.0.1/sha256.sum
- https://files.nordicsemi.com/artifactory/NCS/external/bundles/config.json
- https://files.nordicsemi.com/artifactory/NCS/external/bundles/v3/index-linux-aarch64.json

## Fresh isolated environments

amd64:

- Home: `/tmp/opencode/pb001-v341-west-home`.
- SDK: `.../ncs/v3.4.1`; Python: SDK-local `.venv`.
- Test-owned workspace app: SDK `qualification-app/`.
- Nordic state: `/tmp/opencode/pb001-v341-nordic-state`.
- Nordic tools: `/tmp/opencode/pb001-v341-nordic-tools/toolchains/8285d8ad56`.
- Set `NRFUTIL_HOME` to the isolated state for nrfutil qualification, never the
  user's normal inventory.
- Source identity: sdk-nrf `b20f8619ba9a5530f8c34b0a130d829947cfe55d`, sdk-zephyr
  `33fa6a7aac6a4401d16a67cb9f27a3483fa02dd6`.

Pi:

- Checkout: `/home/thomas-rpi4/nix-nrf-experiments/implementation`.
- Home: `/home/thomas-rpi4/nix-nrf-experiments/pb001-v341-west-home`.
- SDK: home `ncs/v3.4.1`; Python: SDK-local `.venv`.
- Successful provisioning report:
  `state/pb001-v341-west-provision-native-prerequisite.json` (return 0, 180.42s).
- Earlier report `pb001-v341-west-provision.json` failed at Nordic-index pygit2
  resolution; preserve it as diagnostic history.
- Approximately 68 GiB free after provisioning; telemetry showed no throttling.
- Preserve all earlier seed Git object stores: old shared-clone fixtures depend
  on them. They are not active SDK baseline inputs.

## Acceptance evidence and limits

- amd64 SDK 1.0.1 package builds; ARM/RISC-V ELF32 compiler probes and plain GDB
  pass. Both-system no-build evaluation passed.
- Complete amd64 `nix flake check -L --keep-going` passed during migration, before
  the latest VERSION parser, pip-consistency and native-prerequisite edits.
  **Do not call that a final gate pass for current files.**
- Bootstrap suite passed 39 tests plus nine fixture tests before the newest
  consistency regression; source suite passed 23 tests before structured VERSION
  fixtures. Rerun current suites and both native full gates when work resumes.
- `tests/application-types/baseline.py` is a new opt-in compile-only runner.
  amd64 `/tmp/opencode/pb001-v341-baseline-builds-v2/result.json` passed 12 cases:
  six targets/profiles on each supported backend. Includes nRF52840 single and
  sysbuild, nRF5340 CPUAPP/CPUNET, nRF54L15 CPUAPP/FLPR with automatic launcher.
  ELF machine/hash evidence retained; no hardware execution claimed.
- amd64 `/tmp/opencode/pb001-v341-command-layers-four-layouts/result.json` completed
  312 parser cases (39 declarations, four layouts, two backends), eight failures:
  only missing suit-manifest implementation repeated across layouts/backends.
  Other previously missing imports now load. Verify the full report's preservation
  field before citing it; no source-preservation claim is inferred from case count.
- Earlier `pb001-v341-command-layers/result.json` had only three layouts because
  SDK-owned Nordic is manifest self, not a named project. Runner fallback fixed;
  do not use that incomplete report as four-layout acceptance.
- Pi compile run was stopped for this pause during the last FLPR case. Retained
  `pb001-v341-baseline-builds/result.json` contains five completed passing cases.
  It says `outcome: failed` because incomplete; this is cancellation, not proof of
  an FLPR compiler failure. Runner report `state/pb001-v341-baseline-native.json`
  records returncode -15. No final ARM64 six-case pass is claimed.
- Session-owned remote verification descendants were terminated. No session
  provisioning/build job remains running locally or on the Pi.

## Resume checklist

1. Hear the user's additional information before deciding any next implementation.
2. Review latest requirement recipe, VERSION parsing and regression tests. Finish
   documentation of explicit PyPI native prerequisite and joint pip resolution.
3. Rerun interrupted Pi FLPR/build qualification using a new output root; never
   overwrite evidence. Run v3.4.1 registry/parser audit on Pi with a real
   workspace-application directory. No SBOM smoke required.
4. Qualify application-owned imported v3.4.1 fixtures with the updated VERSION
   parser; do not reuse v3.3.0 build outcomes.
5. Run current focused tests, both-host native full gates and all package/smoke
   outputs; audit remaining active v3.3.0 examples/fixtures separately from
   historical evidence. Some old strings remain in synthetic version tests and
   comments; migration cleanup is not complete.
6. Reconcile PB-001/PB-026 acceptance and evidence. Keep upstream suit-manifest
   defect explicit; no silent skip, SDK patch, or passing-all-commands claim.
7. No commit/publication or hardware action without separate authorization.
