# Development Archive

Completed, superseded, or historical planning documents from
`docs/development/`. These are **historical evidence, not current API or
behavior documentation**: they describe the state of the repository and its
plans at the time they were written, including old source paths and module
layouts that no longer exist. Do not follow their path references as current
architecture.

For current information use:

- `README.md` — public usage, backends, and workspace layout;
- `docs/development/architecture.md` — current repository architecture and
  ownership;
- `docs/development/west-backend-status.md` and
  `docs/development/nrfutil-backend-status.md` — backend status;
- `docs/development/sdk-nrf-feasibility-draft.md` — non-binding future
  direction;
- `docs/development/clean-bootstrap-versioning-plan.md` — accepted bootstrap
  design and phase history.

## Grouped index

Original shell / backend selector:

- `backend-selector-handoff.md` — `mkNrfShell` backend selector evaluation
  gate handoff (superseded by the current dispatcher in `nix/backends/`).
- `phase-1-clean-shell-handoff.md` — scoped toolchain env / clean shell
  handoff (implemented).

nix-nrf CLI / bootstrap / doctor:

- `nix-nrf-cli-plan.md` — nix-nrf CLI phase plan (implemented).
- `nix-nrf-cli-phase-1-handoff.md` — nix-nrf CLI phase 1 (implemented).
- `nix-nrf-cli-phase-2-handoff.md` — nix-nrf CLI phase 2 (implemented).
- `nix-nrf-bootstrap-handoff.md` — nrfutil bootstrap module handoff
  (implemented; see `nix/backends/nrfutil/bootstrap.nix`).
- `nix-nrf-doctor-handoff.md` — doctor command module handoff (implemented;
  see `nix/commands/doctor.nix`).

Clean-room proof:

- `clean-room-build-handoff.md` — clean-room bootstrap/build proof handoff
  (implemented; see `tests/clean-room/run.sh`).

West prototype / public integration:

- `west-backend-environment-handoff.md` — west backend environment prototype
  (superseded by the public `backend = "west"` shell in
  `nix/backends/west/shell.nix`).
- `west-backend-public-integration-handoff.md` — public west backend
  integration handoff (implemented).

Superseded pure sdk-nrf prototype:

- `sdk-nrf-prototype-handoff.md` — pure Nix sdk-nrf prototype plan
  (superseded; current direction is the hybrid west backend, see
  `docs/development/west-backend-status.md`).

Repository refactor phases:

- `repository-refactor-plan.md` — master refactor plan (phases 1-5, all
  implemented; replaced by `docs/development/architecture.md`).
- `repository-refactor-phase-2-handoff.md` — backend separation phase
  (implemented).
- `repository-refactor-phase-3-handoff.md` — shared components and
  deduplication phase (implemented).
- `repository-refactor-phase-4-handoff.md` — documentation and artifact
  cleanup phase (implemented; the archive was created by it).
- `repository-refactor-phase-5-handoff.md` — final architecture verification
  phase (implemented; created `docs/development/architecture.md`).
