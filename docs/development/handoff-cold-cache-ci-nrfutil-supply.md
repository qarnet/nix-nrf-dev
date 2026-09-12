# Handoff: fix cold-cache CI nrfutil supply

## Goal

Fix PR #12 CI failure without hash-only workaround. Make Nix `nrfutil` supply reproducible on fresh GitHub runners.

## Root cause, already confirmed

PR run `34668261245`, job `103484518928`, fails before NCS install, tests, firmware build, or release.

Old locked input:

- Receiver `flake.lock` pins `qarnet/nix-nrf-dev` at `e9d77367e334213417c10fa7a7ded3e9195f78c0`.
- Its `nix/nrfutil-core.nix` labels core as 8.1.1 but fetches mutable URL:
  `https://files.nordicsemi.com/artifactory/swtools/external/nrfutil/executables/x86_64-unknown-linux-gnu/nrfutil`
- Expected hash:
  `sha256-SAD4tx/uwMqvPBQ9KbC3/W8zxqJY2hDmYHQ/DbGJCgs=`
- Fresh runner got:
  `sha256-HPS9HT1k9DprlgLY2OjWR77A0m1Re6cv0VT5VUa1AmA=`

Nix correctly rejects changed upstream bytes. Both Nix-store and NCS caches missed, exposing stale mutable dependency.

`nrfutil-sdk-manager` 1.16.1 workflow download passed checksum. It is separate from failed `nrfutil-core` derivation.

## Scope

Work across:

1. `/home/thomas-workstation/repos/nix-nrf-dev`
2. `/home/thomas-workstation/repos/le-audio-receiver`

Use current `nix-nrf-dev` `main` architecture as baseline:

- `nix/flake/components.nix`
- `nix/backends/nrfutil/`
- `nix/flake/checks/nrfutil.nix`

Then update receiver:

- `flake.lock`
- `flake.nix` only if current `mkNrfShell` API needs explicit compatible arguments.

## Constraints

- Do **not** replace old expected hash with CI `got` hash.
- Do **not** bypass `nix develop`, alter CI cache keys, pin a warm cache, or use `$RUNNER_TEMP` PATH ordering as workaround.
- Do **not** change firmware build, package, release, test-gate, nRF54L15 artifact, or `VERSION` behavior.
- Preserve exact NCS v3.3.0 / toolchain `911f4c5c26` contract.
- Preserve current public `mkNrfShell` behavior needed by receiver builds.

## Important compatibility trap

Current `nix-nrf-dev` packages versioned Nixpkgs archives through:

```nix
pkgs.nrfutil.withExtensions [ "nrfutil-sdk-manager" ]
```

Good immutable-source direction. But:

- receiver follows pinned Nixpkgs 25.11, where nrfutil-sdk-manager is 1.8.0;
- current nix-nrf-dev own unstable pin has 1.15.0;
- receiver CI currently provisions 1.16.1.

Do not blindly update receiver lock to current nix-nrf-dev. Keep 1.16.1, or prove a deliberate replacement satisfies exact toolchain environment contract before changing it.

## Required result

Use versioned, content-pinned Nordic package archives or another immutable controlled source. No mutable `.../executables/.../nrfutil` endpoint.

## Verification

In `nix-nrf-dev`:

```sh
nix build .#nrfutil
nix flake check
```

In receiver after lock/API update:

```sh
nix develop --accept-flake-config --command bash -c \
  'nrfutil sdk-manager toolchain env --ncs-version v3.3.0 --as-script sh | grep -q 911f4c5c26'

nix develop --command bash scripts/test-all.sh
```

Expected canonical result:

```text
Gate complete: 72 PASS / 0 FAIL / 72 TOTAL
```

Push fix branch. Fresh GitHub Actions run must pass tests from empty Nix/NCS caches, then firmware. No release expected because VERSION stays unchanged.

## Stop condition

If immutable 1.16.1 packaging cannot satisfy exact NCS/toolchain contract, stop. Report exact command output and proposed compatibility decision. Do not downgrade silently or land cache-dependent fix.
