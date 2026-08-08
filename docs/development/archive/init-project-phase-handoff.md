# Dynamic Project Initializer — Phase 5 Implementation Handoff

Status: historical. Phase 5 of
`docs/development/nixos-safety-init-testing-plan.md` was implemented and
accepted on branch `feat/nixos-safety-and-init` (commit `feat(init): add
dynamic project initializer`). This document records the implementation
shape; archived with the accepted plan.

## Goal

Replace the static `templates.default` onboarding path with a public
`apps.<system>.init-project` program that safely generates a consumer flake from
explicit runtime inputs. Generated projects always contain a concrete NCS
release, never `latest`.

## Scope

In scope:

- public `nix run ...#init-project -- ...` application;
- dynamic latest-stable resolution through the exact packaged nrfutil for the
  nrfutil backend;
- latest-supported resolution from local west metadata for the west backend;
- collision-safe, symlink-safe project generation;
- deterministic fake-boundary tests and current-checkout generated-flake CI;
- removal of `templates.default` and all live static-template onboarding;
- public and maintainer documentation updates.

Out of scope:

- SDK/toolchain installation or mutable west bootstrap;
- hardware access or host configuration changes;
- interactive prompts, `--force`, overwrite, merge, or update modes;
- Jinja, Cookiecutter, Copier, runtime hooks, or generated-command execution;
- GitHub tag lookup at initializer runtime;
- automatic west metadata generation or pull requests. Record a future roadmap
  item for a workflow that detects new stable `sdk-nrf` tags and opens a PR
  carrying reviewed west metadata, hashes, and tests.

## Grounded current behavior

- `flake.nix` currently publishes `templates.default`; remove it.
- `templates/default` contains only `.envrc` and a hard-coded `flake.nix`.
- `nix/flake/components.nix` is the per-system composition root.
- `nix/flake/per-system.nix` publishes packages, apps/dev shells, library, and
  checks. It currently has a deadnix exclusion only for `templates/`; remove
  that obsolete exclusion/comment with the template.
- `nix/backends/west/versions.nix` is the authoritative supported-release
  metadata. It currently contains `v3.3.0`, but code must compute a semantic
  maximum and must not assume one entry or lexical ordering.
- `nix/commands/default.nix` remains the `nix-nrf` dispatcher. The initializer
  is a separate public flake app, not a new `nix-nrf` subcommand.
- Installed nrfutil 8.2.0 with sdk-manager 1.15.0 emits this search shape for
  `sdk-manager search --json --skip-overhead`:

  ```json
  {
    "alerts": [],
    "entries": [
      {
        "sdkStatus": {"local": "none", "remote": "available"},
        "sdkType": "nrf",
        "sdkVersion": "v3.4.0",
        "tags": ["LTS"],
        "toolchains": [
          {
            "status": {"local": "none", "remote": "available"},
            "version": "v3.4.0"
          }
        ]
      }
    ]
  }
  ```

  Search uses `entries`, not bootstrap/list's `versions` shape.

## Public CLI contract

Executable: `nix-nrf-init-project`, published through
`apps.<system>.init-project`.

```text
nix-nrf-init-project [DESTINATION]
  [--backend nrfutil|west]
  [--ncs-version VERSION|latest]
  [--non-interactive]
```

- `DESTINATION` defaults to `.`.
- `--backend` defaults to `nrfutil`.
- `--ncs-version` defaults to `latest` for both backends:
  - nrfutil resolves latest stable remotely through sdk-manager;
  - west resolves latest stable supported by local `versions.nix` metadata.
- `--non-interactive` is accepted and has no behavior in this non-prompting
  release.
- `argparse.ArgumentParser(allow_abbrev=False)` owns help and usage errors.
  Invalid CLI syntax, backend, version syntax, unsupported explicit west
  releases, and `--force` exit 2.
