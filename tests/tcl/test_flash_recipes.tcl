#!/usr/bin/env tclsh
# SPDX-License-Identifier: MIT
#
# tests/tcl/test_flash_recipes.tcl — fake-OpenOCD semantic regression tests
# for the repository Tcl flash recipes (tcl/nrf53_flash.tcl and
# tcl/nrf54l_flash.tcl).
#
# Sources the REAL recipes under tclsh with fake OpenOCD commands that record
# every command + args into ::log, then asserts command order, single-argument
# preservation (including paths with spaces), conditionals, and safety
# branches — no hardware, no real OpenOCD, no Tcl packages. Command semantics
# matter more than formatting; human `puts` text is only asserted where it
# proves a warning or recovery branch fired.
#
# Recipe paths come from the required env vars NIX_NRF_NRF53_FLASH_TCL and
# NIX_NRF_NRF54L_FLASH_TCL; fail clearly when unset.
#
# Run standalone from the repo:
#   NIX_NRF_NRF53_FLASH_TCL="$PWD/tcl/nrf53_flash.tcl" \
#   NIX_NRF_NRF54L_FLASH_TCL="$PWD/tcl/nrf54l_flash.tcl" \
#     tclsh tests/tcl/test_flash_recipes.tcl
# Wired as checks.flash-recipe-tests in nix/flake/checks/core.nix (pinned
# pkgs.tcl).

# --- required env vars -----------------------------------------------------
foreach var {NIX_NRF_NRF53_FLASH_TCL NIX_NRF_NRF54L_FLASH_TCL} {
    if {![info exists ::env($var)] || $::env($var) eq ""} {
        puts stderr "FAIL: required env var $var is not set"
        exit 1
    }
}

# --- fake OpenOCD surface --------------------------------------------------
# Record-only commands. Every fake appends a Tcl list describing the command
# and its args to ::log, preserving single-argument boundaries.
proc init {} {lappend ::log [list init]}
proc targets {args} {lappend ::log [list targets {*}$args]}
proc reset {args} {lappend ::log [list reset {*}$args]}
proc halt {} {lappend ::log [list halt]}
proc wait_halt {args} {lappend ::log [list wait_halt {*}$args]}
proc load_image {args} {lappend ::log [list load_image {*}$args]}
proc verify_image {args} {lappend ::log [list verify_image {*}$args]}
proc mww {args} {lappend ::log [list mww {*}$args]}
proc nrf53_recover {} {lappend ::log [list nrf53_recover]}
proc nrf53_cpunet_release {args} {lappend ::log [list nrf53_cpunet_release {*}$args]}

# flash dispatcher: the recipes use fillw / write_image / probe.
proc flash {subcommand args} {
    switch -- $subcommand {
        fillw -
        write_image -
        probe {
            lappend ::log [list flash $subcommand {*}$args]
        }
        default {
            error "unknown flash subcommand: $subcommand"
        }
    }
}

# Target commands. arp_examine honors the per-target lock state (error when
# locked); read_memory honors per-address programmed values and returns the
# erased default 0xFFFFFFFF otherwise.
proc ::readmem {addr} {
    if {[info exists ::mem($addr)]} {
        return $::mem($addr)
    }
    return 0xFFFFFFFF
}

proc nrf53.cpuapp {subcommand args} {
    switch -- $subcommand {
        arp_examine {
            # Record the attempt even when it fails: the recipes branch on a
            # failed examine, so the log must prove the examine happened
            # before any recovery.
            lappend ::log [list nrf53.cpuapp arp_examine]
            if {$::app_locked} {
                error "nrf53.cpuapp locked (APPROTECT)"
            }
        }
        read_memory {
            set addr [lindex $args 0]
            lappend ::log [list nrf53.cpuapp read_memory $addr [lindex $args 1] [lindex $args 2]]
            return [::readmem $addr]
        }
        default {
            error "nrf53.cpuapp: unknown subcommand \"$subcommand\""
        }
    }
}

