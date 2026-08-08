# Nightly Latest-NCS Initializer — Phase 6 Implementation Handoff

Status: historical. Phase 6 of
`docs/development/nixos-safety-init-testing-plan.md` was implemented and
accepted on branch `feat/nixos-safety-and-init` (commit `ci(ncs): validate
latest initializer nightly`). This document records the implementation
shape; archived with the accepted plan.

## Goal

Add a scheduled/manual hosted workflow that proves the latest strict-stable NCS
release advertised as remotely installable by the real packaged sdk-manager can
be selected by `init-project`, rendered as a concrete consumer flake, evaluated,
and entered as a non-mutating dev shell. It must never download/install an SDK
or toolchain and must not turn a Nordic service outage into a repository failure.

## Scope

In scope:

- new `.github/workflows/latest-ncs-init.yml`;
- real live nrfutil/sdk-manager index queries only in that workflow;
- independent latest-version calculation and comparison with generated output;
- generated-flake evaluation and dev-shell realization/entry;
- expected read-only bootstrap-not-ready proof under isolated state;
- clear GitHub warning/job-summary pass, fail, and inconclusive outcomes;
- documentation of exact claim and limitations.

Out of scope:

- SDK/toolchain installation, `west` execution, firmware build, hardware access,
  flashing, or host policy mutation;
- normal PR/flake checks contacting Nordic;
- runtime GitHub `sdk-nrf` tag discovery;
- automatic west metadata pull requests (already a future roadmap item);
- silently substituting v3.3.0 or another repository-tested release;
- caching isolated Nordic user state or SDK content.

## Workflow trigger and policy

Create `.github/workflows/latest-ncs-init.yml` with:

- name `Latest NCS initializer`;
- schedule once nightly away from the top of the hour, e.g. `37 2 * * *`;
- `workflow_dispatch`;
- top-level `permissions: { contents: read }` (normal YAML form is fine);
- concurrency group `latest-ncs-init-${{ github.ref }}` with cancellation;
- one `ubuntu-latest` job, `timeout-minutes: 25`;
- existing action versions/pattern: `actions/checkout@v7`,
  `cachix/install-nix-action@v31`, `cachix/cachix-action@v17`, cache `qarnet`;
- no cache action for HOME, NRFUTIL_HOME, NCS source, or toolchain state.

Use a unique path under `${{ runner.temp }}` containing run ID and attempt for
the validation root. Setup actions run with the runner's normal HOME. Validation
steps export:

```text
HOME=<validation-root>/home
NRFUTIL_HOME=<validation-root>/nrfutil-home
```

Create both explicitly. Cleanup the exact unique validation root in an
`if: always()` final step. Never delete a fixed shared path.

## Resolve step

Use one workflow step with `id: resolve` to perform initializer resolution and
an independent real search. It must emit step outputs:

```text
result=pass|inconclusive|failed
resolved=vMAJOR.MINOR.PATCH   # only on pass
```

### Bounded retry

Use at most three attempts for each live operation, with short bounded sleeps
(for example 10 seconds between attempts):

1. `nix run .#init-project -- "$dest" --backend nrfutil --ncs-version latest --non-interactive`
2. independent `nix run .#nrfutil -- sdk-manager search --json --skip-overhead`

The initializer already has a 60-second search timeout. Wrap the independent
search in GNU `timeout 90`. Use one new destination per initializer retry, or
verify a failed invocation left no destination before reuse. Never remove an
unknown caller path.

On failure, classify only Nordic sdk-manager transport/index outages as
retryable/inconclusive. Classification must require sdk-manager/Nordic index
context and one of:

- explicit `Failed to download SDK remote config` / SDK index unavailable;
- DNS/name-resolution failure;
- connection refused/reset/unreachable;
- TLS/transport/request timeout;
- HTTP 5xx;
- command timeout status 124.

Do not classify generic Nix evaluation/build/cache/GitHub failures as Nordic
outages. Do not classify these as inconclusive:

- malformed JSON/schema;
- no stable remotely installable release;
- usage/package/initializer errors;
- generated-output mismatch.

After three retryable outages, set `result=inconclusive`, emit a GitHub
`::warning` annotation, write an **INCONCLUSIVE** summary with attempt count and
last concise diagnostic, and exit the step successfully. No validation steps
run afterward.

Any non-outage error sets `result=failed`, preserves useful logs, writes a
failure detail, and exits nonzero.

### Independent expected release

After initializer success, the independent search JSON must be parsed by a
small Python stdlib here-document in the workflow. Do not import or call the
initializer's parser: this is an independent drift check.