- No prompts and no overwrite option.
- Success writes no machine data to stdout. It prints one concise stderr line
  naming destination, backend, and resolved concrete NCS release.
- Errors use `init-project: ...` on stderr and leave no generated output.

Valid explicit release syntax is `vMAJOR.MINOR.PATCH` with an optional
prerelease suffix beginning with `-` and containing only ASCII alphanumerics,
dots, and hyphens. Latest selection accepts only strict stable
`vMAJOR.MINOR.PATCH` values with no suffix. Explicit west values must also be
exact keys in `nix/backends/west/versions.nix`; explicit nrfutil values remain
offline and are not checked against the remote index.

## Version resolution

### nrfutil

When selection is `latest`, invoke exactly:

```text
<packaged-nrfutil>/bin/nrfutil sdk-manager search --json --skip-overhead
```

Use `subprocess.run` with argv, captured text streams, and a 60-second timeout.
Never use shell execution or ambient PATH lookup. Any timeout, nonzero exit,
malformed JSON, or malformed required schema aborts before filesystem writes.
Include a concise sdk-manager stderr detail for nonzero failure without silently
falling back.

Validate required schema types while permitting unknown extra fields:

- top-level object with `entries` list;
- each entry has string `sdkType`, string `sdkVersion`, string-list `tags`,
  object `sdkStatus` with string `remote`, and list `toolchains`;
- each toolchain has string `version` and object `status` with string `remote`.

A latest candidate must satisfy all of:

- `sdkType == "nrf"`;
- `sdkVersion` strictly matches `vMAJOR.MINOR.PATCH`;
- `sdkStatus.remote == "available"`;
- at least one toolchain has `status.remote == "available"`;
- lower-cased tags do not contain `unstable`, `preview`, or `rc`.

Do not trust response order. Parse numeric semantic tuples and choose `max`, so
`v3.4.0` beats a chronologically later `v3.3.4`; prerelease entries never win.
If no candidate remains, fail without generating files.

### west

Package the sorted key list from `nix/backends/west/versions.nix` as JSON in
the initializer wrapper. For omitted/`latest`, validate keys and select the
numeric semantic maximum among strict stable keys. Do not invoke nrfutil or
GitHub. For an explicit value, require exact metadata membership. If metadata
has no stable key, fail before writing.

West metadata cannot be replaced with runtime tag/requirements discovery:
each entry owns fixed-output Zephyr SDK URLs/hashes, compiler targets/hashes,
Python, west bootstrap version, requirements, and compatibility constraints.

## Generated project

Add a dedicated implementation area:

```text
nix/init-project/default.nix
nix/init-project/skeleton/flake.nix.in
nix/init-project/skeleton/.envrc
bin/commands/nix-nrf-init-project
```

The generated output contains exactly:

```text
flake.nix
.envrc
```

Use a placeholder template and Python stdlib rendering. Replace backend and
version placeholders with `json.dumps` string literals, require each placeholder
exactly once, and reject unresolved placeholders. The generated flake should be
minimal and avoid a second project-owned Nixpkgs/flake-utils input:

```nix
{
  description = "nRF firmware project";

  inputs.nix-nrf-dev.url = "github:qarnet/nix-nrf-dev";

  outputs = {nix-nrf-dev, ...}: {
    devShells.x86_64-linux.default =
      nix-nrf-dev.lib.x86_64-linux.mkNrfShell {
        backend = "<resolved backend>";
        ncsVersion = "<resolved concrete version>";
        # autoBootstrap = true;
        # packages = [];
        # extraShellHook = "";
      };
  };
}
```

`.envrc` remains `use flake`. Generated files contain no `latest`, no runtime
hooks, and no commands to execute.

## Packaging and flake wiring

`nix/init-project/default.nix` receives exactly:

- `pkgs`;
- `nrfutilPackage`;
- `westVersions`.

Build a public package with `$out/bin/nix-nrf-init-project`; copy the skeleton
under `$out/share/nix-nrf/init-project`; patch the Python shebang; wrap once:

