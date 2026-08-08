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
# Resource telemetry: the script records exact integer KiB values
# for filesystem free space and mutable-path sizes, bootstrap/build elapsed
# seconds, and the realized clean-env-test Nix closure. Telemetry always
# prints to the run logs; when NIX_NRF_CLEAN_TELEMETRY_FILE is set, the
# script writes one Markdown report (absolute path, existing real parent,
# target must not exist in any form — symlinks rejected — and must remain
# outside the clean home). The target is exclusively reserved with Bash
# noclobber during validation, so a caller file is never overwritten; the
# emitter later populates exactly that reserved file. Fields that a
# future-stage checkpoint did not reach are reported as "not available"
# (never zero); zero means a measured empty path only.
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
#                                 home's filesystem, default 25. This is a
#                                 conservative end-to-end free-space guard
#                                 covering SDK source, toolchain, nrfutil
#                                 state, extraction/temp overhead, build
#                                 tree, possible same-filesystem Nix closure
#                                 realization, and safety margin — not a
#                                 measured SDK-only size. It is not lowered
#                                 until at least one complete retained run
#                                 establishes observed peak plus margin.
#   NIX_NRF_CLEAN_ALLOW_OUTSIDE_TMP=1
#                                 permit a caller home outside /tmp (still
#                                 subject to the other safety rules).
#   NIX_NRF_CLEAN_DRY_RUN=1       validate preconditions only; print the plan
#                                 and exit without running nix develop or any
#                                 download.
#   NIX_NRF_CLEAN_TELEMETRY_FILE  optional absolute path for the single
#                                 Markdown telemetry report (no overwrite;
#                                 parent must exist and be a real directory,
#                                 target and parent must not be symlinks; the
#                                 target is exclusively reserved with Bash
#                                 noclobber during validation; must stay
#                                 outside the clean home). Without it,
#                                 telemetry still prints to the run logs.
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

# ── Telemetry helpers ────────────────────────────────────────────────────────
# Print "available-kib mount-point" for the filesystem hosting a path.
fs_free_and_mount() {
  df -kP "$1" 2>/dev/null | awk 'NR == 2 {print $4, $6}'
}

# Print available KiB on the filesystem hosting a path.
fs_free_kib() {
  fs_free_and_mount "$1" | awk '{print $1}'
}

# Print total KiB for a path via du -sk; prints nothing when the path does not
# exist. A measured empty path prints 0.
path_size_kib() {
  if [ -e "$1" ]; then
    du -sk -- "$1" 2>/dev/null | awk '{print $1}' || true
  fi
}

# Human-readable KiB/MiB/GiB for an integer KiB value (C locale decimal point).
human_kib() {
  LC_ALL=C awk -v k="$1" 'BEGIN {
    if (k < 1024) printf "%d KiB", k
    else if (k < 1048576) printf "%.1f MiB", k / 1024
    else printf "%.1f GiB", k / 1048576
  }'
}

# Emit one measurement to the run logs (always). The optional Markdown report
# populates the exact target reserved during validation, once at exit, from
# the recorded globals.
emit_metric() {
  printf 'metric: %s: %s\n' "$1" "$2"
}

# Emit a KiB measurement: exact integer KiB plus human-readable value beside.
emit_kib_metric() {
  if [ "$2" = "not available" ]; then
    emit_metric "$1" "not available"
  else
    emit_metric "$1" "$2 KiB ($(human_kib "$2"))"
  fi
}

# Exclusively reserve the telemetry report target with Bash noclobber. Runs
# only after all path validation passed, so an invalid path never leaves a
# file behind, and a racing creator between validation and reservation is
# rejected instead of overwritten. The emitter later populates exactly this
# reserved file.
reserve_telemetry_file() {
  if ! ( set -o noclobber && : > "$1" ) 2>/dev/null; then
    fail "telemetry" "telemetry target already exists or cannot be exclusively created: $1"
  fi
}

# Read a metrics file written by an inner lifecycle and require a non-negative
# integer (exact command-timing evidence).
read_int_metric() {
  local value
  if [ ! -f "$1" ]; then
    fail "timing" "expected metrics file missing: $1"
  fi
  value="$(<"$1")"
  case "$value" in
    '' | *[!0-9]*)
      fail "timing" "metrics file is not a non-negative integer: $1 (value: '$value')"
      ;;
  esac
  printf '%s\n' "$value"
}

