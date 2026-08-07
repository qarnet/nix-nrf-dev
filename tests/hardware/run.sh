#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# tests/hardware/run.sh — hardware integration test for nix-nrf-dev.
#
# Builds four distinct runtime artifacts and flashes them through
# openocd-master + the TCL recipes, proving REAL multicore flashing:
#
#   - nRF5340 CPUAPP blinky  (nrf5340dk/nrf5340/cpuapp)
#   - nRF5340 CPUNET empty   (nrf5340dk/nrf5340/cpunet, official NCS
#                             samples/basic/empty)
#   - XIAO nRF54L15 CPUAPP blinky (existing normal app proof)
#   - XIAO nRF54L15 FLPR bundle   (xiao_nrf54l15/nrf54l15/cpuflpr,
#                             official NCS samples/basic/empty sysbuild
#                             bundle: CPUAPP VPR launcher + FLPR RRAM)
#
# Each hex layout is validated against its required address regions BEFORE
# any flash write (stdlib Python Intel HEX parser: checksums, extended
# segment/linear records, out-of-region byte rejection). Every OpenOCD
# invocation is captured to a per-step log; the nRF53 run must byte-verify
# BOTH cores ("Verified app core:" / "Verified net core:") with no "no
# flash bank found" warning, and the FLPR run must byte-verify the whole
# bundle ("Verified image: <bundle>"). FLPR EXECUTION is not observed —
# this phase proves flashability, not runtime IPC/heartbeat.
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
command -v nix-nrf >/dev/null 2>&1 || fail "tools" "nix-nrf not on PATH — enter the nix dev shell first"
command -v west >/dev/null 2>&1 || fail "tools" "west not on PATH — enter the nix dev shell first"
command -v python3 >/dev/null 2>&1 || fail "tools" "python3 not on PATH (needed for Intel HEX layout validation)"
echo "OK: openocd, nix-nrf, west, python3 present"

# ── 1. Identify probes and targets ──────────────────────────────────────────
step "nix-nrf probes enumeration"
nix-nrf probes || fail "nix-nrf-probes" "nix-nrf probes failed to enumerate probes"

step "Find nRF5340 probe"
SER53="$(nix-nrf probes --find nrf53)" || fail "find-nrf53" "no unique nRF5340 probe found (exit $?)"
echo "OK: nRF5340 probe serial: $SER53"

step "Find nRF54L15 probe"
SER54L="$(nix-nrf probes --find nrf54l)" || fail "find-nrf54l" "no unique nRF54L15 probe found (exit $?)"
echo "OK: nRF54L15 probe serial: $SER54L"

# ── 2. Build four artifacts from NCS ────────────────────────────────────────
# The west wrapper loads the NCS toolchain env. If NCS v3.3.0 is not
# installed, west fails with a clear message — run.sh surfaces that.
NCS_ROOT="${ZEPHYR_BASE:-$HOME/ncs/v3.3.0/zephyr}/.."
BLINKY_SRC="${ZEPHYR_BASE:-$HOME/ncs/v3.3.0/zephyr}/samples/basic/blinky"
NCS_EMPTY_SRC="$NCS_ROOT/nrf/samples/basic/empty"
if [ ! -d "$BLINKY_SRC" ]; then
  fail "blinky-src" "blinky sample not found at $BLINKY_SRC — is ZEPHYR_BASE set or NCS v3.3.0 installed?"
fi
if [ ! -d "$NCS_EMPTY_SRC" ]; then
  fail "empty-src" "empty sample not found at $NCS_EMPTY_SRC — is ZEPHYR_BASE set or NCS v3.3.0 installed?"
fi

BUILD_DIR_53="$(mktemp -d -t nrf53-blinky-XXXXXX)"
BUILD_DIR_53_NET="$(mktemp -d -t nrf53-cpunet-XXXXXX)"
BUILD_DIR_54L="$(mktemp -d -t nrf54l-blinky-XXXXXX)"
BUILD_DIR_54L_FLPR="$(mktemp -d -t nrf54l-flpr-XXXXXX)"
LOG_FLASH53="$(mktemp -t nrf53-openocd-XXXXXX.log)"
LOG_FLASH54L="$(mktemp -t nrf54l-openocd-XXXXXX.log)"
LOG_FLASH54L_FLPR="$(mktemp -t nrf54l-flpr-openocd-XXXXXX.log)"
trap 'rm -rf "$BUILD_DIR_53" "$BUILD_DIR_53_NET" "$BUILD_DIR_54L" "$BUILD_DIR_54L_FLPR" "$LOG_FLASH53" "$LOG_FLASH54L" "$LOG_FLASH54L_FLPR"' EXIT