proc nrf53.cpunet {subcommand args} {
    switch -- $subcommand {
        arp_examine {
            lappend ::log [list nrf53.cpunet arp_examine]
            if {$::net_locked} {
                error "nrf53.cpunet locked"
            }
        }
        read_memory {
            set addr [lindex $args 0]
            lappend ::log [list nrf53.cpunet read_memory $addr [lindex $args 1] [lindex $args 2]]
            return [::readmem $addr]
        }
        default {
            error "nrf53.cpunet: unknown subcommand \"$subcommand\""
        }
    }
}

# Record single-argument `puts` calls so warning/recovery branch text can be
# asserted where semantics alone does not identify the branch, then forward
# to the real puts.
rename puts ::orig_puts
proc puts {args} {
    if {[llength $args] == 1} {
        lappend ::puts_log [lindex $args 0]
    }
    ::orig_puts {*}$args
}

# --- tiny assertions -------------------------------------------------------
set ::assert_count 0

proc assert_eq {actual expected msg} {
    incr ::assert_count
    if {$actual ne $expected} {
        ::orig_puts "FAIL: $msg"
        ::orig_puts "  expected: $expected"
        ::orig_puts "  actual:   $actual"
        exit 1
    }
}

proc assert_subseq {needle haystack msg} {
    incr ::assert_count
    set nl [llength $needle]
    set ni 0
    foreach item $haystack {
        if {$ni < $nl && [string equal [lindex $needle $ni] $item]} {
            incr ni
        }
    }
    if {$ni != $nl} {
        ::orig_puts "FAIL: $msg"
        ::orig_puts "  expected ordered subsequence: $needle"
        ::orig_puts "  in:                          $haystack"
        exit 1
    }
}

proc assert_count_cmd {cmd msg expected} {
    incr ::assert_count
    set count 0
    foreach entry $::log {
        if {[string equal [lindex $entry 0] $cmd]} {
            incr count
        }
    }
    if {$count != $expected} {
        ::orig_puts "FAIL: $msg"
        ::orig_puts "  expected $expected occurrence(s) of command \"$cmd\", got $count"
        ::orig_puts "  log: $::log"
        exit 1
    }
}

proc assert_contains_substr {entries substr msg} {
    incr ::assert_count
    foreach entry $entries {
        if {[string first $substr $entry] >= 0} {
            return
        }
    }
    ::orig_puts "FAIL: $msg"
    ::orig_puts "  substring \"$substr\" not found in: $entries"
    exit 1
}

# --- per-test state --------------------------------------------------------
proc reset_state {} {
    set ::log [list]
    set ::puts_log [list]
    set ::app_locked 0
    set ::net_locked 0
    unset -nocomplain ::mem
}

# --- source the real recipes ----------------------------------------------
source $::env(NIX_NRF_NRF54L_FLASH_TCL)
source $::env(NIX_NRF_NRF53_FLASH_TCL)

# --- tests -----------------------------------------------------------------

# 1. nrf54l_rram_we records exactly `mww 0x5004b500 0x101`.
reset_state
nrf54l_rram_we
assert_eq $::log [list [list mww 0x5004b500 0x101]] \
    "nrf54l_rram_we exact write-enable"

# 2. nrf54l_flash with a space-containing image path: exact order and
#    single-argument preservation.
reset_state
set image "/tmp/firmware images/merged.hex"
nrf54l_flash $image
assert_eq $::log \
    [list \
        [list reset halt] \
        [list mww 0x5004b500 0x101] \
        [list load_image $image] \
        [list verify_image $image] \
        [list reset run]] \
    "nrf54l_flash exact order and single-argument image preservation"

# 3. Erased UICR performs one exact `flash fillw <addr> 0x50FA50FA 1`.
reset_state
_uicr_unprotect nrf53.cpuapp 0x00FF8000
assert_eq $::log \
    [list \
        [list nrf53.cpuapp read_memory 0x00FF8000 32 1] \
        [list flash fillw 0x00FF8000 0x50FA50FA 1]] \
    "erased UICR performs one exact fillw"

# 4. Already-unprotected UICR performs no write.
reset_state
set ::mem(0x00FF8000) 0x50FA50FA
_uicr_unprotect nrf53.cpuapp 0x00FF8000
assert_eq $::log [list [list nrf53.cpuapp read_memory 0x00FF8000 32 1]] \
    "already-unprotected UICR performs no write"
