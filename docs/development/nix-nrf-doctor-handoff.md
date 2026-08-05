# `nix-nrf doctor` Hardware Access Handoff

## Goal

Add read-only environment and probe-access diagnostics:

```text
nix-nrf doctor
nix-nrf doctor --json
```

Doctor must distinguish:

- selected SDK/toolchain ready versus missing;
- no visible debug probe;
- visible CMSIS-DAP/J-Link candidate with inaccessible USB/hidraw nodes;
- at least one accessible candidate;
- mixed accessible/inaccessible candidates.

Provide exact NixOS and generic Linux udev remediation without invoking sudo,
changing groups, installing rules, opening probes, or mutating host state.

## Grounding

### Current probe discovery

`bin/nix-nrf-probes` scans `/sys/bus/usb/devices/*/product` for `CMSIS-DAP`
and then invokes OpenOCD. OpenOCD's generic failure currently becomes only
`cannot open probe (udev permissions? probe in use?)`; it cannot distinguish
visibility from node access before opening hardware.

### Pinned upstream rules

Pinned OpenOCD source revision:

```text
e6752ecbcf72efe4e213e8418e381ff2e0ffdf54
```

Its canonical `contrib/60-openocd.rules`:

- warns against running OpenOCD as root;
- applies `MODE="660", GROUP="plugdev", TAG+="uaccess"`;
- includes generic
  `ATTRS{product}=="*CMSIS-DAP*"` coverage;
- includes SEGGER J-Link VID/PID entries;
- applies to `usb`, `tty`, and `hidraw` subsystems.

Exact source:
<https://raw.githubusercontent.com/openocd-org/openocd/e6752ecbcf72efe4e213e8418e381ff2e0ffdf54/contrib/60-openocd.rules>.

Built `openocd-master-unwrapped` already contains:

```text
$out/share/openocd/contrib/60-openocd.rules
```

NixOS `services.udev.packages` only imports files under a package's
`etc/udev/rules.d` or `lib/udev/rules.d` (pinned Nixpkgs
`nixos/modules/services/hardware/udev.nix`, option description). Therefore
passing OpenOCD directly does not activate its contrib rule; a thin relocation
package is required.

### Linux node mapping

For a USB device sysfs directory:

- `busnum` + `devnum` map to `/dev/bus/usb/%03d/%03d`;
- interface descendants matching `*:*/hidraw/hidraw*` map by basename to
  `/dev/hidraw*`;
- `os.access(path, os.R_OK | os.W_OK)` reports current-process access.

Current host evidence includes one J-Link (`product=J-Link`) and two named
CMSIS-DAP devices. User groups include `dialout` but not `plugdev`; upstream
`TAG+="uaccess"` means group membership alone is not definitive, so doctor must
report groups as context and test nodes directly.

## Exact implementation

### Upstream udev-rule package

Add `nix/nrf-udev-rules.nix`:

```nix
{
  pkgs,
  openocd,
}:
```

Create a small derivation named `nix-nrf-udev-rules` that copies, without
content changes:

```text
${openocd}/share/openocd/contrib/60-openocd.rules
  -> $out/lib/udev/rules.d/60-openocd.rules
```

Fail build if source rule is absent. Preserve upstream SPDX/content; do not
maintain a repository VID/PID list.

Expose as `packages.udev-rules`.

Add `nixosModules.default` at top-level flake output. Module must add current
system's `self.packages.${pkgs.stdenv.hostPlatform.system}.udev-rules` to
`services.udev.packages`. No options needed in first version. Document consumer:

```nix
imports = [ nix-nrf-dev.nixosModules.default ];
```

Add check that builds `udev-rules`, compares installed rule byte-for-byte with
the pinned OpenOCD contrib file, and verifies destination exists. Do not build
an entire NixOS system in normal flake checks.

### Doctor command module

Add:

- `bin/nix-nrf-doctor` (Python);
- `nix/nix-nrf-doctor.nix` (internal derivation installed at
  `$out/libexec/nix-nrf/doctor`).

Nix module takes:

```nix
{
  pkgs,
  bootstrapCommand,
  ncsVersion ? null,
  udevRules,
}:
```

Wrap with:

- exact bootstrap path in `NIX_NRF_DOCTOR_BOOTSTRAP`;
- configured NCS version when non-null;
- exact udev-rule store path in `NIX_NRF_DOCTOR_UDEV_RULES`;
- `PYTHONHOME`/`PYTHONPATH` unset.

Tests may override source-script roots through environment:

- `NIX_NRF_DOCTOR_SYSFS_ROOT` (default `/sys/bus/usb/devices`);
- `NIX_NRF_DOCTOR_DEV_ROOT` (default `/dev`);
- `NIX_NRF_DOCTOR_SKIP_SDK=1` to isolate hardware fixtures.

Packaged wrapper should not force those testing variables.

### Candidate discovery

Scan immediate directories under sysfs root. Read optional text attributes
without crashing on absent/unreadable files:

- `product`, `manufacturer`, `serial`, `idVendor`, `idProduct`, `busnum`,
  `devnum`.

Candidate recognition uses descriptors, not local VID/PID catalog:

- CMSIS-DAP when product contains `cmsis-dap` case-insensitively;
- J-Link when product contains `j-link`/`jlink` or manufacturer contains
  `segger` case-insensitively.

Deduplicate by sysfs device path. Sort by path for deterministic output.

For every candidate collect:

- type (`cmsis-dap` or `j-link`);
- product/manufacturer/serial and VID:PID when present;
- USB node from numeric busnum/devnum;
- all descendant hidraw nodes from `<device>/*:*/hidraw/hidraw*`;
- each node's existence and current read/write accessibility.

Access classification:

- CMSIS-DAP: accessible when at least one hidraw node is read/write; if no
  hidraw node exists, fall back to USB node accessibility and mark fallback.
- J-Link: accessible when USB bus node is read/write.
- Candidate visible but required nodes absent/inaccessible: permission/device
  issue.

Do not open nodes or invoke OpenOCD/J-Link tools.

Overall hardware status:

- no candidates: FAIL (`no supported debug probe visible`);
- candidates but none accessible: FAIL (`probe visible but inaccessible`);
- at least one accessible: PASS; inaccessible additional candidates are WARN.

Print current username/uid and supplementary group names as context. Do not
claim joining `plugdev` alone fixes access; direct node result is authority.

### SDK/toolchain status

When configured NCS version exists and skip flag is not set, run exact internal
bootstrap command:

```text
bootstrap --check --quiet --print-sdk-path
```

- exit 0 + one existing SDK path: PASS and report path;
- nonzero: FAIL and remediation `nix-nrf bootstrap`;
- malformed/multiple path lines: FAIL;
- no configured version (base package): WARN/SKIP, not overall failure;
- `NIX_NRF_DOCTOR_SKIP_SDK=1`: SKIP, not failure.

Doctor never invokes bootstrap without `--check`.

### Output and exit contract

Human mode prints sections:

1. `SDK/toolchain`
2. `User access`
3. `Debug probes`
4. `Remediation` only when needed
5. final `PASS` or `FAIL`

Remediation for node-access failures must include:

```text
NixOS:
  imports = [ nix-nrf-dev.nixosModules.default ];

Other Linux:
  nix build .#udev-rules
  Install result/lib/udev/rules.d/60-openocd.rules using your distribution's
  documented udev procedure, reload rules, then replug probe.
```

Also identify exact packaged rule path from `NIX_NRF_DOCTOR_UDEV_RULES`. Say
OpenOCD should not run as root. Never print a command that executes sudo.

`--json` emits one JSON object only, with stable top-level fields:

```json
{
  "ok": true,
  "sdk": {"status": "pass|fail|skip", "version": null, "path": null, "message": "..."},
  "user": {"uid": 1000, "name": "...", "groups": ["..."]},
  "hardware": {"status": "pass|fail", "message": "...", "candidates": []},
  "remediation": ["..."]
}
```

Each candidate includes `type`, descriptors, `sysfs_path`, `accessible`,
`access_method` (`hidraw`, `usb`, or `none`), and `nodes` array. Each node has
`path`, `kind`, `exists`, `readable`, `writable`.

Exit:

- 0 when SDK is pass/skip and at least one hardware candidate accessible;
- 1 for SDK failure or hardware failure;
- 2 for CLI usage errors.

### Dispatcher and packaging

