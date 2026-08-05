#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# tests/west-backend/run.sh — clean-room proof for the public west backend
# (mutable west workspace + version-local venv, Nix Zephyr SDK), entered
# through the public API: `mkNrfShell { backend = "west"; ncsVersion =
# "v3.3.0"; }`.
#
# Proves end-to-end behavior from an empty, isolated Linux home directory:
#   1. Enter the public west shell (via the flake's public `lib.mkNrfShell`
#      with `backend = "west"`) without inheriting developer state.
#   2. Run `nix-nrf bootstrap --yes` to create the mutable west workspace
#      and version-local venv under the isolated home.
#   3. Re-enter the shell with the same isolated home and prove the scoped
#      `west` wrapper resolves ZEPHYR_BASE/ZEPHYR_SDK_INSTALL_DIR and runs
#      the venv west.
#   4. Build Zephyr basic blinky for xiao_nrf54l15/nrf54l15/cpuapp with
#      sysbuild.
#   5. Verify the resulting ELF artifact and domains.yaml.
#
# This is a REAL multi-gigabyte network setup and build test (west init +
# west update + pip requirements + full sysbuild). It installs into an
# isolated HOME (never the developer's $HOME/ncs) and by default removes
# script-created temporary state on exit. It never flashes hardware.
#
# Environment controls:
#   NIX_NRF_WEST_CLEAN_HOME            optional absolute path; when omitted
#                                       the script creates a directory via
#                                       `mktemp -d -t nix-nrf-west-home-XXXXXXXX`
#   NIX_NRF_WEST_CLEAN_KEEP=1          retain a script-created temporary home
#                                       after the run or on failure for
#                                       diagnosis; any other value cleans it
#                                       on exit. A caller-provided home is
#                                       never removed.
#   NIX_NRF_WEST_MIN_FREE_GIB          optional integer minimum free space on
#                                       the home's filesystem, default 25.
#   NIX_NRF_WEST_ALLOW_OUTSIDE_TMP=1   permit a caller home outside /tmp
#                                       (still subject to the other safety
#                                       rules).
#   NIX_NRF_WEST_DRY_RUN=1             validate preconditions only; print the
#                                       plan and exit without running nix
#                                       develop or any download.
#
# Usage: bash tests/west-backend/run.sh
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

# Public west backend instance: the flake's own public `lib.mkNrfShell` with
# `backend = "west"`. The harness enters it with `nix develop --expr` so no
# dedicated devShell output is needed.
WEST_SHELL_EXPR='let flake = builtins.getFlake (toString ./.); in flake.lib.x86_64-linux.mkNrfShell { backend = "west"; ncsVersion = "v3.3.0"; }'

# NCS release wired into the public west shell instance above.
NCS_VERSION="v3.3.0"
MIN_FREE_GIB="${NIX_NRF_WEST_MIN_FREE_GIB:-25}"
CLEAN_HOME="${NIX_NRF_WEST_CLEAN_HOME:-}"
CREATED_HOME=""

# ── Resolve the clean home ───────────────────────────────────────────────────
if [ -z "$CLEAN_HOME" ]; then
  CLEAN_HOME="$(mktemp -d -t nix-nrf-west-home-XXXXXXXX)"
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
  if [ "${NIX_NRF_WEST_CLEAN_KEEP:-}" = "1" ]; then
    echo "keeping script-created clean home for diagnosis: $CREATED_HOME"
    return 0
  fi
  case "$(basename "$CREATED_HOME")" in
    nix-nrf-west-home-*)
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
  *) fail "home-path" "NIX_NRF_WEST_CLEAN_HOME must be an absolute path: $CLEAN_HOME" ;;
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
    if [ "${NIX_NRF_WEST_ALLOW_OUTSIDE_TMP:-}" != "1" ]; then
      fail "home-path" "clean home outside /tmp requires NIX_NRF_WEST_ALLOW_OUTSIDE_TMP=1: $CLEAN_HOME"
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
    fail "free-space" "NIX_NRF_WEST_MIN_FREE_GIB must be a non-negative integer: $MIN_FREE_GIB"
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
  fail "free-space" "only ${free_gib} GiB free on $mount_point; need at least ${MIN_FREE_GIB} GiB for the workspace download and build"
fi

# ── Dry-run: preconditions only, no download ─────────────────────────────────
if [ "${NIX_NRF_WEST_DRY_RUN:-}" = "1" ]; then
  step "Dry run"
  echo "all preconditions satisfied; would run:"
  echo "  1. nix develop --impure --expr '<public mkNrfShell backend = west>' --ignore-env --set-env-var HOME $CLEAN_HOME (nix-nrf bootstrap --yes: west init + west update + pip requirements)"
  echo "  2. nix develop --impure --expr '<public mkNrfShell backend = west>' --ignore-env --set-env-var HOME $CLEAN_HOME (fresh shell, scoped west wrapper)"
  echo "  3. west build -p always -b xiao_nrf54l15/nrf54l15/cpuapp --sysbuild blinky"
  echo "dry run OK"
  exit 0
fi

# ── Lifecycle 1: cold explicit bootstrap ─────────────────────────────────────
step "Lifecycle 1: cold explicit bootstrap (NCS ${NCS_VERSION})"
echo "selected release: ${NCS_VERSION} (public mkNrfShell backend = west)"

