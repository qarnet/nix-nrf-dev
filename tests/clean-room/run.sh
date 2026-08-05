#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# tests/clean-room/run.sh — clean-room bootstrap and blinky build for
# nix-nrf-dev.
#
# Proves end-to-end behavior from an empty, isolated Linux home directory:
#   1. Enter the project shell without inheriting developer nRF Util/NCS state.
#   2. Run `nix-nrf bootstrap --yes` and install NCS v3.3.0 plus the selected
#      toolchain under the isolated home.
#   3. Re-enter the shell with the same isolated home.
#   4. Prove the shell derives ZEPHYR_BASE from the isolated installation.
#   5. Build Zephyr basic blinky for xiao_nrf54l15/nrf54l15/cpuapp with
#      sysbuild.
#   6. Verify the resulting ELF artifact and domains.yaml.
#
# This is a REAL multi-gigabyte Nordic download and build test. It installs
# into an isolated HOME (never the developer's $HOME/ncs), and by default
# removes script-created temporary state on exit. It never flashes hardware.
#
# Environment controls:
#   NIX_NRF_CLEAN_HOME            optional absolute path; when omitted the
#                                 script creates a directory via
#                                 `mktemp -d -t nix-nrf-clean-home-XXXXXXXX`
#   NIX_NRF_CLEAN_KEEP=1          retain a script-created temporary home after
#                                 the run or on failure for diagnosis; any
#                                 other value cleans it on exit. A
#                                 caller-provided home is never removed.
#   NIX_NRF_CLEAN_MIN_FREE_GIB    optional integer minimum free space on the
#                                 home's filesystem, default 25.
#   NIX_NRF_CLEAN_ALLOW_OUTSIDE_TMP=1
#                                 permit a caller home outside /tmp (still
#                                 subject to the other safety rules).
#   NIX_NRF_CLEAN_DRY_RUN=1       validate preconditions only; print the plan
#                                 and exit without running nix develop or any
#                                 download.
#
# Usage: bash tests/clean-room/run.sh
# Exit codes: 0 = all steps passed; non-zero = the first failing step.
# Runs all Nix commands from the repository root.

set -euo pipefail

fail() {
  echo "FAIL: $1: $2" >&2
  exit 1
}

step() {
  echo ""
  echo "=== $1 ==="
}

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

# NCS release pinned by devShells.clean-env-test in flake.nix. The test never
# installs a different release; sdk-manager remains the runtime authority for
# what the selector resolves to.
NCS_VERSION="v3.3.0"
MIN_FREE_GIB="${NIX_NRF_CLEAN_MIN_FREE_GIB:-25}"
CLEAN_HOME="${NIX_NRF_CLEAN_HOME:-}"
CREATED_HOME=""

# ── Resolve the clean home ───────────────────────────────────────────────────
if [ -z "$CLEAN_HOME" ]; then
  CLEAN_HOME="$(mktemp -d -t nix-nrf-clean-home-XXXXXXXX)"
  CREATED_HOME="$CLEAN_HOME"
  echo "created clean home: $CLEAN_HOME"
else
  echo "caller clean home: $CLEAN_HOME"
fi

# Cleanup runs on every exit (success or failure). Only a script-created home
# is ever removed, and only after its exact path and basename prefix match
# what this script recorded.
cleanup() {
  if [ -z "$CREATED_HOME" ]; then
    echo "caller-provided home left in place (never removed): $CLEAN_HOME"
    return 0
  fi
  if [ "${NIX_NRF_CLEAN_KEEP:-}" = "1" ]; then
    echo "keeping script-created clean home for diagnosis: $CREATED_HOME"
    return 0
  fi
  case "$(basename "$CREATED_HOME")" in
    nix-nrf-clean-home-*)
      if [ "$CREATED_HOME" = "$CLEAN_HOME" ]; then
        echo "removing script-created clean home: $CREATED_HOME"
        rm -rf "$CREATED_HOME"
        return 0
      fi
      ;;
  esac
  echo "WARNING: refusing cleanup of $CREATED_HOME (path or prefix mismatch)" >&2
}
trap cleanup EXIT

