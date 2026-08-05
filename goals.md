# Goals

Roadmap for nix-nrf-dev, based on a gap analysis against established Nix
library-flake conventions and against the practical needs of nRF firmware
development. Three sections: **conventions** (what mature library flakes ship
that we don't), **practical gaps** (project-specific holes), and **power
features** (the roadmap toward "clone and everything works").

Status legend: `[ ]` open · `[x]` done · `[-]` rejected/deferred.

---

## 1. Nix library-flake conventions

### 1.1 `[ ]` Overlay output (`overlays.default`)

**What:** Export an overlay that injects our packages into a consumer's
nixpkgs:

```nix
overlays.default = final: prev: {
  openocd-master = ...;
  openocd-master-unwrapped = ...;
  nrfutil = final.nrfutil.withExtensions [ "nrfutil-sdk-manager" ];
  nix-nrf = ...; # owns the internal probes module; openocd passed in
};
```

**Why:** This is the single most standard output for a flake that exports
packages — git-hooks.nix, treefmt-nix, rust-overlay all ship one. It lets a
consumer add the overlay once and then refer to `pkgs.openocd-master`
anywhere (their own devShells, NixOS configs, packages), with everything
built against *their* nixpkgs instance instead of a second evaluation of
ours. It also composes: overlays stack, `packages.<system>` outputs don't.

**How:** Refactor the `nix/*.nix` files so they take `final`/`prev` (or just
keep taking `pkgs` and call them from the overlay). Keep the existing
`packages.<system>` outputs as thin wrappers over the overlay applied to our
pinned nixpkgs, so nothing breaks for current consumers. Document in the
README that overlay consumers need `config.allowUnfree = true` **and**
`config.segger-jlink.acceptLicense = true` (or equivalent per-package
license handling): the packaged nrfutil derivation unconditionally depends
on `segger-jlink-headless`.

### 1.2 `[ ]` System-independent `lib.mkNrfShell pkgs { ... }`

**What:** Offer `lib.mkNrfShell = pkgs: { ncsVersion, ... }: ...` at
the top level, alongside (not replacing) the current per-system
`lib.${system}.mkNrfShell`. `ncsVersion` stays a required argument in both
forms: every caller selects an NCS release explicitly.

**Why:** Today `mkNrfShell` closes over our own
`import nixpkgs { config.allowUnfree = true; }`. Even when the consumer sets
`inputs.nixpkgs.follows`, they pay a second nixpkgs evaluation (~seconds and
significant memory per system), and their nixpkgs `config` and overlays are
silently ignored. The convention for library flakes is: system-independent
functions take `pkgs` as the first argument; per-system convenience wrappers
are optional sugar. This also makes the function usable from non-flake
contexts and from flake-parts modules.

**How:** `nix/mk-nrf-shell.nix` already takes `pkgs` — the change is mostly
plumbing in `flake.nix`: build openocd-master/nrfutil from the
*given* pkgs (via the overlay from 1.1) and construct `nix-nrf` from them
(the probes command module is owned internally by `nix-nrf`), then export both
forms. Note the
caveat: if the consumer's pkgs lacks `allowUnfree`/SEGGER license acceptance,
the nrfutil construction must degrade gracefully (nixpkgs' nrfutil only
supports Linux; Darwin would need a documented degraded path rather than an
evaluation error).

### 1.3 `[ ]` `nixConfig` cache hints

**What:**

```nix
nixConfig = {
  extra-substituters = [ "https://qarnet.cachix.org" ];
  extra-trusted-public-keys = [ "qarnet.cachix.org-1:<public key>" ];
};
```

**Why:** We build openocd from source (~10 min) and cache it on Cachix, but
consumers only benefit if they configure the substituter manually — most
won't. With `nixConfig` in the flake, Nix prompts first-time users to accept
the cache and then pulls binaries instead of building. This is the
difference between "template init → 10 minute build" and "template init →
30 second download".

**How:** Get the public key from the Cachix cache settings page, add the
block to both `flake.nix` and `templates/default/flake.nix` (template
consumers hit the cold build most). Mention in the README that users on
multi-user Nix installs may need `trusted-users` or to accept the prompt.

### 1.4 `[ ]` Fold package builds into `checks`

**What:** `checks = { formatting; pre-commit; } // packages` (per system),
so `nix flake check` builds every package.

**Why:** Convention and simplification: `nix flake check` becomes the single
local command that validates the repo, and CI's separate "Build packages"
step collapses into the flake-check step (Cachix still caches everything).
Today a broken package build passes `nix flake check` locally and only fails
later in CI.

**How:** One-line change in `flake.nix`; then simplify `ci.yml` (keep the
smoke-run steps — building is not the same as executing).

### 1.5 `[ ]` Tagged releases + CHANGELOG

**What:** Tag semver releases (`v0.1.0`, ...) and maintain a
`CHANGELOG.md`.

**Why:** Flake consumers pin by ref. Without tags their options are "track
main" (breaks under them) or "pin a commit hash" (never updates,
unreadable). `github:qarnet/nix-nrf-dev?ref=v0.1.0` is the standard
middle ground. Since the repo already enforces Conventional Commits via
convco, the changelog is nearly free: `convco changelog` generates it from
history.