step "Build blinky for nRF5340 (nrf5340dk/nrf5340/cpuapp)"
if west build -b nrf5340dk/nrf5340/cpuapp -d "$BUILD_DIR_53" "$BLINKY_SRC"; then
  echo "OK: nRF5340 blinky built at $BUILD_DIR_53"
else
  fail "build-nrf53" "west build for nrf5340dk/nrf5340/cpuapp failed"
fi

step "Build empty CPUNET image for nRF5340 (nrf5340dk/nrf5340/cpunet, --sysbuild)"
if west build -p always --sysbuild -b nrf5340dk/nrf5340/cpunet -d "$BUILD_DIR_53_NET" "$NCS_EMPTY_SRC"; then
  echo "OK: nRF5340 CPUNET empty image built at $BUILD_DIR_53_NET"
else
  fail "build-nrf53-net" "west build for nrf5340dk/nrf5340/cpunet failed"
fi

step "Build blinky for Xiao nRF54L15 (xiao_nrf54l15/nrf54l15/cpuapp, --sysbuild)"
if west build -b xiao_nrf54l15/nrf54l15/cpuapp --sysbuild -d "$BUILD_DIR_54L" "$BLINKY_SRC"; then
  echo "OK: nRF54L15 blinky built at $BUILD_DIR_54L"
else
  fail "build-nrf54l" "west build for xiao_nrf54l15/nrf54l15/cpuapp failed"
fi

step "Build empty FLPR bundle for Xiao nRF54L15 (xiao_nrf54l15/nrf54l15/cpuflpr, --sysbuild)"
if west build -p always --sysbuild -b xiao_nrf54l15/nrf54l15/cpuflpr -d "$BUILD_DIR_54L_FLPR" "$NCS_EMPTY_SRC"; then
  echo "OK: nRF54L15 FLPR bundle built at $BUILD_DIR_54L_FLPR"
else
  fail "build-nrf54l-flpr" "west build for xiao_nrf54l15/nrf54l15/cpuflpr failed"
fi

# ── 3. Require exact non-empty root artifacts (sysbuild contract) ───────────
# No fallback paths: exact root locations are part of the tested sysbuild
# contract. `-s` requires a non-empty regular file.
step "Verify build artifacts"
HEX53="$BUILD_DIR_53/merged.hex"
HEX53_NET="$BUILD_DIR_53_NET/merged.hex"
HEX54L="$BUILD_DIR_54L/merged.hex"
HEX54L_FLPR="$BUILD_DIR_54L_FLPR/merged.hex"
DOMAINS54L_FLPR="$BUILD_DIR_54L_FLPR/domains.yaml"
for hex in "$HEX53" "$HEX53_NET" "$HEX54L" "$HEX54L_FLPR"; do
  [ -s "$hex" ] || fail "artifacts" "missing non-empty merged.hex at $hex"
done
[ -s "$DOMAINS54L_FLPR" ] || fail "artifacts" "missing non-empty domains.yaml at $DOMAINS54L_FLPR"
grep -qF "name: empty" "$DOMAINS54L_FLPR" || fail "artifacts" "FLPR domains.yaml lacks the 'empty' (FLPR) domain: $DOMAINS54L_FLPR"
grep -qF "name: vpr_launcher" "$DOMAINS54L_FLPR" || fail "artifacts" "FLPR domains.yaml lacks the 'vpr_launcher' (CPUAPP) domain: $DOMAINS54L_FLPR"
echo "OK: nRF5340 CPUAPP hex: $HEX53"
echo "OK: nRF5340 CPUNET hex: $HEX53_NET"
echo "OK: nRF54L15 blinky hex: $HEX54L"
echo "OK: nRF54L15 FLPR bundle hex: $HEX54L_FLPR"
echo "OK: FLPR domains.yaml declares domains 'empty' and 'vpr_launcher'"