# ── Safety validation of the clean home ──────────────────────────────────────
case "$CLEAN_HOME" in
  /*) ;;
  *) fail "home-path" "NIX_NRF_CLEAN_HOME must be an absolute path: $CLEAN_HOME" ;;
esac

[ "$CLEAN_HOME" != "/" ] || fail "home-path" "refusing / as clean home"
[ "$CLEAN_HOME" != "/home" ] || fail "home-path" "refusing /home as clean home"

real_home="$(readlink -f "$HOME" 2>/dev/null || true)"
resolved_home="$(readlink -f "$CLEAN_HOME" 2>/dev/null || true)"
if [ -n "$resolved_home" ] && [ "$resolved_home" = "$real_home" ]; then
  fail "home-path" "clean home equals the current user's HOME: $CLEAN_HOME"
fi
repo_resolved="$(readlink -f "$REPO_ROOT")"
if [ -n "$resolved_home" ] && [ "$resolved_home" = "$repo_resolved" ]; then
  fail "home-path" "clean home equals the repository root: $CLEAN_HOME"
fi

case "$CLEAN_HOME" in
  /tmp/*) ;;
  *)
    if [ "${NIX_NRF_CLEAN_ALLOW_OUTSIDE_TMP:-}" != "1" ]; then
      fail "home-path" "clean home outside /tmp requires NIX_NRF_CLEAN_ALLOW_OUTSIDE_TMP=1: $CLEAN_HOME"
    fi
    ;;
esac

if [ -e "$CLEAN_HOME" ]; then
  [ -d "$CLEAN_HOME" ] || fail "home-path" "clean home exists but is not a directory: $CLEAN_HOME"
  [ -z "$(ls -A "$CLEAN_HOME")" ] || fail "home-path" "caller clean home must be empty: $CLEAN_HOME"
  echo "clean home exists and is empty: $CLEAN_HOME"
else
  mkdir -p "$CLEAN_HOME"
  echo "created caller-provided clean home (not tracked for cleanup): $CLEAN_HOME"
fi

# ── Free-space check (before any download) ───────────────────────────────────
case "$MIN_FREE_GIB" in
  '' | *[!0-9]*)
    fail "free-space" "NIX_NRF_CLEAN_MIN_FREE_GIB must be a non-negative integer: $MIN_FREE_GIB"
    ;;
esac

df_line="$(df -kP "$CLEAN_HOME" | awk 'NR == 2 {print $4, $6}')"
free_kib="$(printf '%s\n' "$df_line" | awk '{print $1}')"
mount_point="$(printf '%s\n' "$df_line" | awk '{print $2}')"
case "$free_kib" in
  '' | *[!0-9]*)
    fail "free-space" "cannot parse df output for $CLEAN_HOME"
    ;;
esac
min_kib=$((MIN_FREE_GIB * 1024 * 1024))
free_gib=$((free_kib / 1024 / 1024))
echo "free space on $mount_point: ${free_gib} GiB (minimum required: ${MIN_FREE_GIB} GiB)"
if [ "$free_kib" -lt "$min_kib" ]; then
  fail "free-space" "only ${free_gib} GiB free on $mount_point; need at least ${MIN_FREE_GIB} GiB for the SDK/toolchain download and build"
fi

# ── Dry-run: preconditions only, no download ─────────────────────────────────
if [ "${NIX_NRF_CLEAN_DRY_RUN:-}" = "1" ]; then
  step "Dry run"
  echo "all preconditions satisfied; would run:"
  echo "  1. nix develop .#clean-env-test --ignore-env --set-env-var HOME $CLEAN_HOME (cold bootstrap of NCS ${NCS_VERSION} + toolchain)"
  echo "  2. nix develop .#clean-env-test --ignore-env --set-env-var HOME $CLEAN_HOME (fresh shell, ZEPHYR_BASE derivation)"
  echo "  3. west build -p always -b xiao_nrf54l15/nrf54l15/cpuapp --sysbuild blinky"
  echo "dry run OK"
  exit 0
fi

# ── Lifecycle 1: cold explicit bootstrap ─────────────────────────────────────
step "Lifecycle 1: cold explicit bootstrap (NCS ${NCS_VERSION})"
echo "selected release: ${NCS_VERSION} (pinned by devShells.clean-env-test)"

[ -z "$(ls -A "$CLEAN_HOME")" ] || fail "precondition" "clean home not empty before bootstrap"
[ ! -e "$CLEAN_HOME/.nrfutil" ] || fail "precondition" "clean home already contains .nrfutil state"
[ ! -e "$CLEAN_HOME/ncs" ] || fail "precondition" "clean home already contains an ncs directory"
echo "OK: isolated home is empty and has neither .nrfutil nor ncs"

# First entry: isolated HOME with no inherited developer state. Asserts the
# environment, runs the real bootstrap, re-checks read-only, and verifies the
# SDK landed under the isolated home with a toolchain.
# shellcheck disable=SC2016  # inner script vars expand inside nix develop, not here
nix develop .#clean-env-test \
  --ignore-env \
  --set-env-var HOME "$CLEAN_HOME" \
  --set-env-var NIX_NRF_EXPECTED_HOME "$CLEAN_HOME" \
  --set-env-var NIX_NRF_EXPECTED_NCS_VERSION "$NCS_VERSION" \
  --command bash -ceu '
    set -euo pipefail
    test "$HOME" = "$NIX_NRF_EXPECTED_HOME" || { echo "HOME mismatch: $HOME" >&2; exit 1; }
    command -v nix-nrf >/dev/null || { echo "nix-nrf not on PATH" >&2; exit 1; }
    command -v nrfutil >/dev/null || { echo "nrfutil not on PATH" >&2; exit 1; }
    command -v west >/dev/null || { echo "west not on PATH" >&2; exit 1; }
    echo "OK: HOME isolated; nix-nrf, nrfutil, west present"
    t0=$SECONDS
    nix-nrf bootstrap --yes
    echo "bootstrap elapsed: $((SECONDS - t0))s"
    sdk_path="$(nix-nrf bootstrap --check --print-sdk-path)"
    echo "sdk path: $sdk_path"
    test "$sdk_path" = "$HOME/ncs/$NIX_NRF_EXPECTED_NCS_VERSION" || { echo "unexpected sdk path: $sdk_path" >&2; exit 1; }
    test -d "$sdk_path/zephyr" || { echo "sdk path has no zephyr/ directory" >&2; exit 1; }
    test -d "$HOME/ncs/toolchains" || { echo "no toolchains directory" >&2; exit 1; }
    [ -n "$(ls -A "$HOME/ncs/toolchains")" ] || { echo "toolchains directory is empty" >&2; exit 1; }
    echo "lifecycle 1 OK"
  '

# ── Lifecycle 2: fresh shell, ZEPHYR_BASE, real build ───────────────────────
step "Lifecycle 2: fresh shell and real west sysbuild"

# Second independent entry with the same isolated HOME. Proves the shell
# derives ZEPHYR_BASE from the isolated installation, that a read-only check
# reports ready without mutation, and that the real build produces the exact
# artifacts. Never flashes hardware.
# shellcheck disable=SC2016  # inner script vars expand inside nix develop, not here
nix develop .#clean-env-test \
  --ignore-env \
  --set-env-var HOME "$CLEAN_HOME" \
  --set-env-var NIX_NRF_EXPECTED_HOME "$CLEAN_HOME" \
  --set-env-var NIX_NRF_EXPECTED_NCS_VERSION "$NCS_VERSION" \
  --command bash -ceu '
    set -euo pipefail
    test "$HOME" = "$NIX_NRF_EXPECTED_HOME" || { echo "HOME mismatch: $HOME" >&2; exit 1; }
    echo "HOME: $HOME"
    test "$ZEPHYR_BASE" = "$HOME/ncs/$NIX_NRF_EXPECTED_NCS_VERSION/zephyr" || { echo "ZEPHYR_BASE mismatch: $ZEPHYR_BASE" >&2; exit 1; }
    test -d "$ZEPHYR_BASE" || { echo "ZEPHYR_BASE is not a directory" >&2; exit 1; }
    echo "ZEPHYR_BASE: $ZEPHYR_BASE"
    sdk_path="$(nix-nrf bootstrap --check --quiet --print-sdk-path)"
    echo "check sdk path: $sdk_path"
    test "$sdk_path" = "$HOME/ncs/$NIX_NRF_EXPECTED_NCS_VERSION" || { echo "unexpected sdk path: $sdk_path" >&2; exit 1; }
    echo "OK: second entry ready without mutation"
    t0=$SECONDS
    west build -p always \
      -b xiao_nrf54l15/nrf54l15/cpuapp \
      --sysbuild \
      -d "$HOME/build/blinky" \
      "$ZEPHYR_BASE/samples/basic/blinky"
    echo "build elapsed: $((SECONDS - t0))s"
    test -s "$HOME/build/blinky/blinky/zephyr/zephyr.elf" || { echo "zephyr.elf missing or empty" >&2; exit 1; }
    test -s "$HOME/build/blinky/domains.yaml" || { echo "domains.yaml missing or empty" >&2; exit 1; }
    echo "artifact OK: $HOME/build/blinky/blinky/zephyr/zephyr.elf"
    echo "artifact OK: $HOME/build/blinky/domains.yaml"
    du -sh "$HOME/ncs"
    du -sh "$HOME/build"
    echo "lifecycle 2 OK"
  '

# ── Summary before cleanup ───────────────────────────────────────────────────
step "Summary before cleanup"
du -sh "$CLEAN_HOME/ncs"
echo ""
echo "ALL CLEAN-ROOM TESTS PASSED"