Extend `nix/nix-nrf.nix`:

- construct one bootstrap module value and share exact path with dispatcher
  and doctor;
- construct doctor with bootstrap command, selected optional version, and
  udev-rules package;
- add `doctor` and `help doctor` cases and top-level help.

Base `packages.nix-nrf` has no NCS default: doctor skips SDK selection but still
diagnoses hardware. Shell-specific `nix-nrf` checks configured selector.

Keep `packages.udev-rules` separate because host configuration consumes it.

### Tests

Add `tests/unit/test_nix_nrf_doctor.py`, stdlib `unittest`, subprocess boundary,
temporary fake sysfs/dev roots, and fake bootstrap command.

Required cases:

1. No candidate -> hardware fail/exit 1.
2. Accessible CMSIS-DAP via hidraw -> pass/exit 0.
3. CMSIS-DAP no hidraw but accessible USB fallback -> pass with fallback.
4. Visible CMSIS-DAP inaccessible nodes -> fail + remediation.
5. Accessible J-Link via USB node -> pass.
6. Mixed accessible/inaccessible candidates -> overall pass plus warning.
7. Missing/unreadable optional attributes do not crash.
8. SDK ready -> pass and exact path.
9. SDK missing -> overall fail + bootstrap remediation; bootstrap invocation
   log proves `--check --quiet --print-sdk-path` only.
10. No configured version and skip mode -> SDK skip.
11. JSON schema/one-object output and deterministic ordering.
12. Human output contains NixOS/generic Linux guidance only when needed and no
    `sudo` command.

Fixture node permission checks must not rely on root semantics. Prefer
injectable/test-only access metadata or monkeypatched pure classifier over
assuming chmod 000 makes `os.access` false in every sandbox. Preserve real
production use of `os.access`.

Wire `checks.doctor-tests` and `checks.udev-rules` into `flake.nix`.

### CI, docs, and live verification

Update normal CI:

- build `.#udev-rules`;
- smoke `nix run .#nix-nrf -- doctor --help` only (no assumption about hosted
  runner USB);
- devshell verifies help;
- flake check runs fixture tests and byte-for-byte rule check.

Update README, CONTRIBUTING, `goals.md`,
`docs/development/clean-bootstrap-versioning-plan.md`, and
`docs/development/nrfutil-backend-status.md`. Mark Phase 4 done only after
fixture gates and one read-only current-host doctor run.

Run current-host:

```bash
nix develop --ignore-environment --command nix-nrf doctor
nix develop --ignore-environment --command nix-nrf doctor --json
```

This is approved read-only inspection. Do not invoke OpenOCD, flash, modify
udev, reload rules, or use sudo. Record candidate/access summary but avoid
committing transient device-node paths if unnecessary.

## Scope

In scope:

- `nix-nrf doctor` read-only SDK + hardware diagnostics.
- Upstream OpenOCD udev-rule relocation package.
- Minimal NixOS module activating packaged upstream rule.
- Fixture tests, CI smoke, docs, current-host read-only validation.

Out of scope:

- Installing/reloading udev rules on host.
- Running as root/sudo or changing groups.
- Opening probes, OpenOCD fingerprinting, flashing, or recovery.
- Custom VID/PID catalog/rules.
- Device-specific firmware checks.
- macOS/Windows diagnostics.

## Verification

```bash
nix fmt
nix flake check -L
nix build -L .#nix-nrf .#udev-rules
nix run .#nix-nrf -- doctor --help
nix develop --ignore-environment --command nix-nrf doctor
nix develop --ignore-environment --command nix-nrf doctor --json
```

Also verify:

- installed rule equals pinned OpenOCD contrib rule;
- `nix flake show` lists `nixosModules.default` and `packages.udev-rules`;
- doctor never invokes mutating bootstrap mode;
- output contains no executable sudo instruction;
- no host state changed.

## Commit and recap

Commit handoff implementation separately:

```text
feat(cli): add hardware access doctor
```

Inspect status/diff/log; stage only phase files. Do not push, merge, amend,
open PR, install/reload udev rules, touch hardware, or add attribution. Return
files, fixture/gate results, current-host read-only result, udev rule provenance,
commit hash/message, blockers/deviations, and explicit no-mutation statement.