# ── 4. Intel HEX layout validation ──────────────────────────────────────────
# Stdlib Python Intel HEX parser: validates record checksums, handles
# extended segment (02) / linear (04) address records, rejects malformed
# or unsupported address state, counts data bytes per required region,
# rejects any byte outside the required regions, and prints total bytes
# and min/max address. Every required region must contain at least one
# data byte — this catches the original app-image-as-net-image defect
# before any flash write touches hardware.
# validate_hex_layout <hex> <name:start:end,...>
validate_hex_layout() {
  local hex="$1" spec="$2" out
  out="$(python3 - "$hex" "$spec" 2>&1 <<'PY'
import sys


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: validate_hex_layout <hex-file> <regions>\n")
        return 2
    path, spec = sys.argv[1], sys.argv[2]
    regions = []
    for part in spec.split(","):
        name, start_s, end_s = part.split(":")
        regions.append((name, int(start_s, 16), int(end_s, 16)))

    base = 0
    total = 0
    lo = None
    hi = None
    region_bytes = {name: 0 for name, _, _ in regions}
    saw_eof = False

    with open(path, "r", encoding="ascii") as f:
        for lineno, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            if not line.startswith(":"):
                sys.stderr.write(f"ERROR: {path}:{lineno}: malformed record (missing ':' prefix)\n")
                return 1
            try:
                raw = bytes.fromhex(line[1:])
            except ValueError:
                sys.stderr.write(f"ERROR: {path}:{lineno}: non-hexadecimal characters\n")
                return 1
            if len(raw) < 5:
                sys.stderr.write(f"ERROR: {path}:{lineno}: record too short\n")
                return 1
            n = raw[0]
            addr = (raw[1] << 8) | raw[2]
            rtype = raw[3]
            payload = raw[4:-1]
            if len(payload) != n:
                sys.stderr.write(
                    f"ERROR: {path}:{lineno}: byte count {n} != payload length {len(payload)}\n"
                )
                return 1
            if sum(raw) & 0xFF:
                sys.stderr.write(f"ERROR: {path}:{lineno}: checksum mismatch\n")
                return 1
            if rtype == 0x00:
                a = base + addr
                for i in range(n):
                    byte_addr = a + i
                    if byte_addr > 0xFFFFFFFF:
                        sys.stderr.write(
                            f"ERROR: {path}:{lineno}: data address 0x{byte_addr:08X} exceeds 32 bits\n"
                        )
                        return 1
                    if lo is None or byte_addr < lo:
                        lo = byte_addr
                    if hi is None or byte_addr > hi:
                        hi = byte_addr
                    total += 1
                    in_region = False
                    for name, start, end in regions:
                        if start <= byte_addr < end:
                            region_bytes[name] += 1
                            in_region = True
                            break
                    if not in_region:
                        sys.stderr.write(
                            f"ERROR: {path}:{lineno}: data byte at 0x{byte_addr:08X} outside all required regions\n"
                        )
                        return 1
            elif rtype == 0x01:
                if n != 0:
                    sys.stderr.write(f"ERROR: {path}:{lineno}: EOF record with payload\n")
                    return 1
                saw_eof = True
                break
            elif rtype == 0x02:
                if n != 2:
                    sys.stderr.write(
                        f"ERROR: {path}:{lineno}: extended segment address record length != 2\n"
                    )
                    return 1
                base = ((payload[0] << 8) | payload[1]) * 16
            elif rtype == 0x04:
                if n != 2:
                    sys.stderr.write(
                        f"ERROR: {path}:{lineno}: extended linear address record length != 2\n"
                    )
                    return 1
                base = ((payload[0] << 8) | payload[1]) * 65536
            elif rtype in (0x03, 0x05):
                # Start segment/linear address: metadata only, no data bytes.
                pass
            else:
                sys.stderr.write(f"ERROR: {path}:{lineno}: unsupported record type 0x{rtype:02X}\n")
                return 1

    if not saw_eof:
        sys.stderr.write(f"ERROR: {path}: missing EOF record\n")
        return 1
    if total == 0:
        sys.stderr.write(f"ERROR: {path}: no data records\n")
        return 1
    if lo is None or hi is None:
        sys.stderr.write(f"ERROR: {path}: no data addresses\n")
        return 1
    for name, _, _ in regions:
        if region_bytes[name] == 0:
            sys.stderr.write(f"ERROR: {path}: region {name} contains no data bytes\n")
            return 1

    print(f"OK: {path}: {total} data bytes, range 0x{lo:08X}..0x{hi:08X}")
    for name, start, end in regions:
        print(f"  region {name}: 0x{start:08X}..0x{end:08X}: {region_bytes[name]} bytes")
    return 0


sys.exit(main())
PY
  )" || fail "hex-layout" "validation failed for $hex: $out"
  echo "$out"
}

step "Validate nRF5340 CPUAPP hex layout (0x00000000..0x00100000)"
validate_hex_layout "$HEX53" "cpuapp:0x00000000:0x00100000"