**How:** Decide on a starting version (0.1.0 — the API will still move),
generate the changelog with convco, tag. Optionally add a
release-please or convco-based release workflow later; manual tagging is
fine at this size. Document the recommended pin in the README install
section.

### 1.6 `[ ]` Automated flake.lock updates

**What:** A scheduled workflow (e.g. `DeterminateSystems/update-flake-lock`)
that opens a weekly PR bumping `flake.lock`.

**Why:** The nightly CI run catches when upstream *breaks us*, but nothing
ever refreshes our pins — nixpkgs, treefmt-nix, git-hooks.nix drift stale
indefinitely. A weekly bot PR runs the full CI (build + smoke + template
init) against the new pins, so updates are validated before merge. This is
standard hygiene for any published flake.

**How:** New workflow, weekly cron, PRs labeled `dependencies`. The
openocd *source* pin in `nix/openocd-master.nix` is separate and stays
manual (bumping it requires hardware verification per CONTRIBUTING.md) —
state that in the workflow's PR body template.

### 1.7 `[ ]` Stated platform-support matrix

**What:** A README section declaring exactly what works where:

| Platform | openocd-master | nix-nrf probes | nrfutil | mkNrfShell |
|---|---|---|---|---|
| x86_64-linux | yes | yes | yes (Nixpkgs; J-Link included) | full |
| aarch64-linux | yes | yes | yes (Nixpkgs; J-Link included) | full (no multilib) |
| Darwin | builds | untested (sysfs!) | **no** | degraded |

**Why:** Nixpkgs' nrfutil only supports Linux (`x86_64-linux`,
`aarch64-linux`) and its derivation unconditionally pulls
`segger-jlink-headless`; on Darwin the package throws, so a Darwin user
discovers the limit by evaluating the shell. Library flakes state support
up front. Note: `bin/nix-nrf-probes` enumerates probes via `/sys/bus/usb/devices`,
so it is Linux-only at runtime regardless of what builds; either document
that or gate the package to Linux.

**How:** Verify the actual matrix (does `eachDefaultSystem` even succeed on
Darwin today?), write it down, and consider restricting
`flake-utils.lib.eachDefaultSystem` to `eachSystem ["x86_64-linux"
"aarch64-linux"]` if Darwin is not a real target — an honest failure beats a
half-shell.

### 1.8 `[-]` (deferred) Migrate flake-utils → flake-parts

**What:** Replace `flake-utils.lib.eachDefaultSystem` with flake-parts.

**Why:** flake-utils is considered legacy; treefmt-nix and git-hooks.nix
(already inputs here) ship first-class flake-parts modules, which would
remove hand-wiring for the formatter/checks. flake-parts also gives a
principled home for the split between per-system and top-level outputs
needed by 1.1/1.2.

