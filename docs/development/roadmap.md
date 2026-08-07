# Roadmap

Open, non-binding future direction for nix-nrf-dev. It keeps only open
direction; completed work is recorded in the repository itself (source, tests,
CI) and in the current status documents, not here. Nothing on this page is a
commitment or a support claim.

Status: rough, non-binding. For the pure Nix-native `sdk-nrf` backend research
question — a fully Nix-managed NCS build environment — see
`docs/development/sdk-nrf-feasibility-draft.md`; the hybrid west backend
remains the proven direction in `docs/development/west-backend-status.md`.

## Near-term priorities

- **Flash recipe packaging and CLI**: package `tcl/*.tcl` as a first-class
  artifact (e.g. `NRF_TCL_DIR` in the shell) and consider a single `nrf-flash`
  command composing `nix-nrf probes` + the recipes + wrapped openocd.
- **Release, cache, and update automation**: tagged releases and a changelog;
  `nixConfig` Cachix hints for consumers; automated `flake.lock` refresh
  (openocd source pin stays manual per CONTRIBUTING); version-keyed
  SDK/toolchain CI caching so repeated clean-room work is not fully
  cold-download.
- **Library shape**: overlay output (`overlays.default`) and a
  system-independent `lib.mkNrfShell pkgs { ... }` form so consumers do not
  pay a second Nixpkgs evaluation; NixOS udev module already landed.
- **Broader version/platform coverage**: additional NCS releases in the west
  backend metadata and additional supported platforms only after proof on
  existing hardware and CI.

## Later opportunities

- **Debug/RTT/console**: openocd RTT session tooling, a documented gdb attach
  path (incl. dual-core nRF5340), and a serial-console helper.
- **nRF52 support**: `tcl/nrf52_flash.tcl` plus probes/flash-CLI wiring;
  upstream openocd already ships `nrf52_recover`.
- **nRF54 recovery**: document/install the `nrfutil device recover` J-Link
  fallback; research a TCL-native nRF54L CTRL-AP recovery as a potential
  upstream contribution.
- **Templates**: additional `templates.*` variants (board preselected, sample
  `west.yml`, VS Code settings) once the default template experience is
  proven.
- **Doctor extras**: `ZEPHYR_BASE`/multilib checks, a shellHook "warn once"
  mode, and a standalone `packages.nrf-doctor` output.
- **Automation hygiene**: scheduled version-discovery PRs (needs workflow
  permissions and failure-semantics design); parallel-bootstrap locking
  verification for sdk-manager installs.

Current behavior and proof for what already exists live in
`docs/development/nrfutil-backend-status.md`,
`docs/development/west-backend-status.md`, `docs/development/architecture.md`,
and `tests/clean-room/README.md`.