- `--set NIX_NRF_INIT_NRFUTIL <exact nrfutil store executable>`;
- `--set NIX_NRF_INIT_WEST_VERSIONS_JSON <JSON key list>`;
- `--set NIX_NRF_INIT_SKELETON <exact packaged skeleton path>`;
- `--unset PYTHONHOME` and `--unset PYTHONPATH`.

These are internal exact-store configuration, not caller override seams.
Tests substitute `nrfutilPackage` at Nix construction time. Production must
never resolve nrfutil from PATH.

Construct/export `initProject` from `nix/flake/components.nix`. Publish only:

```nix
apps.init-project = {
  type = "app";
  program = "${initProject}/bin/nix-nrf-init-project";
};
```

Do not add a public `packages.init-project` unless Nix requires it (it should
not). Remove `templates.default` and delete `templates/default` in this phase.

## Filesystem safety algorithm

Resolve and validate every CLI/version/template input before creating anything.
Generated names are fixed direct children (`flake.nix`, `.envrc`).

1. Convert destination to an absolute lexical path for checks while retaining
   caller spelling for the success message.
2. Reject any existing symlink component in the destination path, a destination
   symlink, non-directory destination, or missing/non-directory parent for a
   new destination.
3. Use `os.path.lexists` for both target names so dangling symlinks count as
   collisions. Reject all collisions before creating either generated file.
4. Render both complete files into a temporary sibling directory on the same
   filesystem.
5. New destination: atomically rename the completed temporary directory with
   Linux `renameat2(..., RENAME_NOREPLACE)` through Python stdlib `ctypes`.
   This repository supports Linux only; do not use replacing `os.rename`.
6. Existing directory: allow unrelated entries, but install each generated
   file with `os.open(O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o644)`. Track
   only files created by this invocation. On failure, close descriptors and
   remove only those tracked files; preserve every pre-existing entry.
7. Always clean the temporary sibling. Never follow or overwrite a generated
   target symlink. Verify each final target remains directly under the resolved
   destination.

No hook or generated command runs during generation.

## Tests

Add:

```text
tests/fixtures/nrfutil-search.py
tests/unit/test_nix_nrf_init_project.py
nix/flake/checks/init-project.nix
```

The fixture is a deterministic sdk-manager-search fake controlled by test-only
environment, logs JSON argv, and rejects anything other than exact
`sdk-manager search --json --skip-overhead`.

The unit suite must run raw source standalone and the packaged initializer in
`checks.init-project-tests`. The check constructs `nix/init-project/default.nix`
with the fake as `nrfutilPackage` and real west metadata, then executes the
packaged public binary.

Required observable tests:

1. explicit exact nrfutil release succeeds while fake is configured to fail if
   called; generated flake contains concrete version/backend;
2. default and explicit `latest` select semantic maximum stable from unordered
   fake search JSON containing a newer RC/preview, other SDK type, remote-SDK
   unavailable entry, no-remote-toolchain entry, and lower stable versions;
3. SDK remote unavailable yields no candidate and no destination;
4. no remote toolchain yields no candidate and no destination;
5. malformed JSON and each malformed required schema class fail without files;
6. empty/no-stable result fails without files;
7. simulated sdk-manager nonzero/network failure preserves useful diagnostic
   and creates nothing;
8. west omitted/`latest` resolves semantic max from packaged local metadata and
   never invokes fake nrfutil;
9. invalid backend, invalid release syntax, unsupported explicit west release,
   and `--force` exit 2;
10. existing `flake.nix` collision preserves sentinel and creates no `.envrc`;
11. generated-target symlink and destination/parent symlink escape attempts are
    rejected while external sentinel/target stays unchanged;
12. existing unrelated directory is preserved while generated files are added;
13. default destination `.`, `--non-interactive`, help, and success summary;
14. generated file set is exactly `.envrc` and `flake.nix`.

