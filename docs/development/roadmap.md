# Roadmap

These are proposals, not commitments. Current behavior lives in source, tests,
CI, and the status documents.

Pure Nix `sdk-nrf` research lives in
[sdk-nrf-feasibility-draft.md](sdk-nrf-feasibility-draft.md). Hybrid west
backend status lives in [west-backend-status.md](west-backend-status.md).

## Near term

- Package `tcl/*.tcl` and consider `nrf-flash` command that combines
  `nix-nrf probes`, recipes, and wrapped OpenOCD.
- Add consumer Cachix hints, automated `flake.lock` refresh, and version-keyed
  SDK or toolchain CI cache. OpenOCD source pin remains manual.
- Add `overlays.default` and system-independent `lib.mkNrfShell pkgs { ... }`
  form to avoid second Nixpkgs evaluation.
- Add west releases and platforms only after hardware and CI tests establish
  support.

## Later

- Add OpenOCD RTT tools, gdb attach guidance, and serial-console helper.
- Add nRF52 recipe and flash CLI integration.
- Document `nrfutil device recover` J-Link fallback for nRF54 and investigate
  nRF54L CTRL-AP recovery for upstream OpenOCD.
- Add initializer profiles after default initializer workflow is established.
- Add `ZEPHYR_BASE` and multilib doctor checks, shell-hook warn-once mode, and
  standalone `packages.nrf-doctor` output.
- Design scheduled version-discovery pull requests and verify sdk-manager
  parallel-install behavior.
- Consider workflow that detects stable `sdk-nrf` tags and opens pull request
  with reviewed west metadata. Initializer will not query GitHub at runtime.