step "Validate nRF5340 CPUNET hex layout (0x01000000..0x01040000)"
validate_hex_layout "$HEX53_NET" "cpunet:0x01000000:0x01040000"

step "Validate nRF54L15 FLPR bundle hex layout (launcher < 0x00165000, FLPR RRAM 0x00165000..0x0017D000)"
validate_hex_layout "$HEX54L_FLPR" "cpuapp-launcher:0x00000000:0x00165000,flpr-rram:0x00165000:0x0017D000"

# ── 5. Flash nRF5340 via our TCL recipe ─────────────────────────────────────
step "Flash nRF5340 (distinct CPUAPP + CPUNET images) via tcl/nrf53_flash.tcl"
# flash_both must receive two DISTINCT images: CPUAPP at 0x00000000 and
# CPUNET at 0x01000000. The old harness passed the same merged.hex twice,
# making the "net core" claim a false positive ("no flash bank found").
[ "$HEX53" != "$HEX53_NET" ] || fail "flash-nrf53" "CPUAPP and CPUNET hex files must be distinct (both $HEX53)"
if openocd \
  -f interface/cmsis-dap.cfg \
  -c "adapter serial $SER53" \
  -c "transport select swd" \
  -c "adapter speed 1000" \
  -f target/nordic/nrf53.cfg \
  -f tcl/nrf53_flash.tcl \
  -c init \
  -c "flash_both $HEX53 $HEX53_NET" \
  -c shutdown 2>&1 | tee "$LOG_FLASH53"; then
  echo "OK: nRF5340 openocd exited 0"
else
  fail "flash-nrf53" "openocd flash via nrf53_flash.tcl failed (exit $?) — see $LOG_FLASH53"
fi
if grep -q "no flash bank found" "$LOG_FLASH53"; then
  fail "flash-nrf53" "'no flash bank found' in OpenOCD log — a core was not flashed: $LOG_FLASH53"
fi
grep -qF "Verified app core: $HEX53" "$LOG_FLASH53" || \
  fail "flash-nrf53" "missing exact 'Verified app core: $HEX53' line — see $LOG_FLASH53"
grep -qF "Verified net core: $HEX53_NET" "$LOG_FLASH53" || \
  fail "flash-nrf53" "missing exact 'Verified net core: $HEX53_NET' line — see $LOG_FLASH53"
echo "OK: nRF5340 both cores flashed and byte-verified"

# ── 6. Flash nRF54L15 blinky via our TCL recipe (existing normal app proof) ─
step "Flash nRF54L15 blinky via tcl/nrf54l_flash.tcl"
if openocd \
  -f interface/cmsis-dap.cfg \
  -c "adapter serial $SER54L" \
  -c "transport select swd" \
  -c "adapter speed 1000" \
  -f target/nordic/nrf54l.cfg \
  -f tcl/nrf54l_flash.tcl \
  -c init \
  -c "nrf54l_flash $HEX54L" \
  -c shutdown 2>&1 | tee "$LOG_FLASH54L"; then
  echo "OK: nRF54L15 blinky openocd exited 0"
else
  fail "flash-nrf54l" "openocd flash via nrf54l_flash.tcl failed (exit $?) — see $LOG_FLASH54L"
fi

# ── 7. Flash nRF54L15 FLPR bundle via our TCL recipe ────────────────────────
step "Flash nRF54L15 FLPR bundle via tcl/nrf54l_flash.tcl"
if openocd \
  -f interface/cmsis-dap.cfg \
  -c "adapter serial $SER54L" \
  -c "transport select swd" \
  -c "adapter speed 1000" \
  -f target/nordic/nrf54l.cfg \
  -f tcl/nrf54l_flash.tcl \
  -c init \
  -c "nrf54l_flash $HEX54L_FLPR" \
  -c shutdown 2>&1 | tee "$LOG_FLASH54L_FLPR"; then
  echo "OK: nRF54L15 FLPR openocd exited 0"
else
  fail "flash-nrf54l-flpr" "openocd FLPR flash via nrf54l_flash.tcl failed (exit $?) — see $LOG_FLASH54L_FLPR"
fi
grep -qF "Verified image: $HEX54L_FLPR" "$LOG_FLASH54L_FLPR" || \
  fail "flash-nrf54l-flpr" "missing exact 'Verified image: $HEX54L_FLPR' line — see $LOG_FLASH54L_FLPR"
echo "OK: nRF54L15 FLPR bundle loaded and byte-verified (execution not observed — out of scope)"

echo ""
echo "ALL HARDWARE TESTS PASSED"