assert_count_cmd flash "already-unprotected UICR has no flash fillw" 0

# 5. Other programmed value performs no write (leave-as-is safety branch).
reset_state
set ::mem(0x00FF8000) 0x12345678
_uicr_unprotect nrf53.cpuapp 0x00FF8000
assert_eq $::log [list [list nrf53.cpuapp read_memory 0x00FF8000 32 1]] \
    "other-programmed UICR performs no write"
assert_count_cmd flash "other-programmed UICR has no flash fillw" 0
assert_contains_substr $::puts_log "leaving as-is" \
    "other-programmed UICR prints leave-as-is warning"

# 6. App helper reads/programs the exact current two app addresses; net
#    helper the exact current net address (current recipe contract, not newly
#    researched constants).
reset_state
uicr_unprotect_app
assert_eq $::log \
    [list \
        [list nrf53.cpuapp read_memory 0x00FF8000 32 1] \
        [list flash fillw 0x00FF8000 0x50FA50FA 1] \
        [list nrf53.cpuapp read_memory 0x00FF801C 32 1] \
        [list flash fillw 0x00FF801C 0x50FA50FA 1]] \
    "uicr_unprotect_app exact current app addresses"
reset_state
uicr_unprotect_net
assert_eq $::log \
    [list \
        [list nrf53.cpunet read_memory 0x01FF8000 32 1] \
        [list flash fillw 0x01FF8000 0x50FA50FA 1]] \
    "uicr_unprotect_net exact current net address"

# 7. check_approtect: unlocked path does not recover; locked path calls
#    nrf53_recover exactly once.
reset_state
check_approtect
assert_count_cmd nrf53_recover "unlocked check_approtect does not recover" 0
assert_eq $::log [list [list nrf53.cpuapp arp_examine]] \
    "unlocked check_approtect only examines the app core"

reset_state
set ::app_locked 1
check_approtect
assert_count_cmd nrf53_recover "locked check_approtect recovers exactly once" 1
assert_eq $::log \
    [list [list nrf53.cpuapp arp_examine] [list nrf53_recover]] \
    "locked check_approtect recovery order"
assert_contains_substr $::puts_log "running nrf53_recover" \
    "locked check_approtect prints recovery message"

# 8. flash_both unlocked path with space-containing names: each name is one
#    argument and the full ordered semantics hold.
reset_state
set app_hex "/path/to/app core.hex"
set net_hex "/path/to/net core.hex"
flash_both $app_hex $net_hex
assert_eq $::log \
    [list \
        [list init] \
        [list nrf53.cpuapp arp_examine] \
        [list targets nrf53.cpuapp] \
        [list reset halt] \
        [list wait_halt 2000] \
        [list flash write_image erase $app_hex] \
        [list nrf53.cpuapp read_memory 0x00FF8000 32 1] \
        [list flash fillw 0x00FF8000 0x50FA50FA 1] \
        [list nrf53.cpuapp read_memory 0x00FF801C 32 1] \
        [list flash fillw 0x00FF801C 0x50FA50FA 1] \
        [list nrf53_cpunet_release nrf53] \
        [list nrf53.cpunet arp_examine] \
        [list targets nrf53.cpunet] \
        [list halt] \
        [list wait_halt 2000] \
        [list flash probe 2] \
        [list flash write_image erase $net_hex] \
        [list nrf53.cpunet read_memory 0x01FF8000 32 1] \
        [list flash fillw 0x01FF8000 0x50FA50FA 1] \
        [list reset run]] \
    "flash_both unlocked exact command sequence with space-containing names"
assert_count_cmd nrf53_recover "flash_both unlocked does not recover" 0
# Ordered-subsequence claims re-proven independently of the full equality.
assert_subseq \
    [list [list flash write_image erase $app_hex] \
        [list nrf53.cpuapp read_memory 0x00FF8000 32 1]] \
    $::log "app image write before app UICR writes"