Update `nix/flake/checks/default.nix` and `nix/flake/per-system.nix` to wire
`init-project-tests`.

Update `.github/workflows/ci.yml`: replace static template-init with a safe
script-created temporary root and explicit offline-capable generation:

```sh
nix run .#init-project -- "$dest" \
  --backend nrfutil --ncs-version v3.3.0 --non-interactive
nix flake check -L "path:$dest" --override-input nix-nrf-dev "path:$repo"
nix develop "path:$dest" --override-input nix-nrf-dev "path:$repo" \
  --command sh -ceu 'command -v openocd; command -v nix-nrf; nix-nrf probes --help >/dev/null; nix-nrf bootstrap --help >/dev/null; ! command -v nrf-probes'
```

Use `mktemp -d` plus a quoted cleanup trap; never delete a fixed caller path.
This CI path may evaluate/realize Nix inputs but must not bootstrap Nordic SDKs.

## Documentation migration

Update live docs/config only; leave `docs/development/archive/` historical.

- `README.md`: quick start uses `nix run ...#init-project`, explains latest
  lookup/concrete pin, exact-version offline path, west selection, no overwrite.
- `docs/backends.md`: keep `mkNrfShell`'s concrete-version requirement clear,
  distinguish initializer latest behavior, dynamic nrfutil authority, local
  west metadata, and tested baseline.
- `docs/development/architecture.md`: replace template output with initializer
  app/module/script/check ownership.
- `docs/hardware.md`: replace “template usage” link wording.
- `docs/development/roadmap.md`: replace stale `templates.*` opportunity with
  future initializer profiles and add stable sdk-nrf tag detection + west
  metadata PR automation as non-binding future work.
- `CONTRIBUTING.md`: include `nix/init-project/` in architecture summary and
  relevant verification command where useful.
- `.github/workflows/ci.yml`, `flake.nix`, and `nix/flake/per-system.nix`:
  remove stale template comments/exclusions.
- Search live files for `nix flake init -t`, `templates.default`,
  `templates/default`, and “template usage”; only accepted plan/history may
  describe removed behavior.

Do not remove truthful `v3.3.0` test/support boundaries from west metadata,
dogfood shells, hardware tests, clean-room tests, fixtures, or examples that
explicitly demonstrate concrete `mkNrfShell` configuration.

## Verification

Run all of:

```sh
python3 tests/unit/test_nix_nrf_init_project.py
nix build -L .#checks.x86_64-linux.init-project-tests
nix run .#init-project -- --help

tmp_root="$(mktemp -d)"
dest="$tmp_root/project"
nix run .#init-project -- "$dest" --backend nrfutil \
  --ncs-version v3.3.0 --non-interactive
nix flake check -L "path:$dest" \
  --override-input nix-nrf-dev "path:$PWD"
nix develop "path:$dest" \
  --override-input nix-nrf-dev "path:$PWD" \
  --command sh -ceu 'command -v openocd; command -v nix-nrf; nix-nrf probes --help >/dev/null; nix-nrf bootstrap --help >/dev/null; ! command -v nrf-probes'
rm -rf -- "$tmp_root"

nix flake show
nix flake check --all-systems --no-build -L
nix flake check -L
```

For actual execution, use a trap so temporary cleanup also occurs on failure.
Do not run default/latest against the live Nordic index in normal verification.

## Execution and escalation

Implement this phase without committing or pushing; return for orchestrator
review first. Report files changed, user-visible behavior, tests and exact
results, generated project proof, deviations, blockers, and suggested follow-up.

Stop and escalate instead of inventing architecture if two attempts fail,
repository evidence contradicts this handoff, `renameat2` is unavailable,
generated-flake realization would require SDK/toolchain bootstrap, or scope
must expand. Preserve partial work and provide exact evidence. Do not weaken
tests or safety checks to continue.