# Minimum/consumed free KiB are computed only from checkpoints actually
# recorded; at least the before-bootstrap checkpoint plus one later checkpoint
# are required, otherwise the fields stay "not available".
compute_free_derived_metrics() {
  local min=""
  local count=0
  local v
  for v in "$FREE_KIB_BEFORE" "$FREE_KIB_AFTER_BOOTSTRAP" "$FREE_KIB_AFTER_BUILD"; do
    if [ "$v" != "not available" ]; then
      count=$((count + 1))
      if [ -z "$min" ] || [ "$v" -lt "$min" ]; then
        min="$v"
      fi
    fi
  done
  if [ "$count" -ge 2 ]; then
    FREE_KIB_MIN="$min"
    CONSUMED_KIB=$((FREE_KIB_BEFORE - FREE_KIB_MIN))
  else
    FREE_KIB_MIN="not available"
    CONSUMED_KIB="not available"
  fi
}

# One report line for a KiB value (integer plus human-readable), or
# "not available" when the checkpoint was not reached.
report_kib_line() {
  if [ "$2" = "not available" ]; then
    printf -- '- %s: not available\n' "$1"
  else
    printf -- '- %s: %s KiB (%s)\n' "$1" "$2" "$(human_kib "$2")"
  fi
}

# Populate the single Markdown telemetry report — the exact target reserved
# during validation — from the recorded globals. Only telemetry functions
# write the report; nothing else touches the target path.
emit_telemetry_report() {
  [ -n "$TELEMETRY_FILE" ] && [ "$TELEMETRY_VALID" = "1" ] || return 0
  {
    echo "# Clean-room telemetry report"
    echo ""
    echo "Exact integer KiB values are the stable evidence, with human-readable"
    echo "MiB/GiB beside them. Fields that a future-stage checkpoint did not reach"
    echo "are \"not available\" (never zero); zero means a measured empty path only."
    echo "The clean-env-test Nix closure is a Nix-store closure, separate from"
    echo "mutable-home disk use under the clean home."
    echo ""
    echo "- result: $RESULT"
    echo "- selected NCS release: $NCS_VERSION"
    echo "- clean home: $CLEAN_HOME"
    echo "- filesystem mount point: $MOUNT_POINT"
    echo "- configured minimum free-space guard: ${MIN_FREE_GIB} GiB"
    report_kib_line "filesystem free KiB before bootstrap" "$FREE_KIB_BEFORE"
    report_kib_line "filesystem free KiB after bootstrap" "$FREE_KIB_AFTER_BOOTSTRAP"
    report_kib_line "filesystem free KiB after build" "$FREE_KIB_AFTER_BUILD"
    report_kib_line "minimum observed free KiB" "$FREE_KIB_MIN"
    report_kib_line "consumed free KiB (before bootstrap to minimum observed)" "$CONSUMED_KIB"
    report_kib_line "NCS path size KiB after bootstrap" "$NCS_KIB_AFTER_BOOTSTRAP"
    report_kib_line "nrfutil path size KiB after bootstrap" "$NRFUTIL_KIB_AFTER_BOOTSTRAP"
    report_kib_line "NCS path size KiB final" "$NCS_KIB_FINAL"
    report_kib_line "nrfutil path size KiB final" "$NRFUTIL_KIB_FINAL"
    report_kib_line "build tree size KiB final" "$BUILD_KIB_FINAL"
    report_kib_line "total clean home size KiB final" "$HOME_KIB_FINAL"
    echo "- bootstrap elapsed seconds: $BOOTSTRAP_ELAPSED_S"
    echo "- build elapsed seconds: $BUILD_ELAPSED_S"
    echo "- clean-env-test Nix closure path (Nix store; separate from mutable-home disk use): $SHELL_CLOSURE_PATH"
    echo "- clean-env-test Nix closure size (nix path-info -Sh): $SHELL_CLOSURE_LINE"
  } > "$TELEMETRY_FILE"
}

