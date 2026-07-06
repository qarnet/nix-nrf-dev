# Hardware integration tests

This directory contains hardware integration tests for nix-nrf-dev, run on a
self-hosted GitHub Actions runner with CMSIS-DAP probes and nRF target boards
attached. The tests verify the full flashing workflow end-to-end on real
hardware: probe identification via `nrf-probes`, and flashing both nRF5340
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
  The dev shell's `west` wrapper loads this toolchain when building blinky.
  Without it, `west build` fails with a clear message.
- **USB access to CMSIS-DAP probes** (user in the `dialout` or `plugdev`
  group, or udev rules granting access — see your distro's USB serial
  permissions guide).
- The nRF5340 and nRF54L15 boards wired to probes, powered, and accessible.

No prebuilt firmware hexes are committed to the repo — `run.sh` builds the
Zephyr blinky sample from NCS at runtime for both targets, then flashes via
our openocd-master + TCL recipes.

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

Once `tests/hardware/run.sh` lands (phase 6), the workflow will:

1. Enter the nix dev shell (`nix develop`).
2. Run `nrf-probes` and assert the table shows the expected nRF5340 and
   nRF54L15 targets.
3. Run `nrf-probes --find nrf53` and `nrf-probes --find nrf54l` to capture
   probe serials.
4. Flash a known-good blinky hex to the nRF5340 via `tcl/nrf53_flash.tcl`.
5. Flash a known-good blinky hex to the nRF54L15 via `tcl/nrf54l_flash.tcl`.
6. Assert each step exits 0.

Until `run.sh` exists, the workflow's `Run hardware integration tests` step
will fail with "No such file or directory" — that's expected. Do not trigger
the workflow until phase 6 is merged and the runner is registered.

## Required hardware

- 1× CMSIS-DAP probe wired to an nRF5340 (e.g., Debugprobe on Pico, or
  picoprobe).
- 1× CMSIS-DAP probe wired to an nRF54L15 (e.g., Seeed Xiao nRF54L15 with
  built-in CMSIS-DAP).
- USB access to both probes from the runner machine.
- Known-good blinky firmware hexes (added in phase 6 under
  `tests/hardware/fixtures/`).