**Why deferred:** Pure churn until the flake grows enough that the wiring
hurts. Revisit when implementing 1.1 + 1.2 — that refactor touches the same
lines, so doing them together may be cheaper.

---

## 2. Practical gaps

### 2.1 `[x]` NixOS module for udev rules (highest impact / lowest effort)

**What:** `nixosModules.default` that installs udev rules granting non-root
access to CMSIS-DAP probes (and our specific probes: Debugprobe on Pico,
Seeed XIAO DAP), e.g.:

```nix
{ nix-nrf-dev, ... }: {
  imports = [ nix-nrf-dev.nixosModules.default ];
  # → services.udev rules for CMSIS-DAP (hidraw + libusb), plugdev/uaccess
}
```

**Why:** Every NixOS user of this flake hits "unable to open CMSIS-DAP
device" until they hand-write udev rules — it is the number-one first-run
failure for probe tooling, and nothing in this repo addresses it. Hardware
tooling in nixpkgs (openocd's `60-openocd.rules`, probe-rs) solves this the
same way. Also directly useful for the self-hosted hardware runner setup.

**How:** Rules based on upstream openocd's contrib rules plus the VID/PIDs
of the supported probes, exposed as both a NixOS module and a raw
`packages.udev-rules` (for non-NixOS distros: `cp` to
`/etc/udev/rules.d/`). Document in README and in
`tests/hardware/README.md`.

**Status (implemented 2026-08):** `nixosModules.default` adds
`packages.udev-rules` — a thin relocation of the pinned OpenOCD
`60-openocd.rules` (byte-for-byte, no repository VID/PID catalog) — to
`services.udev.packages`; no options in the first version. Non-NixOS
remediation is printed by `nix-nrf doctor` (`nix build .#udev-rules` +
distribution udev procedure). Diagnostics/detection live in `nix-nrf doctor`
(see 3.3).

### 2.2 `[ ]` Package the TCL recipes

**What:** A `packages.nrf-tcl` (or similar) derivation installing
`tcl/*.tcl` to `$out/share/nix-nrf-dev/tcl/`, plus an `NRF_TCL_DIR` export
in `mkNrfShell`.

**Why:** Today the recipes are only reachable via the flake source tree —
consumers must write `${inputs.nix-nrf-dev}/tcl/nrf53_flash.tcl` in Nix (and
then somehow get that path into their shell) or copy the files, which forks
them from upstream fixes. The recipes are the crown jewels of this repo
(APPROTECT handling took real hardware debugging); they should be a
first-class, versioned artifact.

**How:** Trivial `runCommand` derivation; wire `NRF_TCL_DIR` into the shell
hook; update README examples to use it. Superseded in spirit by 3.2 (the
flash CLI embeds the recipes), but this is a 20-minute step worth doing
now.

### 2.3 `[ ]` Unit tests for `bin/nix-nrf-probes`

**What:** A pytest suite run as `checks.nix-nrf-probes-tests`, testing the pure
logic against fixtures: sysfs-enumeration parsing, `FWP|`-line parsing of
openocd output, family-signature classification (DPIDR/AP-map → family),
`--find` disambiguation (0 / 1 / many matches → exit 0/1/2), and
table formatting.

**Why:** It's 250 lines of the trickiest code in the repo, currently only
exercised by `--help` in CI and by real hardware on the (not yet active)
self-hosted runner. The classification table (`PART_NAMES`, the AP-IDR
signatures) is exactly the kind of thing a future contributor breaks while
adding nRF52 support. Testing it requires no hardware: inject fake sysfs
trees (tmpdir) and canned openocd stdout.

**How:** Light refactor of `bin/nix-nrf-probes` to make enumeration and openocd
invocation injectable (module-level functions already mostly allow this);
add `tests/unit/test_nrf_probes.py`; wire a `checks` derivation:
`pkgs.runCommand` + `python3.withPackages (ps: [ps.pytest])`. black already
formats the file, so style is covered.

---

## 3. Power features (roadmap)

Ordered by impact. 3.1 is the endgame; 3.2–3.4 pay off immediately.

### 3.1 `[ ]` Nix-native NCS build environment (`sdk-nrf` backend)

**What:** Offer an experimental Nix-native build backend (reserved name
`sdk-nrf`) that does not use `nrfutil sdk-manager` at runtime. Materialize the
NCS west workspace, Zephyr SDK compiler targets, host tools, and Python
environment from fixed Nix inputs. `nix develop` yields a shell where `west
build` works immediately, with inputs pinned in `flake.lock`. `mkNrfShell`
already accepts `backend` (default `"nrfutil"`); `sdk-nrf` is reserved but
rejected at evaluation until this work lands.

**Version direction:** the `sdk-nrf` backend must use version metadata keyed
by NCS release — each entry derives the west manifest, Nordic Zephyr
revision, Zephyr SDK release and targets, Python requirements, and host-tool
versions from that release. The metadata may mark tested releases, but caller
selection stays an explicit, required `ncsVersion` with no default, matching
the current nrfutil backend API.
Supporting multiple releases is a core acceptance criterion; the backend must
not encode v3.3.0 as the sole architecture. v3.3.0 remains the first proof
target because installed source and hardware test evidence exist, not because
the backend is permanently tied to it.

**Why:** This is what would distinguish nix-nrf-dev from "a nice shell
around an imperative installer". Today the toolchain lives in `~/ncs`,
installed manually, version-drifts silently, and differs between the CI
runner, the hardware runner, and each developer. Hermetic toolchains give
bit-reproducible dev environments, trivial version switching per branch
(`ncsVersion` in the flake → checkout a branch, direnv reloads, correct
toolchain), and CI runners with zero manual provisioning.

**How:** Do not repackage Nordic's opaque toolchain bundle. nrfutil and
sdk-manager are closed source, the bundle layout is undocumented, and
redistribution/caching terms for its binary tools need separate review.
Technically unpacking it may be possible, but it is not a maintainable Nix
foundation.

Instead, **adapt patterns from `nix-community/zephyr-nix`** (prior art: versioned
   Zephyr SDK archives, selectable compiler targets, source-derived Python
   env, and fixed west workspaces through `west2nix`). NCS v3.3.0 specifies
   Zephyr SDK 0.17.0 with only `arm-zephyr-eabi` and
   `riscv64-zephyr-elf`, which fits its minimal-target model. Pros:
   principled, smaller closure, nixpkgs host-tool option. Cons: it targets
   upstream Zephyr; NCS needs Nordic's Zephyr fork, full `nrf/west.yml`
   workspace, Nordic Python requirements, blobs, and sysbuild validation on
   real nRF53/54L builds. Borrow architecture, not source code, unless its
   currently absent license file is clarified. `MatthewCroughan/nrf-nix`
   (Apache-2.0, last substantive work in 2023) proves the broad approach for
   NCS v2.1.0 by fetching an sdk-nrf west workspace and combining it with a
   Zephyr SDK and Nix Python environment; use it as prior art, not a current
   dependency.

Closed-source nrfutil prevents rebuilding or maintaining nrfutil itself; it
does **not** prevent a Nix-native NCS build environment because sdk-nrf's west
manifest, Nordic's Zephyr fork, Zephyr SDK archives, and required Python
package index are publicly accessible. Keep the `nrfutil` backend as the
supported default until the `sdk-nrf` backend has hardware-verified parity
(the `tests/hardware/run.sh` blinky build is the acceptance test). This is the
largest work item in this file — expect iteration.

### 3.2 `[ ]` Unified `nrf-flash` CLI

**What:** One command that composes the existing pieces:

```
nrf-flash build/zephyr/zephyr.hex               # auto-detect probe+chip
nrf-flash --chip nrf53 --serial E6635C08 fw.hex  # explicit
nrf-flash --recover --chip nrf53                 # APPROTECT recovery
```

Internally: `nix-nrf probes --find` → select recipe (`nrf53_flash.tcl` /
`nrf54l_flash.tcl`) → invoke wrapped openocd with the right cfg + transport
+ speed incantation.

**Why:** The pieces exist but composing them requires reading the README
and hand-assembling a six-argument openocd command line (the CI TCL-parse
steps show how much boilerplate that is). A single entry point turns the
repo's core value into something a consumer uses daily, makes the probe
policy ("never assume the mapping, always `--find`") the *default* instead
of a documented convention, and gives flash behavior a stable CLI surface
that scripts and CI can rely on while the TCL underneath evolves.

**How:** Python (same conventions as `bin/nix-nrf-probes` — black, wrapped with
openocd on PATH, unset PYTHONHOME/PYTHONPATH). Embed the TCL via the
derivation (subsumes 2.2's `NRF_TCL_DIR` for this use). Chip→(cfg, recipe,
proc) table mirrors `PART_NAMES`. Clear error taxonomy: no probe /
ambiguous probes / locked target (point at `--recover`) / verify failed.
Add to `mkNrfShell` packages and to the hardware integration test.

### 3.3 `[ ]` `nrf-doctor` bootstrap/diagnostic command

**What:** A checklist command that verifies the environment and prints the
exact fix for anything missing:

- NCS SDK and toolchain installed for the pinned `ncsVersion`? → print or
  invoke the explicit `nix-nrf bootstrap` path, which uses
  `nrfutil sdk-manager install <version>` for the `nrfutil` backend.
- udev rules present / probe device nodes accessible? → point at 2.1.
- Probes enumerable? Run `nix-nrf probes`, report.
- `ZEPHYR_BASE` derivable? multilib GCC present for native_sim?

**Why:** Every first-run failure mode currently surfaces as a confusing
downstream error (west wrapper failure, openocd permission error, cryptic
cmake errors). Almost all support burden for a tool like this is
environment triage; a doctor command converts that to self-service. The
shellHook already contains fragments of this logic (ZEPHYR_BASE probing) —
this centralizes it. Becomes *less* necessary as 3.1/2.1 land, so keep it a
thin, honest checklist rather than an auto-fixer.

**How:** Shell or Python script packaged as an internal `nix-nrf` subcommand
module (like the probes module); call it from
`mkNrfShell`'s hook in a "warn once" mode and expose it as
`packages.nrf-doctor`.

**Status (partially landed 2026-08):** the SDK/toolchain and probe-access
subsets are implemented as the internal `nix-nrf doctor` subcommand
(`$out/libexec/nix-nrf/doctor`, read-only; descriptor-based CMSIS-DAP/J-Link
discovery, node-access classification, exact NixOS/generic-Linux udev
remediation, fake-boundary fixture tests in `checks.doctor-tests`). Still
open: `ZEPHYR_BASE`/multilib checks, the shellHook "warn once" mode, and a
standalone `packages.nrf-doctor` output.

### 3.4 `[ ]` Debug & console story (RTT, gdb, serial)

**What:** Round out the dev loop beyond flashing:

- `nrf-rtt [--chip ...]` — start openocd with an RTT server attached
  (`rtt setup` / `rtt server start`) and stream the channel, using
  `nix-nrf probes` for selection.
- A documented/generated openocd gdb config so `west debug` and raw
  `arm-zephyr-eabi-gdb` attach work against our openocd-master, including
  the dual-core nRF5340 case (app vs net core attach).
- A trivial serial-console helper or at least a documented recipe
  (`picocom`/`tio` in the shell + udev-stable device naming).

**Why:** Flash-only tooling covers half the loop; the first thing anyone
does after flashing is look at logs. RTT specifically needs the openocd
session, so it belongs to this repo's competence (nobody else can
coordinate "flash, then keep the session for RTT"). This also feeds the
hardware tests: asserting on RTT output ("blinky started") would upgrade
`tests/hardware/run.sh` from "flash exits 0" to a true end-to-end check —
closing the gap the script itself documents (no LED assertion).