# Exit-time telemetry: the COMPLETE measurement schema is printed to the run
# logs on every exit — result, release/home/mount/guard, all free-space
# checkpoint and derived values, all mutable sizes, elapsed seconds, and the
# closure path/line — including "not available" for dry-run/future stages so
# no field is silently omitted even without a telemetry file. Then the
# optional Markdown report populates the exact reserved target. Runs before
# cleanup.
emit_final_telemetry() {
  compute_free_derived_metrics
  emit_metric "result" "$RESULT"
  emit_metric "selected NCS release" "$NCS_VERSION"
  emit_metric "clean home" "$CLEAN_HOME"
  emit_metric "filesystem mount point" "$MOUNT_POINT"
  emit_metric "configured minimum free-space guard" "${MIN_FREE_GIB} GiB"
  emit_kib_metric "filesystem free KiB before bootstrap" "$FREE_KIB_BEFORE"
  emit_kib_metric "filesystem free KiB after bootstrap" "$FREE_KIB_AFTER_BOOTSTRAP"
  emit_kib_metric "filesystem free KiB after build" "$FREE_KIB_AFTER_BUILD"
  emit_kib_metric "minimum observed free KiB" "$FREE_KIB_MIN"
  emit_kib_metric "consumed free KiB (before bootstrap to minimum observed)" "$CONSUMED_KIB"
  emit_kib_metric "NCS path size KiB after bootstrap" "$NCS_KIB_AFTER_BOOTSTRAP"
  emit_kib_metric "nrfutil path size KiB after bootstrap" "$NRFUTIL_KIB_AFTER_BOOTSTRAP"
  emit_kib_metric "NCS path size KiB final" "$NCS_KIB_FINAL"
  emit_kib_metric "nrfutil path size KiB final" "$NRFUTIL_KIB_FINAL"
  emit_kib_metric "build tree size KiB final" "$BUILD_KIB_FINAL"
  emit_kib_metric "total clean home size KiB final" "$HOME_KIB_FINAL"
  emit_metric "bootstrap elapsed seconds" "$BOOTSTRAP_ELAPSED_S"
  emit_metric "build elapsed seconds" "$BUILD_ELAPSED_S"
  emit_metric "clean-env-test Nix closure path (Nix store; separate from mutable-home disk use)" "$SHELL_CLOSURE_PATH"
  emit_metric "clean-env-test Nix closure size (nix path-info -Sh)" "$SHELL_CLOSURE_LINE"
  if [ -n "$TELEMETRY_FILE" ] && [ "$TELEMETRY_VALID" = "1" ]; then
    emit_telemetry_report
  fi
}

# Cleanup runs on every exit (success or failure). Only a script-created home
# is ever removed, and only after its exact path and basename prefix match
# what this script recorded. The script-created metrics directory is removed
# for caller-provided homes too (exact path only) unless the run is retained
# for diagnosis. Every rm -rf failure is returned explicitly so on_exit can
# degrade an otherwise successful run into failure without ever masking an
# existing nonzero status.
cleanup() {
  local rc=0
  if [ "${NIX_NRF_CLEAN_KEEP:-}" = "1" ]; then
    echo "retaining clean-room state at $CLEAN_HOME for diagnosis (NIX_NRF_CLEAN_KEEP=1)"
    return 0
  fi
  if [ -n "$CLEAN_HOME" ] && [ -d "$CLEAN_HOME/.nix-nrf-clean-metrics" ]; then
    echo "removing script-created metrics directory: $CLEAN_HOME/.nix-nrf-clean-metrics"
    rm -rf "$CLEAN_HOME/.nix-nrf-clean-metrics" || rc=1
  fi
  if [ -z "$CREATED_HOME" ]; then
    echo "caller-provided home left in place (never removed): $CLEAN_HOME"
    return "$rc"
  fi
  case "$(basename "$CREATED_HOME")" in
    nix-nrf-clean-home-*)
      if [ "$CREATED_HOME" = "$CLEAN_HOME" ]; then
        echo "removing script-created clean home: $CREATED_HOME"
        rm -rf "$CREATED_HOME" || rc=1
        return "$rc"
      fi
      ;;
  esac
  echo "WARNING: refusing cleanup of $CREATED_HOME (path or prefix mismatch)" >&2
  # Refusal is a cleanup failure: return nonzero so on_exit degrades an
  # otherwise successful run (an earlier rc=1 is also preserved by this).
  return 1
}

on_exit() {
  # Capture the original exit status first. Telemetry/cleanup failure may turn
  # an otherwise successful run into failure, but must never hide an existing
  # nonzero status.
  local status=$?
  local degraded=0
  if ! emit_final_telemetry; then
    echo "WARNING: telemetry emission failed" >&2
    degraded=1
  fi
  if ! cleanup; then
    echo "WARNING: cleanup failed" >&2
    degraded=1
  fi
  if [ "$status" -eq 0 ] && [ "$degraded" -eq 1 ]; then
    status=1
  fi
  exit "$status"
}

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

