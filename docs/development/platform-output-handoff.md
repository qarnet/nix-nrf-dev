# Supported-platform output contract handoff

## Goal

Make flake output set match repository's implemented host support:
`x86_64-linux` only. Remove broken/unproven default-system outputs and add
cross-system evaluation to CI so unsupported outputs cannot silently return.

## Why this shape is decided

- Root currently uses `flake-utils.lib.eachDefaultSystem`, exposing
  `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, and `aarch64-darwin`.
- `nix flake check --all-systems --no-build --show-trace` currently fails at
  `packages.x86_64-darwin.default`: pinned Nixpkgs 26.11 dropped
  `x86_64-darwin`.
- `packages.aarch64-darwin.default` fails because OpenOCD wrapper closes over
  Linux-only `pkgs.systemd`.
- `packages.aarch64-linux.west-zephyr-sdk-v3_3_0` fails by explicit assertion in
  `nix/backends/west/zephyr-sdk.nix`; west supports only `x86_64-linux`.
- `docs/development/clean-bootstrap-versioning-plan.md` lines 528-538 explicitly
  leave macOS expansion and Linux ARM64 toolchain installation out of scope.
- README, clean-room proofs, west backend, hardware flow, udev behavior, and CI
  are all Linux x86_64 grounded. No tested non-x86_64-linux public contract
  exists.

Therefore do not repair or retain speculative partial outputs. Publish only
implemented platform. Future platform expansion must add implementation,
metadata, and proof before adding system to list.

## Scope

### In scope

- Define one root `supportedSystems = [ "x86_64-linux" ];` binding in
  `flake.nix`.
- Replace root `eachDefaultSystem` with `flake-utils.lib.eachSystem
  supportedSystems`.
- Change template from `eachDefaultSystem` to explicit
  `eachSystem [ "x86_64-linux" ]`, so generated consumer does not reference
  absent `nix-nrf-dev.lib.<unsupported-system>` outputs.
- Update stale `eachDefaultSystem` comments in
  `nix/flake/per-system.nix` and `docs/development/architecture.md`.
- State repository host support clearly near README introduction/install
  guidance and in public-output table: current flake outputs are
  `x86_64-linux` only; macOS and Linux ARM64 remain unsupported.
- Add CI evaluation gate `nix flake check --all-systems --no-build -L` before
  normal building `nix flake check -L`.
- Keep current-system full check and template-init behavior.

### Out of scope

- macOS support, Linux ARM64 toolchain support, cross compilation, Rosetta, or
  repairing Darwin OpenOCD wrapping.
- Adding Zephyr SDK assets for another architecture.
- Changing nrfutil, OpenOCD, west, udev, NixOS module, command, or shell behavior
  on `x86_64-linux`.
- Adding new flake inputs or testing dependencies.
- Building foreign-system derivations.

## Exact implementation

Reshape root `outputs` body minimally:

```nix
outputs = inputs@{ self, nixpkgs, flake-utils, treefmt-nix, git-hooks, ... }:
  let
    supportedSystems = [ "x86_64-linux" ];
  in
    flake-utils.lib.eachSystem supportedSystems (
      system: import ./nix/flake/per-system.nix { ... }
    )
    // { ... };
```

Exact argument spelling may retain current destructuring rather than `inputs@`;
key contract is one root list passed to `eachSystem`. Do not export
`supportedSystems` publicly in this phase; adding a new public API is not needed
to fix output shape.

Template should use:

```nix
flake-utils.lib.eachSystem [ "x86_64-linux" ] (system: { ... })
```

Template intentionally duplicates one literal because it is copied into an
independent consumer repository and cannot safely reference root's private let
binding.

In `.github/workflows/ci.yml`, Flake check step should run both commands in
order:

```yaml
run: |
  nix flake check --all-systems --no-build -L
  nix flake check -L
```

First command proves every published system output evaluates; second realizes
normal checks. Do not use `--no-build` for second command.

Do not alter `nixosModules.default` in this phase. NixOS module behavioral
evaluation remains separate planned coverage.

## Verification

Run:

```sh
nix flake check --all-systems --no-build -L
nix eval .#packages --apply builtins.attrNames --json
nix eval .#lib --apply builtins.attrNames --json
nix eval .#checks --apply builtins.attrNames --json
nix eval .#devShells --apply builtins.attrNames --json
nix flake check -L
```

Each attr-name command must return exactly `["x86_64-linux"]`.

Then exercise template through same public path as CI, using temp directory and
local override. This writes only under `/tmp`:

```sh
repo="$PWD"
rm -rf /tmp/nix-nrf-platform-template-test
mkdir -p /tmp/nix-nrf-platform-template-test
nix flake init -t "path:$repo" /tmp/nix-nrf-platform-template-test
nix flake check -L /tmp/nix-nrf-platform-template-test \
  --override-input nix-nrf-dev "path:$repo"
```

If installed Nix syntax does not accept target path on `flake init` or flake
path before flags, use CI's proven `cd /tmp/...` command shape instead; do not
change test meaning.

## Acceptance

- Pre-change `--all-systems --no-build` failure is captured in phase evidence.
- Post-change command exits 0.
- `packages`, `lib`, `checks`, and `devShells` expose only `x86_64-linux`.
- Normal full flake check still passes.
- Generated template evaluates and enters its shell through local root override
  on x86_64-linux.
- README and architecture no longer imply default-system support.
- No backend/runtime behavior changes.

## Executor instructions

Implement exactly this platform-contract phase. Stop and escalate instead of
adding unsupported-platform hacks, weakening evaluation, or expanding scope.
After verification, inspect `git status`, `git diff`, and recent log; stage only
intended files and commit with concise conventional message. Do not push,
amend, open PR, or add agent attribution. Return files changed, exact command
results, commit hash/message, blockers, deviations, and suggested follow-up.