**How:** Extend the TCL with an rtt proc per chip (RAM search ranges
differ), wrap in a small CLI, add `tio` to the default shell packages.
Hardware-verify on both boards.

### 3.5 `[ ]` nRF54L recovery path

**What:** Close the documented "Recovery: NONE" gap for nRF54L:

1. Short term: document the `nrfutil device recover` J-Link fallback and
   install an exact `device` command version through nrfutil's supported
   command interface on demand. It reintroduces the J-Link dependency we
   otherwise avoid, so keep it outside the default shell/bootstrap path.
2. Long term: implement nRF54L CTRL-AP recovery in openocd TCL (research:
   the nRF54L CTRL-AP ERASEALL sequence is documented in the product spec)
   and, if it proves out on hardware, contribute upstream and bump our pin.

**Why:** A locked nRF54L currently means "go find a J-Link", which is the
scariest failure a user of this flake can hit, and it contradicts the
repo's CMSIS-DAP-only value proposition. Even just a reliable, documented
escape hatch materially de-risks adoption; a TCL-native recovery would be a
genuine upstream contribution.

**How:** Start with route 1 (on-demand command install + README). Route 2 is
a hardware research task — do it against a sacrificial board, gate on the
hardware test rig.

### 3.6 `[ ]` nRF52 flash recipe