assert_subseq \
    [list [list nrf53_cpunet_release nrf53] [list targets nrf53.cpunet]] \
    $::log "cpunet release/examine before selecting net"
assert_subseq \
    [list [list flash probe 2] [list flash write_image erase $net_hex]] \
    $::log "net halt/wait + flash probe 2 before net image write"
assert_subseq \
    [list [list flash write_image erase $net_hex] \
        [list nrf53.cpunet read_memory 0x01FF8000 32 1]] \
    $::log "net UICR handling after net image write"
assert_eq [lindex $::log end] [list reset run] "flash_both ends with reset run"

# 9. flash_both locked path: recovery after failed app examine and before app
#    reset/flash, then continues the normal flow.
reset_state
set ::app_locked 1
set app_hex "/path/to/app core.hex"
set net_hex "/path/to/net core.hex"
flash_both $app_hex $net_hex
assert_count_cmd nrf53_recover "flash_both locked recovers exactly once" 1
assert_subseq \
    [list [list nrf53.cpuapp arp_examine] [list nrf53_recover] \
        [list targets nrf53.cpuapp]] \
    $::log "recovery after failed app examine and before app reset/flash"
assert_contains_substr $::puts_log "running nrf53_recover" \
    "flash_both locked prints recovery message"
assert_eq $::log \
    [list \
        [list init] \
        [list nrf53.cpuapp arp_examine] \
        [list nrf53_recover] \
        [list targets nrf53.cpuapp] \
        [list reset halt] \
        [list wait_halt 2000] \
        [list flash write_image erase $app_hex] \
        [list nrf53.cpuapp read_memory 0x00FF8000 32 1] \
        [list flash fillw 0x00FF8000 0x50FA50FA 1] \
        [list nrf53.cpuapp read_memory 0x00FF801C 32 1] \
        [list flash fillw 0x00FF801C 0x50FA50FA 1] \
        [list nrf53_cpunet_release nrf53] \
        [list nrf53.cpunet arp_examine] \
        [list targets nrf53.cpunet] \
        [list halt] \
        [list wait_halt 2000] \
        [list flash probe 2] \
        [list flash write_image erase $net_hex] \
        [list nrf53.cpunet read_memory 0x01FF8000 32 1] \
        [list flash fillw 0x01FF8000 0x50FA50FA 1] \
        [list reset run]] \
    "flash_both locked recovery then normal flow"

# 10. flash_west: uses the exact NET_CORE_HEX, runs no manual init/app
#     reset-halt sequence, flashes the app before release/net flow, and ends
#     with reset run.
reset_state
set app_hex "/path/to/app core.hex"
set NET_CORE_HEX "/path/to/net core.hex"
flash_west $app_hex
assert_eq $::log \
    [list \
        [list flash write_image erase $app_hex] \
        [list nrf53.cpuapp read_memory 0x00FF8000 32 1] \
        [list flash fillw 0x00FF8000 0x50FA50FA 1] \
        [list nrf53.cpuapp read_memory 0x00FF801C 32 1] \
        [list flash fillw 0x00FF801C 0x50FA50FA 1] \
        [list nrf53_cpunet_release nrf53] \
        [list nrf53.cpunet arp_examine] \
        [list targets nrf53.cpunet] \
        [list halt] \
        [list wait_halt 2000] \
        [list flash probe 2] \
        [list flash write_image erase $NET_CORE_HEX] \
        [list nrf53.cpunet read_memory 0x01FF8000 32 1] \
        [list flash fillw 0x01FF8000 0x50FA50FA 1] \
        [list reset run]] \
    "flash_west exact sequence with exact NET_CORE_HEX"
assert_count_cmd init "flash_west runs no manual init" 0
assert_count_cmd reset "flash_west runs only the final reset run" 1
assert_count_cmd targets "flash_west never selects the app core" 1
assert_subseq \
    [list [list flash write_image erase $app_hex] \
        [list nrf53_cpunet_release nrf53]] \
    $::log "flash_west flashes app before release/net flow"
assert_eq [lindex $::log end] [list reset run] "flash_west ends with reset run"

::orig_puts "flash recipe tests passed: $::assert_count assertions"