Validate the same installed sdk-manager 1.15.0 required shape:

- top-level object with `entries` list;
- every entry object has string `sdkType`, string `sdkVersion`, string-list
  `tags`, object `sdkStatus` with string `remote`, and list `toolchains`;
- every toolchain object has string `version` and object `status` with string
  `remote`.

Unknown extra fields remain allowed. Select candidates only when:

- `sdkType == "nrf"`;
- version strictly matches `^v[0-9]+\.[0-9]+\.[0-9]+$`;
- SDK remote status is `available`;
- at least one toolchain remote status is `available`;
- normalized individual tags are not exactly `unstable`, `preview`, or `rc`.

Choose numeric semantic max; never trust response order. Empty/no-candidate and
malformed schema are hard failures, not outages.

Parse generated `flake.nix` independently and require exactly one:

```nix
backend = "nrfutil";
ncsVersion = "vMAJOR.MINOR.PATCH";
```

Require generated release equals independently calculated expected release and
the assignment does not contain `latest`. Wrong selection is a hard failure.
Set `result=pass` and `resolved=<release>` only after all checks pass.

## Generated-flake validation steps

Run only when `steps.resolve.outputs.result == 'pass'`.

1. Evaluate current generated project:

   ```sh
   nix flake check -L "path:$dest" \
     --override-input nix-nrf-dev "path:$GITHUB_WORKSPACE"
   ```

2. Before shell entry, require no `$HOME/ncs` and no directory named `zephyr`
   anywhere under isolated HOME.
3. Enter/realize the generated shell against current checkout. Inside it:
   - require `command -v nrfutil`, `nix-nrf`, `openocd`, and `west`;
   - do not invoke `west` (its wrapper may bootstrap);
   - run `nix-nrf bootstrap --check` with captured output;
   - require exit status exactly 1;
   - require `NCS version <resolved> not ready; missing:`;
   - require `no changes made (--check)`.
4. After shell entry, repeat no-`$HOME/ncs` and no-`zephyr`-directory checks.
5. Inspect nrfutil logs when present and reject any actual sdk-manager install
   invocation. Search/list/toolchain-env/config/cache/log creation is allowed;
   SDK source/toolchain installation is not.

Any evaluation, realization, command-presence, expected-status/diagnostic, or
non-mutation failure is a hard workflow failure.

## Summary and annotations

Add an `if: always()` summary step based on resolve output and prior step/job
status:

- **PASS**: name resolved release and state exactly what passed;
- **INCONCLUSIVE**: warning, Nordic index unavailable after bounded retries;
- **FAILED**: identify phase that failed and point to logs.

Supported PASS claim:

> Latest strict-stable NCS release advertised by the real packaged sdk-manager
> was selected, independently verified, rendered into valid Nix, evaluated,
> and entered as a non-mutating shell with expected missing-SDK readiness.

Explicit limitation:

> This does not prove SDK/toolchain download, firmware build, or hardware.

Inconclusive exits success only for bounded Nordic transport/index outages.
Malformed data, wrong selection, generated Nix drift, or mutation remains red.

## Documentation

Update `docs/backends.md` with a short “Nightly latest validation” subsection
covering PASS claim, no-download limitation, and inconclusive-vs-failure policy.
Update `docs/development/architecture.md` workflow/test ownership if needed.
Keep README concise; add only a link/note if it improves public understanding.
Update accepted-plan header only after implementation verification: Phase 6
complete pending review, Phase 7 next.

## Verification

Normal verification must not run a live latest lookup.

```sh
# YAML/action/shell lint through repository hooks:
nix flake check --all-systems --no-build -L
nix flake check -L
git diff --check
```

Also inspect the workflow manually against this handoff and run any safe local
syntax/classifier simulations that do not contact Nordic. Do not dispatch the
workflow, query live latest, bootstrap, or install during implementation.

Confirm:

- normal `ci.yml` remains deterministic and still uses explicit v3.3.0 for its
  generated-project test;
- no SDK/toolchain install command exists in the new workflow;
- only `bootstrap --check` appears;
- no Nordic state cache is configured;
- permissions are read-only;
- `actionlint`, formatting, and shellcheck pass.

## Execution and escalation

Implement without commit or push; return for orchestrator review. Report files,
workflow paths/outcomes, exact retry/classification rules, shell non-mutation
proof, verification results, deviations, and blockers.

Stop and escalate instead of weakening classification or assertions if action
syntax cannot express the decided states, sdk-manager diagnostics contradict
the classifier evidence, shell entry performs mutation, or implementation
would require a live query during normal checks.