**What:** `tcl/nrf52_flash.tcl` + wiring into `nix-nrf probes` (signatures
already exist in `PART_NAMES`) and the future `nrf-flash` CLI.

**Why:** Cheapest family to support — upstream openocd has a mature `nrf5`
flash driver and `nrf52_recover`, so the recipe is mostly "use the standard
driver + handle APPROTECT on rev2+ parts". nRF52840 is the most widely
owned Nordic chip (every dongle/DK drawer has one), so this single file
significantly widens who can use the flake. `nix-nrf probes` classifying seven
nRF52 variants it can't flash is a visible loose end.

**How:** Write the recipe following the nrf53 file's structure
(check/recover/flash procs, west-runner integration), add the CI TCL-parse
step, hardware-verify on an nRF52840 DK/dongle, document in README
(including the recovery row: `nrf52_recover` — upstream, proven).

### 3.7 `[ ]` More templates

**What:** Additional `templates.*` variants once the above exists, e.g.
`templates.nrf5340` / `templates.nrf54l15` with a board pre-selected, a
sample `west.yml`, VS Code settings for the scoped-west setup, and a
`scripts/bin/` seed (the shellHook already blesses that path).

**Why:** Low priority, but templates are the top of the funnel — the closer
`nix flake init -t` gets to "west build works with zero edits", the
stronger the first impression. Only worth doing after 3.1 (hermetic
toolchain) since that's what removes the remaining manual step.

**How:** One directory per template under `templates/`; keep `default`
minimal as-is. Extend the CI template-init step to loop over all templates.

---

## Suggested sequencing

| Phase | Items | Rationale |
|-------|-------|-----------|
| 1 — mechanical | 1.3, 1.4, 1.7, 2.2, 1.6 | Hours of work, no design risk, immediate consumer benefit |
| 2 — structure | 1.1, 1.2 (consider 1.8 here), 2.1, 1.5 | The overlay/lib refactor defines the public API; tag v0.1.0 after |
| 3 — robustness | 2.3, 3.3, 3.6 | Tests + doctor + easiest new chip |
| 4 — hermeticity | 3.1 | Evaluate fixed NCS workspace + minimal Zephyr SDK targets now that clean bootstrap from an empty HOME is proven (`tests/clean-room/run.sh`, Phase 3) |
| 5 — daily-driver | 3.2, 3.4, 3.5 | Flash CLI, RTT/debug, recovery — the "powerful" layer |
| 6 — polish | 3.7 | Templates once the zero-edit experience is real |
