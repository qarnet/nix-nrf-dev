# Hardware integration tests

This directory contains hardware integration tests for nix-nrf-dev, run on a
self-hosted GitHub Actions runner with CMSIS-DAP probes and nRF target boards
attached. The tests verify the full flashing workflow end-to-end on real
hardware: probe identification via `nix-nrf probes`, and flashing both nRF5340
and nRF54L15 via the TCL recipes.

The workflow lives at `.github/workflows/hardware.yml` and is triggered:
- manually via `workflow_dispatch` (GitHub Actions UI → Run workflow), and
- nightly via `schedule` once uncommented in the workflow file.

It runs on a self-hosted runner with the `nrf-hardware` label.

## Registering a self-hosted runner

Follow GitHub's official guide: <https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-github-actions/adding-self-hosted-runners>

Steps summary:

1. Go to **github.com → qarnet/nix-nrf-dev → Settings → Actions → Runners
   → New self-hosted runner → New self-hosted runner**.
2. Choose Linux, x64.
3. Download the runner archive, extract it, configure it on the dedicated
   machine at your desk.
4. During configuration, assign the label `nrf-hardware` (in addition to the
   default `self-hosted` label):
   ```sh
   ./config.sh --url https://github.com/qarnet/nix-nrf-dev --labels self-hosted,nrf-hardware
   ```
5. Install the runner as a service (recommended) or run it interactively.
6. The runner must have:
   - Nix installed (so `cachix/install-nix-action` can configure it, or pre-installed).
   - USB access to the CMSIS-DAP probes (user in the `dialout` or `plugdev`
     group, or udev rules granting access — see your distro's USB serial
     permissions guide).
   - The nRF5340 and nRF54L15 boards wired to probes, powered, and accessible.

## Runner prerequisites

The self-hosted runner must have:

- **Nix installed** (so `cachix/install-nix-action` can configure it, or
  pre-installed via the Determinate Nix Installer).
- **NCS v3.3.0 installed** via nrfutil sdk-manager:
  ```sh
  nrfutil sdk-manager toolchain install --ncs-version v3.3.0
  ```
  The dev shell's `west` wrapper loads this toolchain when building the
  samples. Without it, `west build` fails with a clear message.
- **USB access to CMSIS-DAP probes** (user in the `dialout` or `plugdev`
  group, or udev rules granting access — see your distro's USB serial
  permissions guide).
- The nRF5340 and nRF54L15 boards wired to probes, powered, and accessible.

No prebuilt firmware hexes are committed to the repo — `run.sh` builds all
artifacts from NCS at runtime (four separate clean build dirs, removed on
exit) and flashes them via our openocd-master + TCL recipes.

## Security notes

Self-hosted runners have access to the repository's `GITHUB_TOKEN` and any
secrets available to the workflow. This has implications:

- **Anyone with write access to the repo can read secrets** by editing the
  workflow file to exfiltrate them. Restrict write access to trusted
  maintainers only.
- **Forked pull requests cannot access secrets** — GitHub withholds secrets
  from fork PR runs, so the hardware workflow will not run on fork PRs unless
  manually triggered by a maintainer after review.
- **Run untrusted code cautiously**: the hardware workflow checks out the PR's
  code and runs `tests/hardware/run.sh` on a machine with physical hardware
  access. Do not run this workflow on untrusted forks without reviewing the
  `run.sh` changes first.
- **Dedicated machine recommended**: run the self-hosted runner on a machine
  isolated from sensitive data, since CI jobs run arbitrary repo code on it.
- The runner registers a long-lived token; rotate it if the machine is
  decommissioned or compromised (GitHub Settings → Actions → Runners → Remove).

## What the tests do

`tests/hardware/run.sh` runs on the self-hosted runner:

1. Enter the nix dev shell (`nix develop`).
2. Run `nix-nrf probes` and assert the table shows the expected nRF5340 and
   nRF54L15 targets.
3. Run `nix-nrf probes --find nrf53` and `nix-nrf probes --find nrf54l` to
   capture probe serials.
4. Build four runtime artifacts from NCS (each in its own `mktemp` dir,
   all removed on exit):
   - nRF5340 CPUAPP blinky (`nrf5340dk/nrf5340/cpuapp`);
   - nRF5340 CPUNET empty image (`nrf5340dk/nrf5340/cpunet`, official NCS
     `samples/basic/empty`);
   - XIAO nRF54L15 CPUAPP blinky (`xiao_nrf54l15/nrf54l15/cpuapp` — the
     existing normal app proof);
   - XIAO nRF54L15 FLPR sysbuild bundle (`xiao_nrf54l15/nrf54l15/cpuflpr`,
     official NCS `samples/basic/empty`), whose `domains.yaml` must declare
     both the `empty` (FLPR) and `vpr_launcher` (CPUAPP) domains.
5. Validate every hex against its required address layout with a stdlib
   Python Intel HEX parser (checksums, extended segment/linear records,
   per-region byte counts, out-of-region byte rejection) before any flash
   write:
   - CPUAPP: `[0x00000000, 0x00100000)`;
   - CPUNET: `[0x01000000, 0x01040000)`;
   - FLPR bundle: CPUAPP launcher `[0x00000000, 0x00165000)` plus FLPR RRAM
     `[0x00165000, 0x0017D000)`.
   Every listed region must contain at least one data byte. This catches the
   original defect where the CPUAPP-only image was passed as both the app and
   net image, making the net-core claim a false positive.
6. Flash the nRF5340 via `tcl/nrf53_flash.tcl` `flash_both` with the distinct
   CPUAPP and CPUNET hexes and `allow_recovery 0` (the harness is authorized
   to flash but never to recover or mass erase — a locked app core aborts the
   run), assert the log has no `no flash bank found` warning, and assert byte
   verification of both cores (exact `Verified app core:` / `Verified net
   core:` lines).
7. Flash the nRF54L15 blinky via `tcl/nrf54l_flash.tcl` (existing normal app
   proof).
8. Flash the nRF54L15 FLPR bundle via `tcl/nrf54l_flash.tcl`, asserting the
   exact `Verified image: <bundle>` byte-verification line.
9. Assert each step exits 0.

Each OpenOCD invocation is captured to a per-step temporary log (removed on
exit) so a failure surfaces the exact OpenOCD evidence.

**Explicit limit:** this phase proves *flashability* — that distinct
CPUAPP/CPUNET images exist at the correct address spaces and that the official
FLPR payload lives at the FLPR RRAM addresses, with OpenOCD
`load_image` + `verify_image` succeeding byte-for-byte. It does **not** observe
FLPR runtime execution, IPC, or heartbeat; proving runtime FLPR needs
dedicated observable firmware and is separate work. It never runs recovery or
mass erase: `flash_both` is called with `allow_recovery 0`, so a locked
nRF5340 aborts the harness instead of triggering `nrf53_recover`.

## Required hardware

- 1× CMSIS-DAP probe wired to an nRF5340 (e.g., Debugprobe on Pico, or
  picoprobe).
- 1× CMSIS-DAP probe wired to an nRF54L15 (e.g., Seeed Xiao nRF54L15 with
  built-in CMSIS-DAP).
- USB access to both probes from the runner machine.
- No committed firmware fixtures: all hexes are built at runtime by `run.sh`.
