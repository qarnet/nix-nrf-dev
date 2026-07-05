# SPDX-License-Identifier: MIT
#
# nRF54L RRAM flashing helpers.
#
# nRF54L RRAM needs no OpenOCD flash driver: once the RRAMC write-enable is
# set it is plain byte-writable memory, so load_image/verify_image suffice.
# FLPR (RISC-V coprocessor) firmware is flashed the same way — its code
# partition is an RRAM slice in the app core address space (0x165000 on the
# nRF54L15). Verified on hardware 2026-07-05 (Xiao nRF54L15, built-in
# CMSIS-DAP).
#
# Use together with target/nordic/nrf54l.cfg (or a board cfg that sources
# it), e.g.:
#   openocd -c "adapter serial <SER>" -f target/nordic/nrf54l.cfg \
#           -f nrf54l_flash.tcl -c init -c "nrf54l_flash merged.hex" -c shutdown
#
# RECOVERY WARNING: there is NO known-good openocd recovery for nRF54L
# (upstream has none; the generic _nrf_ctrl_ap_recover expects the nRF53
# CTRL-AP IDR). If APPROTECT ever engages, the fallback is Nordic's
# `nrfutil device recover` with a J-Link.

# Enable RRAMC write mode (RRAMC.CONFIG = WEN | write-buffer size).
proc nrf54l_rram_we {} {
    mww 0x5004b500 0x101
}

# Flash an image (ihex/elf with embedded addresses) and verify, then run.
proc nrf54l_flash {image} {
    reset halt
    nrf54l_rram_we
    load_image $image
    verify_image $image
    reset run
}
