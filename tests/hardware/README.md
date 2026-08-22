# Hardware integration tests

Hardware workflow runs manually on self-hosted `nrf-hardware` runner with
CMSIS-DAP probes and target boards. It identifies probes with `nix-nrf probes`
and flashes nRF5340 and nRF54L15 through the Tcl recipes.

Workflow is `.github/workflows/hardware.yml`. It has no schedule.

## Register a self-hosted runner

Follow [GitHub runner guide](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-github-actions/adding-self-hosted-runners).

1. In `qarnet/nix-nrf-dev`, open Settings, Actions, Runners, then New
   self-hosted runner.
2. Choose Linux x64.
3. Configure runner on dedicated machine and add `nrf-hardware` label:

   ```sh
   ./config.sh --url https://github.com/qarnet/nix-nrf-dev --labels self-hosted,nrf-hardware
   ```

4. Run it as service or interactively.
5. Provide Nix, CMSIS-DAP USB access, and wired nRF5340 and nRF54L15 boards.

## Runner prerequisites

- Install Nix.
- Install NCS `v3.3.0` with nrfutil sdk-manager:

  ```sh
  nrfutil sdk-manager toolchain install --ncs-version v3.3.0
  ```

- Give runner user USB access through `dialout`, `plugdev`, or distribution
  udev rules.
- Connect and power nRF5340 and nRF54L15 boards.

`run.sh` builds all firmware at runtime in four temporary build directories.
It does not use committed HEX fixtures.

## Security

Self-hosted runners can access `GITHUB_TOKEN` and available workflow secrets.

- Anyone with repository write access can change workflow to expose secrets.
  Limit write access to trusted maintainers.
- Fork pull requests do not receive secrets. Maintainer must review before
  manually triggering workflow for fork code.
- Workflow checks out pull request code and runs `tests/hardware/run.sh` on
  machine with physical hardware. Review that script before running untrusted
  code.
- Use dedicated machine isolated from sensitive data.
- Rotate long-lived runner token when machine is retired or compromised.

## What test does

`tests/hardware/run.sh`:

1. Enters Nix shell.
2. Requires XIAO serial `8EE9B3FF` through explicit CMSIS-DAP v2 bulk USB
   using `nix-nrf doctor --json | python3 tests/hardware/preflight_xiao.py
   8EE9B3FF`. Preflight does not run OpenOCD.
3. Enumerates probes and finds nRF5340 and nRF54L15 serials.
4. Builds nRF5340 CPUAPP blinky, nRF5340 CPUNET empty image, nRF54L15 CPUAPP
   blinky, and nRF54L15 FLPR sysbuild bundle.
5. Validates checksums, addresses, and data coverage of every HEX before flash.
6. Flashes distinct nRF5340 app and net images with `allow_recovery 0` and
   checks byte verification.
7. Flashes nRF54L15 blinky and FLPR bundle and checks byte verification.

Test verifies placement and OpenOCD byte verification. It does not verify FLPR
execution, IPC, or heartbeat. It never recovers or mass-erases nRF5340.

## Required hardware

- One CMSIS-DAP probe wired to nRF5340, such as Pico Debugprobe or picoprobe.
- One CMSIS-DAP probe wired to nRF54L15, such as Seeed XIAO nRF54L15 with
  built-in CMSIS-DAP.
- USB access to both probes from runner machine.