# NCS release pinned by devShells.clean-env-test in nix/flake/dev-shells.nix.
# The test never installs a different release; sdk-manager remains the
# runtime authority for what the selector resolves to.
NCS_VERSION="v3.3.0"
MIN_FREE_GIB="${NIX_NRF_CLEAN_MIN_FREE_GIB:-25}"
CLEAN_HOME="${NIX_NRF_CLEAN_HOME:-}"
CREATED_HOME=""

# ── Telemetry state (result defaults to failed; dry-run/passed set later) ────
RESULT="failed"
MOUNT_POINT="not available"
FREE_KIB_BEFORE="not available"
FREE_KIB_AFTER_BOOTSTRAP="not available"
FREE_KIB_AFTER_BUILD="not available"
FREE_KIB_MIN="not available"
CONSUMED_KIB="not available"
NCS_KIB_AFTER_BOOTSTRAP="not available"
NRFUTIL_KIB_AFTER_BOOTSTRAP="not available"
NCS_KIB_FINAL="not available"
NRFUTIL_KIB_FINAL="not available"
BUILD_KIB_FINAL="not available"
HOME_KIB_FINAL="not available"
BOOTSTRAP_ELAPSED_S="not available"
BUILD_ELAPSED_S="not available"
SHELL_CLOSURE_PATH="not available"
SHELL_CLOSURE_LINE="not available"
TELEMETRY_FILE="${NIX_NRF_CLEAN_TELEMETRY_FILE:-}"
TELEMETRY_VALID=0

# ── Resolve the clean home ───────────────────────────────────────────────────
if [ -z "$CLEAN_HOME" ]; then
  CLEAN_HOME="$(mktemp -d -t nix-nrf-clean-home-XXXXXXXX)"
  CREATED_HOME="$CLEAN_HOME"
  echo "created clean home: $CLEAN_HOME"
else
  echo "caller clean home: $CLEAN_HOME"
fi

# Telemetry is emitted and cleanup runs on every exit (success or failure),
# with telemetry emitted before cleanup. Only a script-created home is ever
# removed, and only after its exact path and basename prefix match what this
# script recorded.
trap on_exit EXIT

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

