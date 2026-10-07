---
id: PB-003
title: Expose scoped matching GDB and binutils from the selected toolchain
status: Backlog
assignee: []
created_date: '2026-09-26 00:41'
labels:
  - 'area:toolchain'
  - 'area:cli'
  - 'area:debug'
dependencies: []
priority: p1
type: feature
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

Nordic's toolchain environment is currently scoped to west. Users lack deliberate direct access to matching debugger and ELF analysis tools for CPUAPP and FLPR artifacts.

### Desired outcome

Users can invoke matching GDB, addr2line, nm, objdump, readelf, and size without contaminating the surrounding shell or guessing tool paths.

### Scope / Non-goals

Provide scoped tool execution with preserved arguments, streams, and exit status. Respect selected backend/version/bundle. Qualify Arm and RISC-V offline tools separately from host FLPR run-control support. No global Nordic environment, ambient-host fallback, unrequested installation, or west SDK upgrade.

### Technical context

nix/backends/nrfutil/shell.nix:70-126; nix/backends/west/zephyr-sdk.nix; nix/backends/west/versions.nix. West packaging notes plain GDB versus gdb-py ABI limitations. Receiver has separate CPUAPP and src/flpr images.

Research and pinned upstream references: docs/product/research/debug-tooling.md. Receiver evidence: le-audio-receiver at 012b19739802e8fc53d6e8a701fb362a17a1c209, inspected read-only.

### Open questions

Which executables and GDB Python features run in each existing backend, and should the public interface be a scoped tool command or named wrappers?

This item remains Backlog until refinement resolves implementation-shaping questions and assigns size. Hardware access, flashing, recovery, and intrusive operations still require explicit approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Public subprocess tests demonstrate argument quoting, input/output, exit-code propagation, and clear missing-tool errors using the configured selector.
- [ ] #2 Actual selected GDB and binutils execute, and known matching Arm/FLPR ELFs can be inspected and symbolicated offline; unsupported tools are reported explicitly.
- [ ] #3 Parent Python/Git/loader environment remains unchanged, and debug invocation never installs a missing SDK or switches to an unrelated host tool.
- [ ] #4 Support documentation distinguishes plain GDB, Python extensions, Arm run control, and RISC-V offline analysis without changing west version metadata.
<!-- AC:END -->
