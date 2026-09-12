# nrfutil cold-cache CI supply record

## Resolution

Source commit `2e6ac03` adds the repository-owned `nrfutil` composition in
`nix/backends/nrfutil/package.nix`. It combines the consumer's Nixpkgs core
with sdk-manager `1.16.1` from Nordic's versioned archive and fixed Nix hash.

At validation, receiver commit `02d042f` locked that source revision and
removed its local sdk-manager override. GitHub Actions run `34705924687` ran
after exact Nix and NCS cache misses, verified sdk-manager `1.16.1` and
toolchain `911f4c5c26`, passed `72 PASS / 0 FAIL / 72 TOTAL`, then passed the
nRF54L15 firmware job.

This record preserves the original diagnosis, constraints, and verification
boundary for future supply changes.

## Original goal

Fix PR #12 CI failure without hash-only workaround. Make Nix `nrfutil` supply reproducible on fresh GitHub runners.

## Original root cause

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

The receiver's earlier standalone sdk-manager `1.16.1` download passed its
checksum. It was separate from the failed `nrfutil-core` derivation.

## Implementation scope

The fix spans:

1. `/home/thomas-workstation/repos/nix-nrf-dev`
2. `/home/thomas-workstation/repos/le-audio-receiver`

Source implementation used current `nix-nrf-dev` `main` architecture as its
baseline:

- `nix/flake/components.nix`
- `nix/backends/nrfutil/`
- `nix/flake/checks/nrfutil.nix`

Receiver update changed:

- `flake.lock`
- `flake.nix` only if current `mkNrfShell` API needs explicit compatible arguments.

## Constraints

- Do **not** replace old expected hash with CI `got` hash.
- Do **not** bypass `nix develop`, alter CI cache keys, pin a warm cache, or use `$RUNNER_TEMP` PATH ordering as workaround.
- Do **not** change firmware build, package, release, test-gate, nRF54L15 artifact, or `VERSION` behavior.
- Preserve exact NCS v3.3.0 / toolchain `911f4c5c26` contract.
- Preserve current public `mkNrfShell` behavior needed by receiver builds.

## Compatibility diagnosis

Before this fix, source composition used:

```nix
pkgs.nrfutil.withExtensions [ "nrfutil-sdk-manager" ]
```

That delegated the manager version to consumer Nixpkgs. At incident time:

- receiver follows pinned Nixpkgs 25.11, where nrfutil-sdk-manager is 1.8.0;
- nix-nrf-dev's then-current unstable pin had 1.15.0;
- receiver CI required 1.16.1.

Do not blindly update receiver lock to current nix-nrf-dev. Keep 1.16.1, or prove a deliberate replacement satisfies exact toolchain environment contract before changing it.

## Required outcome

Use versioned, content-pinned Nordic package archives or another immutable controlled source. No mutable `.../executables/.../nrfutil` endpoint.

## Validation

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

The source checks, receiver shell and full test gate, and a fresh GitHub
Actions cache-miss run all passed. No release ran because `VERSION` stayed
unchanged and the proof used a non-main dispatch.

## Decision boundary

Do not silently downgrade or land a cache-dependent workaround. If a future
manager change cannot satisfy the exact NCS/toolchain contract, stop and report
the command output with a compatibility decision.