# ── Telemetry file validation and reservation ────────────────────────────────
if [ -n "$TELEMETRY_FILE" ]; then
  case "$TELEMETRY_FILE" in
    /*) ;;
    *) fail "telemetry" "NIX_NRF_CLEAN_TELEMETRY_FILE must be an absolute path: $TELEMETRY_FILE" ;;
  esac
  telemetry_parent="$(dirname "$TELEMETRY_FILE")"
  # Parent must be an existing real directory; symlinked parents are rejected.
  if [ ! -d "$telemetry_parent" ]; then
    fail "telemetry" "telemetry parent must be an existing directory: $telemetry_parent"
  fi
  if [ -L "$telemetry_parent" ]; then
    fail "telemetry" "telemetry parent must not be a symlink: $telemetry_parent"
  fi
  # Target must not exist in any form: regular file, symlink to an existing
  # file, or dangling symlink (no overwrite, never write through a symlink).
  if [ -e "$TELEMETRY_FILE" ] || [ -L "$TELEMETRY_FILE" ]; then
    fail "telemetry" "telemetry target already exists (no overwrite; symlinks rejected): $TELEMETRY_FILE"
  fi
  case "$TELEMETRY_FILE" in
    "${CLEAN_HOME%/}"/*)
      fail "telemetry" "telemetry target must be outside the clean home: $TELEMETRY_FILE"
      ;;
  esac
  # Symlink-safe: also reject a target that resolves inside the clean home.
  resolved_telemetry="$(readlink -f "$TELEMETRY_FILE" 2>/dev/null || true)"
  resolved_clean_home="$(readlink -f "$CLEAN_HOME" 2>/dev/null || true)"
  if [ -n "$resolved_telemetry" ] && [ -n "$resolved_clean_home" ]; then
    case "$resolved_telemetry" in
      "$resolved_clean_home"/*)
        fail "telemetry" "telemetry target resolves inside the clean home: $TELEMETRY_FILE"
        ;;
    esac
  fi
  # Exclusively reserve the target now; only this invocation may populate it.
  reserve_telemetry_file "$TELEMETRY_FILE"
  TELEMETRY_VALID=1
  echo "telemetry report reserved: $TELEMETRY_FILE"
fi

emit_metric "selected NCS release" "$NCS_VERSION"
emit_metric "clean home" "$CLEAN_HOME"

# ── Free-space check (checkpoint 1: before-bootstrap measurement and guard) ──
case "$MIN_FREE_GIB" in
  '' | *[!0-9]*)
    fail "free-space" "NIX_NRF_CLEAN_MIN_FREE_GIB must be a non-negative integer: $MIN_FREE_GIB"
    ;;
esac

df_line="$(fs_free_and_mount "$CLEAN_HOME")"
case "$df_line" in
  '') fail "free-space" "cannot parse df output for $CLEAN_HOME" ;;
esac
FREE_KIB_BEFORE="$(printf '%s\n' "$df_line" | awk '{print $1}')"
MOUNT_POINT="$(printf '%s\n' "$df_line" | awk '{print $2}')"
case "$FREE_KIB_BEFORE" in
  '' | *[!0-9]*)
    fail "free-space" "cannot parse df output for $CLEAN_HOME"
    ;;
esac
emit_metric "filesystem mount point" "$MOUNT_POINT"
emit_metric "configured minimum free-space guard" "${MIN_FREE_GIB} GiB"
emit_kib_metric "filesystem free KiB before bootstrap" "$FREE_KIB_BEFORE"
min_kib=$((MIN_FREE_GIB * 1024 * 1024))
free_gib=$((FREE_KIB_BEFORE / 1024 / 1024))
echo "free space on $MOUNT_POINT: ${free_gib} GiB (minimum required: ${MIN_FREE_GIB} GiB)"
if [ "$FREE_KIB_BEFORE" -lt "$min_kib" ]; then
  fail "free-space" "only ${free_gib} GiB free on $MOUNT_POINT; need at least ${MIN_FREE_GIB} GiB for the SDK/toolchain download and build"
fi

# ── Dry-run: preconditions only, no download ─────────────────────────────────
if [ "${NIX_NRF_CLEAN_DRY_RUN:-}" = "1" ]; then
  RESULT="dry-run"
  step "Dry run"
  echo "all preconditions satisfied; would run:"
  echo "  1. nix develop .#clean-env-test --ignore-env --set-env-var HOME $CLEAN_HOME (cold bootstrap of NCS ${NCS_VERSION} + toolchain)"
  echo "  2. nix develop .#clean-env-test --ignore-env --set-env-var HOME $CLEAN_HOME (fresh shell, ZEPHYR_BASE derivation)"
  echo "  3. west build -p always -b xiao_nrf54l15/nrf54l15/cpuapp --sysbuild blinky"
  echo "  4. nix build --no-link --print-out-paths .#devShells.x86_64-linux.clean-env-test (realize fixed closure; no Nordic download)"
  echo ""
  echo "expanded telemetry plan (checkpoints recorded on a real run):"
  echo "  checkpoint 1: filesystem free KiB before bootstrap, mount point, minimum free-space guard"
  echo "  checkpoint 2: after bootstrap — free KiB, NCS and nrfutil path sizes, bootstrap elapsed seconds"
  echo "  checkpoint 3: after build — free KiB, final NCS/nrfutil/build-tree/total-home sizes"
  echo "  checkpoint 4: realized clean-env-test Nix closure path and nix path-info -Sh size (Nix store only)"
  echo "  derived: minimum observed free KiB and consumed free KiB from recorded checkpoints"
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

METRICS_DIR="$CLEAN_HOME/.nix-nrf-clean-metrics/bootstrap"
mkdir -p "$METRICS_DIR"

# First entry: isolated HOME with no inherited developer state. Asserts the
# environment, runs the real bootstrap, re-checks read-only, and verifies the
# SDK landed under the isolated home with a toolchain. The inner script
# records the exact bootstrap elapsed seconds (epoch seconds around the
# `nix-nrf bootstrap --yes` command only) to the metrics directory provided
# via the environment; the outer script validates and reads that integer.
# shellcheck disable=SC2016  # inner script vars expand inside nix develop, not here
nix develop .#clean-env-test \
  --ignore-env \
  --set-env-var HOME "$CLEAN_HOME" \
  --set-env-var NIX_NRF_EXPECTED_HOME "$CLEAN_HOME" \
  --set-env-var NIX_NRF_EXPECTED_NCS_VERSION "$NCS_VERSION" \
  --set-env-var NIX_NRF_CLEAN_METRICS_DIR "$METRICS_DIR" \
  --command bash -ceu '
    set -euo pipefail
    test "$HOME" = "$NIX_NRF_EXPECTED_HOME" || { echo "HOME mismatch: $HOME" >&2; exit 1; }
    command -v nix-nrf >/dev/null || { echo "nix-nrf not on PATH" >&2; exit 1; }
    command -v nrfutil >/dev/null || { echo "nrfutil not on PATH" >&2; exit 1; }
    command -v west >/dev/null || { echo "west not on PATH" >&2; exit 1; }
    echo "OK: HOME isolated; nix-nrf, nrfutil, west present"
    t0=$(date +%s)
    nix-nrf bootstrap --yes
    elapsed=$(( $(date +%s) - t0 ))
    echo "bootstrap elapsed: ${elapsed}s"
    printf "%s\n" "$elapsed" > "$NIX_NRF_CLEAN_METRICS_DIR/elapsed"
    sdk_path="$(nix-nrf bootstrap --check --print-sdk-path)"
    echo "sdk path: $sdk_path"
    test "$sdk_path" = "$HOME/ncs/$NIX_NRF_EXPECTED_NCS_VERSION" || { echo "unexpected sdk path: $sdk_path" >&2; exit 1; }
    test -d "$sdk_path/zephyr" || { echo "sdk path has no zephyr/ directory" >&2; exit 1; }
    test -d "$HOME/ncs/toolchains" || { echo "no toolchains directory" >&2; exit 1; }
    [ -n "$(ls -A "$HOME/ncs/toolchains")" ] || { echo "toolchains directory is empty" >&2; exit 1; }
    echo "lifecycle 1 OK"
  '

BOOTSTRAP_ELAPSED_S="$(read_int_metric "$METRICS_DIR/elapsed")"
emit_metric "bootstrap elapsed seconds" "$BOOTSTRAP_ELAPSED_S"

# ── Checkpoint 2: free space and mutable state after bootstrap ──────────────
step "Checkpoint 2: free space and mutable state after bootstrap"
FREE_KIB_AFTER_BOOTSTRAP="$(fs_free_kib "$CLEAN_HOME")"
case "$FREE_KIB_AFTER_BOOTSTRAP" in
  '' | *[!0-9]*)
    fail "free-space" "cannot parse df output for $CLEAN_HOME after bootstrap"
    ;;
esac
NCS_KIB_AFTER_BOOTSTRAP="$(path_size_kib "$CLEAN_HOME/ncs")"
[ -n "$NCS_KIB_AFTER_BOOTSTRAP" ] || NCS_KIB_AFTER_BOOTSTRAP="not available"
NRFUTIL_KIB_AFTER_BOOTSTRAP="$(path_size_kib "$CLEAN_HOME/.nrfutil")"
[ -n "$NRFUTIL_KIB_AFTER_BOOTSTRAP" ] || NRFUTIL_KIB_AFTER_BOOTSTRAP="not available"
emit_kib_metric "filesystem free KiB after bootstrap" "$FREE_KIB_AFTER_BOOTSTRAP"
emit_kib_metric "NCS path size KiB after bootstrap" "$NCS_KIB_AFTER_BOOTSTRAP"
emit_kib_metric "nrfutil path size KiB after bootstrap" "$NRFUTIL_KIB_AFTER_BOOTSTRAP"

# ── Lifecycle 2: fresh shell, ZEPHYR_BASE, real build ───────────────────────
step "Lifecycle 2: fresh shell and real west sysbuild"

METRICS_DIR="$CLEAN_HOME/.nix-nrf-clean-metrics/build"
mkdir -p "$METRICS_DIR"

# Second independent entry with the same isolated HOME. Proves the shell
# derives ZEPHYR_BASE from the isolated installation, that a read-only check
# reports ready without mutation, and that the real build produces the exact
# artifacts. The inner script records the exact build elapsed seconds (epoch
# seconds around the `west build ...` command only) to the metrics directory;
# the outer script validates and reads that integer. Never flashes hardware.
# shellcheck disable=SC2016  # inner script vars expand inside nix develop, not here
nix develop .#clean-env-test \
  --ignore-env \
  --set-env-var HOME "$CLEAN_HOME" \
  --set-env-var NIX_NRF_EXPECTED_HOME "$CLEAN_HOME" \
  --set-env-var NIX_NRF_EXPECTED_NCS_VERSION "$NCS_VERSION" \
  --set-env-var NIX_NRF_CLEAN_METRICS_DIR "$METRICS_DIR" \
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
    t0=$(date +%s)
    west build -p always \
      -b xiao_nrf54l15/nrf54l15/cpuapp \
      --sysbuild \
      -d "$HOME/build/blinky" \
      "$ZEPHYR_BASE/samples/basic/blinky"
    elapsed=$(( $(date +%s) - t0 ))
    echo "build elapsed: ${elapsed}s"
    printf "%s\n" "$elapsed" > "$NIX_NRF_CLEAN_METRICS_DIR/elapsed"
    test -s "$HOME/build/blinky/blinky/zephyr/zephyr.elf" || { echo "zephyr.elf missing or empty" >&2; exit 1; }
    test -s "$HOME/build/blinky/domains.yaml" || { echo "domains.yaml missing or empty" >&2; exit 1; }
    echo "artifact OK: $HOME/build/blinky/blinky/zephyr/zephyr.elf"
    echo "artifact OK: $HOME/build/blinky/domains.yaml"
    du -sh "$HOME/ncs"
    du -sh "$HOME/build"
    echo "lifecycle 2 OK"
  '

BUILD_ELAPSED_S="$(read_int_metric "$METRICS_DIR/elapsed")"
emit_metric "build elapsed seconds" "$BUILD_ELAPSED_S"

# ── Checkpoint 3: free space and final mutable state ────────────────────────
step "Checkpoint 3: free space and final mutable-state sizes"
FREE_KIB_AFTER_BUILD="$(fs_free_kib "$CLEAN_HOME")"
case "$FREE_KIB_AFTER_BUILD" in
  '' | *[!0-9]*)
    fail "free-space" "cannot parse df output for $CLEAN_HOME after build"
    ;;
esac
NCS_KIB_FINAL="$(path_size_kib "$CLEAN_HOME/ncs")"
[ -n "$NCS_KIB_FINAL" ] || NCS_KIB_FINAL="not available"
NRFUTIL_KIB_FINAL="$(path_size_kib "$CLEAN_HOME/.nrfutil")"
[ -n "$NRFUTIL_KIB_FINAL" ] || NRFUTIL_KIB_FINAL="not available"
BUILD_KIB_FINAL="$(path_size_kib "$CLEAN_HOME/build")"
[ -n "$BUILD_KIB_FINAL" ] || BUILD_KIB_FINAL="not available"
HOME_KIB_FINAL="$(path_size_kib "$CLEAN_HOME")"
[ -n "$HOME_KIB_FINAL" ] || HOME_KIB_FINAL="not available"
emit_kib_metric "filesystem free KiB after build" "$FREE_KIB_AFTER_BUILD"
emit_kib_metric "NCS path size KiB final" "$NCS_KIB_FINAL"
emit_kib_metric "nrfutil path size KiB final" "$NRFUTIL_KIB_FINAL"
emit_kib_metric "build tree size KiB final" "$BUILD_KIB_FINAL"
emit_kib_metric "total clean home size KiB final" "$HOME_KIB_FINAL"

# ── Checkpoint 4: realized clean-env-test Nix closure ───────────────────────
step "Checkpoint 4: clean-env-test Nix closure (Nix store; separate from mutable-home disk use)"
# Realizes the fixed dev-shell closure only; runs no bootstrap, west, or
# Nordic install. `nix path-info` alone fails if output is not realized; the
# explicit `nix build --no-link --print-out-paths` is required first.
shell_path="$(nix build --no-link --print-out-paths .#devShells.x86_64-linux.clean-env-test)"
shell_closure_line="$(nix path-info -Sh "$shell_path")"
SHELL_CLOSURE_PATH="$shell_path"
SHELL_CLOSURE_LINE="$shell_closure_line"
emit_metric "clean-env-test Nix closure path (Nix store; separate from mutable-home disk use)" "$SHELL_CLOSURE_PATH"
emit_metric "clean-env-test Nix closure size (nix path-info -Sh)" "$SHELL_CLOSURE_LINE"

RESULT="passed"

# ── Summary before cleanup ───────────────────────────────────────────────────
step "Summary before cleanup"
du -sh "$CLEAN_HOME/ncs"
echo ""
echo "ALL CLEAN-ROOM TESTS PASSED"
