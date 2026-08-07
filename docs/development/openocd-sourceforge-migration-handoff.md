# OpenOCD SourceForge migration handoff

## Phase goal

Move project OpenOCD source pin from GitHub mirror to canonical SourceForge Git
repository, while preserving immutable Nix inputs and all existing Nordic flash
behavior.

Current branch is `feat/nrfutil-sdk-manager`; starting worktree was clean.

## In scope

- Change OpenOCD source fetch in `nix/hardware/openocd.nix` from
  `pkgs.fetchFromGitHub` to `pkgs.fetchgit` using canonical SourceForge URL.
- Pin exact SourceForge `master` commit and known fixed-output hash below.
- Keep submodule fetching enabled. This preserves current source shape needed by
  inherited OpenOCD/Nixpkgs autoreconf behavior. Upstream `.gitmodules` controls
  nested Jim Tcl and libjaylink origins; this phase changes OpenOCD repository
  origin, not dependency origins.
- Update current maintenance instructions in `CONTRIBUTING.md` to use
  SourceForge and explain resolving moving `master` to immutable commit.
- Replace archived raw GitHub OpenOCD link in
  `docs/development/archive/nix-nrf-doctor-handoff.md` with equivalent pinned
  SourceForge raw link. Keep archived revision `e6752ec...` there because that
  section records historical evidence from that revision.
- Run package, flake, and authorized physical hardware validation.
- Commit all scoped changes, including this handoff document.

## Out of scope

- No OpenOCD code patches, Tcl recipe behavior changes, wrapper changes, NixOS
  module changes, probe-detection changes, or dependency-origin rewrites.
- No switch away from inherited external Jim Tcl/libjaylink build configuration.
- No NCS clean-room bootstrap/build rerun. Those gates already passed and source
  migration affects OpenOCD only.
- No recovery, mass erase, APPROTECT changes, probe firmware changes, or board
  wiring changes.
- No push, merge, PR, release bump, or history rewrite.

## Exact implementation

### `nix/hardware/openocd.nix`

Retain existing `pkgs.openocd.overrideAttrs` structure, `pname`, and inherited
package behavior. Replace only source fetch expression with equivalent shape:

```nix
src = pkgs.fetchgit {
  url = "https://git.code.sf.net/p/openocd/code";
  rev = "da3920b0a52dc2d394afb222c688dac7e57acc1b";
  hash = "sha256-ILHycdQeoMbtZvpCl7nqPgMEXYD4A1LlR1XEiopvD9A=";
  fetchSubmodules = true;
};
```

Do not use moving `master` directly in `rev`. Do not retain `owner` or `repo`
fields from `fetchFromGitHub`.

### `CONTRIBUTING.md`

Update “Bumping the openocd pin” so maintainers:

1. Inspect canonical SourceForge repository at
   `https://sourceforge.net/p/openocd/code/ci/master/tree/`.
2. Resolve SourceForge `master` to exact commit, then put that immutable SHA in
   `rev`; moving branch names/tags are not Nix pins.
3. Update fixed-output `hash` with submodules included. Existing failed-build
   hash workflow may remain if accurate for `pkgs.fetchgit`.
4. Run both OpenOCD package builds and normal flake gate.
5. Run manual hardware harness.

Remove GitHub OpenOCD mirror as maintenance source. Keep unrelated GitHub/Cachix
workflow references unchanged.

### Archived handoff

At `docs/development/archive/nix-nrf-doctor-handoff.md`, replace old raw GitHub
URL with pinned SourceForge raw URL for same historical revision:

```text
https://sourceforge.net/p/openocd/code/ci/e6752ecbcf72efe4e213e8418e381ff2e0ffdf54/tree/contrib/60-openocd.rules?format=raw
```

Do not rewrite archived revision or historical conclusions.

## Grounding evidence

- Canonical repository: `https://git.code.sf.net/p/openocd/code`.
- SourceForge `master` resolved during planning to
  `da3920b0a52dc2d394afb222c688dac7e57acc1b`.
- Prefetched source with submodules produced
  `sha256-ILHycdQeoMbtZvpCl7nqPgMEXYD4A1LlR1XEiopvD9A=` and store path
  `/nix/store/hcprkpmnzawdi2yxgmd5a4v749z91jpa-code-da3920b`.
- Candidate contains `tcl/target/nordic/nrf53.cfg` with application/network flash
  banks and `tcl/target/nordic/nrf54l.cfg` with CPU and AUX access ports.
- Candidate SourceForge raw udev-rule URL returned canonical
  `contrib/60-openocd.rules` during planning.
- Existing build inherits external Jim Tcl and libjaylink flags from pinned
  Nixpkgs (`--disable-internal-jimtcl`, `--disable-internal-libjaylink`) and has
  previously passed package and hardware checks.
- Current worktree was clean at phase start.

## User-observable acceptance behavior

- Evaluated OpenOCD source comes from canonical SourceForge URL at exact SHA.
- Unwrapped and wrapped OpenOCD packages build successfully.
- Full flake gate passes without weakened checks.
- `nix-nrf probes` and existing Tcl recipes still enumerate and byte-verify both
  nRF5340 cores plus nRF54L15 CPUAPP/FLPR images on authorized hardware.
- Hardware run performs no recovery or mass erase.

## Verification commands

Run from repository root, in this order:

```sh
nix build .#openocd-master-unwrapped -L
nix build .#openocd-master -L
nix flake check --all-systems -L
nix develop --command bash tests/hardware/run.sh
```

Afterward inspect:

```sh
git status --short
git diff --check
git diff
git log --oneline -5
```

Expected physical probes:

- nRF5340 QKAA: `E6635C08CB1F502B`
- XIAO nRF54L15 AAC0: `8EE9B3FF`

Hardware harness already invokes nRF53 `flash_both` with recovery disabled.
Do not run any separate recovery or erase command.

## Commit and recap

Stage only intended files. Commit once with concise repo-style message, for
example `build(openocd): fetch canonical SourceForge source`. Do not add
attribution footer.

Return recap containing:

- Files changed and behavior changed.
- Exact commands run and results, including flake check count and physical
  byte-verification evidence.
- Commit hash/message.
- Any blockers or deviations.

Stop and escalate without committing incomplete work if two materially
different attempts fail, source/hash evidence conflicts, validation needs test
weakening, hardware identifies unexpected probes, or any destructive action
appears necessary. Preserve worktree and report exact command/error/evidence.
