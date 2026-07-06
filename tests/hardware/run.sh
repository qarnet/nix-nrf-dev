#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# tests/hardware/run.sh — hardware integration test for nix-nrf-dev.
#
# Builds the Zephyr blinky sample for both target boards, identifies probes
# via nrf-probes, and flashes both boards via our openocd-master + TCL
# recipes. Asserts each step exits 0. Does NOT assert visible LED blink
# (would need a camera or GPIO probe — out of scope).
#
# Runs inside the nix dev shell (provided by the hardware workflow's
# cachix/install-nix-action + the flake's devShells.default). The runner
# must have NCS v3.3.0 installed via nrfutil sdk-manager.
#
# Usage: bash tests/hardware/run.sh
# Exit codes: 0 = all steps passed; non-zero = the first failing step.

set -euo pipefail

# fail <step> <message> — print context and exit non-zero.
fail() {
  echo "FAIL: $1: $2" >&2
  exit 1
}

# step <label> — echo a header for the next assertion.
step() {
  echo ""
  echo "=== $1 ==="
}

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

# ── 0. Verify tools are present ─────────────────────────────────────────────
step "Verify tools"
command -v openocd >/dev/null 2>&1 || fail "tools" "openocd not on PATH — enter the nix dev shell first"
command -v nrf-probes >/dev/null 2>&1 || fail "tools" "nrf-probes not on PATH — enter the nix dev shell first"
command -v west >/dev/null 2>&1 || fail "tools" "west not on PATH — enter the nix dev shell first"
echo "OK: openocd, nrf-probes, west present"

# ── 1. Identify probes and targets ──────────────────────────────────────────
step "nrf-probes enumeration"
nrf-probes || fail "nrf-probes" "nrf-probes failed to enumerate probes"

step "Find nRF5340 probe"
SER53="$(nrf-probes --find nrf53)" || fail "find-nrf53" "no unique nRF5340 probe found (exit $?)"
echo "OK: nRF5340 probe serial: $SER53"

step "Find nRF54L15 probe"
SER54L="$(nrf-probes --find nrf54l)" || fail "find-nrf54l" "no unique nRF54L15 probe found (exit $?)"
echo "OK: nRF54L15 probe serial: $SER54L"

# ── 2. Build blinky from NCS ────────────────────────────────────────────────
# The west wrapper loads the NCS toolchain env. If NCS v3.3.0 is not
# installed, west fails with a clear message — run.sh surfaces that.
BLINKY_SRC="${ZEPHYR_BASE:-$HOME/ncs/v3.3.0/zephyr}/samples/basic/blinky"
if [ ! -d "$BLINKY_SRC" ]; then
  fail "blinky-src" "blinky sample not found at $BLINKY_SRC — is ZEPHYR_BASE set or NCS v3.3.0 installed?"
fi

BUILD_DIR_53="$(mktemp -d -t nrf53-blinky-XXXXXX)"
BUILD_DIR_54L="$(mktemp -d -t nrf54l-blinky-XXXXXX)"
trap 'rm -rf "$BUILD_DIR_53" "$BUILD_DIR_54L"' EXIT

step "Build blinky for nRF5340 (nrf5340dk/nrf5340/cpuapp)"
if west build -b nrf5340dk/nrf5340/cpuapp -d "$BUILD_DIR_53" "$BLINKY_SRC"; then
  echo "OK: nRF5340 blinky built at $BUILD_DIR_53"
else
  fail "build-nrf53" "west build for nrf5340dk/nrf5340/cpuapp failed"
fi

step "Build blinky for Xiao nRF54L15 (xiao_nrf54l15/nrf54l15/cpuapp, --sysbuild)"
if west build -b xiao_nrf54l15/nrf54l15/cpuapp --sysbuild -d "$BUILD_DIR_54L" "$BLINKY_SRC"; then
  echo "OK: nRF54L15 blinky built at $BUILD_DIR_54L"
else
  fail "build-nrf54l" "west build for xiao_nrf54l15/nrf54l15/cpuapp failed"
fi

# Locate the merged hex for each build. Zephyr produces merged.hex at the
# build dir root for multi-image builds (sysbuild) or zephyr.hex for single-image.
HEX53=""
for cand in "$BUILD_DIR_53/merged.hex" "$BUILD_DIR_53/zephyr/zephyr.hex"; do
  [ -f "$cand" ] && HEX53="$cand" && break
done
[ -n "$HEX53" ] || fail "hex-nrf53" "no merged.hex or zephyr.hex found in $BUILD_DIR_53"

HEX54L=""
for cand in "$BUILD_DIR_54L/merged.hex" "$BUILD_DIR_54L/zephyr/zephyr.hex"; do
  [ -f "$cand" ] && HEX54L="$cand" && break
done
[ -n "$HEX54L" ] || fail "hex-nrf54l" "no merged.hex or zephyr.hex found in $BUILD_DIR_54L"

echo "OK: nRF5340 hex: $HEX53"
echo "OK: nRF54L15 hex: $HEX54L"

# ── 3. Flash nRF5340 via our TCL recipe ─────────────────────────────────────
step "Flash nRF5340 via tcl/nrf53_flash.tcl"
# nrf53_flash.tcl's flash_both proc takes app_hex and net_hex. For a blinky
# build, the merged.hex contains both app and net images. We pass it as both
# arguments; the recipe flashes app core first, then net core.
if openocd \
  -f interface/cmsis-dap.cfg \
  -c "adapter serial $SER53" \
  -c "transport select swd" \
  -c "adapter speed 1000" \
  -f target/nordic/nrf53.cfg \
  -f tcl/nrf53_flash.tcl \
  -c init \
  -c "flash_both $HEX53 $HEX53" \
  -c shutdown; then
  echo "OK: nRF5340 flashed"
else
  fail "flash-nrf53" "openocd flash via nrf53_flash.tcl failed (exit $?)"
fi

# ── 4. Flash nRF54L15 via our TCL recipe ────────────────────────────────────
step "Flash nRF54L15 via tcl/nrf54l_flash.tcl"
if openocd \
  -f interface/cmsis-dap.cfg \
  -c "adapter serial $SER54L" \
  -c "transport select swd" \
  -c "adapter speed 1000" \
  -f target/nordic/nrf54l.cfg \
  -f tcl/nrf54l_flash.tcl \
  -c init \
  -c "nrf54l_flash $HEX54L" \
  -c shutdown; then
  echo "OK: nRF54L15 flashed"
else
  fail "flash-nrf54l" "openocd flash via nrf54l_flash.tcl failed (exit $?)"
fi

echo ""
echo "ALL HARDWARE TESTS PASSED"