[ -z "$(ls -A "$CLEAN_HOME")" ] || fail "precondition" "clean home not empty before bootstrap"
[ ! -e "$CLEAN_HOME/ncs" ] || fail "precondition" "clean home already contains an ncs directory"
echo "OK: isolated home is empty"

# First entry: isolated HOME with no inherited developer state. Asserts the
# environment, runs the real bootstrap, re-checks read-only, and verifies the
# workspace/venv landed under the isolated home with the Nix Zephyr SDK.
# shellcheck disable=SC2016  # inner script vars expand inside nix develop, not here
nix develop --impure --expr "$WEST_SHELL_EXPR" \
  --ignore-env \
  --set-env-var HOME "$CLEAN_HOME" \
  --set-env-var NIX_NRF_WEST_EXPECTED_HOME "$CLEAN_HOME" \
  --set-env-var NIX_NRF_WEST_EXPECTED_NCS_VERSION "$NCS_VERSION" \
  --command bash -ceu '
    set -euo pipefail
    test "$HOME" = "$NIX_NRF_WEST_EXPECTED_HOME" || { echo "HOME mismatch: $HOME" >&2; exit 1; }
    command -v nix-nrf >/dev/null || { echo "nix-nrf not on PATH" >&2; exit 1; }
    ! command -v nrfutil || { echo "nrfutil must not be on PATH in the west backend" >&2; exit 1; }
    ! command -v nix-nrf-west-setup || { echo "the temporary nix-nrf-west-setup command must not exist" >&2; exit 1; }
    test "$ZEPHYR_TOOLCHAIN_VARIANT" = zephyr || { echo "ZEPHYR_TOOLCHAIN_VARIANT mismatch" >&2; exit 1; }
    case "$ZEPHYR_SDK_INSTALL_DIR" in
      /nix/store/*) ;;
      *) echo "ZEPHYR_SDK_INSTALL_DIR must point into /nix/store: $ZEPHYR_SDK_INSTALL_DIR" >&2; exit 1 ;;
    esac
    case "$ZEPHYR_SDK_INSTALL_DIR" in
      "$HOME"/*) echo "ZEPHYR_SDK_INSTALL_DIR must not point into the clean home" >&2; exit 1 ;;
    esac
    echo "SDK store path: $ZEPHYR_SDK_INSTALL_DIR"
    echo "OK: HOME isolated; backend-aware nix-nrf present; no nrfutil; Nix Zephyr SDK exported"
    t0=$SECONDS
    nix-nrf bootstrap --yes
    echo "bootstrap elapsed: $((SECONDS - t0))s"
    workspace="$(nix-nrf bootstrap --check --print-sdk-path)"
    echo "workspace: $workspace"
    test "$workspace" = "$HOME/ncs/$NIX_NRF_WEST_EXPECTED_NCS_VERSION" || { echo "unexpected workspace: $workspace" >&2; exit 1; }
    test -f "$workspace/.west/config" || { echo "missing .west/config" >&2; exit 1; }
    test -f "$workspace/nrf/west.yml" || { echo "missing nrf/west.yml" >&2; exit 1; }
    test -f "$workspace/zephyr/zephyr-env.sh" || { echo "missing zephyr/zephyr-env.sh" >&2; exit 1; }
    test -x "$workspace/.venv/bin/west" || { echo "missing .venv/bin/west" >&2; exit 1; }
    "$workspace/.venv/bin/west" --version
    "$ZEPHYR_SDK_INSTALL_DIR/arm-zephyr-eabi/bin/arm-zephyr-eabi-gcc" --version | head -1
    "$ZEPHYR_SDK_INSTALL_DIR/riscv64-zephyr-elf/bin/riscv64-zephyr-elf-gcc" --version | head -1
    echo "lifecycle 1 OK"
  '

# ── Lifecycle 2: fresh shell, scoped west wrapper, real build ────────────────
step "Lifecycle 2: fresh shell and real west sysbuild"

# Second independent entry with the same isolated HOME. Proves the scoped
# `west` wrapper resolves the workspace from HOME, requires bootstrap
# readiness, exports ZEPHYR_BASE, and execs the venv west; the real build
# produces the exact artifacts. Never flashes hardware.
# shellcheck disable=SC2016  # inner script vars expand inside nix develop, not here
nix develop --impure --expr "$WEST_SHELL_EXPR" \
  --ignore-env \
  --set-env-var HOME "$CLEAN_HOME" \
  --set-env-var NIX_NRF_WEST_EXPECTED_HOME "$CLEAN_HOME" \
  --set-env-var NIX_NRF_WEST_EXPECTED_NCS_VERSION "$NCS_VERSION" \
  --command bash -ceu '
    set -euo pipefail
    test "$HOME" = "$NIX_NRF_WEST_EXPECTED_HOME" || { echo "HOME mismatch: $HOME" >&2; exit 1; }
    echo "HOME: $HOME"
    ! command -v nrfutil || { echo "nrfutil must not be on PATH in the west backend" >&2; exit 1; }
    echo "OK: second entry, no nrfutil"
    t0=$SECONDS
    west build -p always \
      -b xiao_nrf54l15/nrf54l15/cpuapp \
      --sysbuild \
      -d "$HOME/build/blinky" \
      "$HOME/ncs/$NIX_NRF_WEST_EXPECTED_NCS_VERSION/zephyr/samples/basic/blinky"
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
echo "ALL WEST-BACKEND CLEAN-ROOM TESTS PASSED"
