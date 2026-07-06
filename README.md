# nix-nrf-dev

Reusable Nix tooling for Nordic nRF firmware development: an NCS toolchain dev
shell and CMSIS-DAP flashing via a pinned openocd-master build. Verified on
nRF5340 and nRF54L15 hardware.

## Install

### New project (template)

```bash
nix flake init -t github:qarnet/nix-nrf-dev
direnv allow          # or: nix develop
```

### Existing project (flake input)

```nix
{
  inputs.nix-nrf-dev = {
    url = "github:qarnet/nix-nrf-dev";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

```nix
devShells.default = nix-nrf-dev.lib.${system}.mkNrfShell {
  ncsVersion = "v3.3.0";
};
```

The shell provides `west` + Zephyr toolchain (via nrfutil sdk-manager),
`ZEPHYR_BASE`, `openocd` (master build), `nrf-probes`, `nrfutil`, and
multilib GCC for `native_sim`.

**Scoped toolchain environment:** Nordic's sdk-manager env script exports
`PYTHONHOME`, `PYTHONPATH`, `LD_LIBRARY_PATH` and `GIT_EXEC_PATH` — toxic to
non-toolchain tools. `mkNrfShell` does NOT eval it into the shell; a `west`
wrapper loads it only inside west's process tree. The shell itself stays
clean — `nix`, agents, and editors launched from it work normally.

## Outputs

| Output | What |
|--------|------|
| `lib.<system>.mkNrfShell { ncsVersion, packages, extraShellHook, withMultilib }` | devShell factory |
| `packages.openocd-master` | openocd from master (pinned), wrapped for libudev |
| `packages.openocd-master-unwrapped` | the raw build |
| `packages.nrf-probes` | probe/target identification (read-only) |
| `packages.nrfutil-core` | minimal nrfutil (no J-Link dependency) |
| `devShells.default` | dogfood shell for hacking on this repo |
| `formatter.<system>` | treefmt wrapper (`nix fmt`) |
| `checks.<system>` | `formatting` (treefmt) + `pre-commit` (git-hooks.nix) |
| `templates.default` | project skeleton (flake.nix + .envrc) |
| `tcl/` | canonical flash recipes (see below) |

## nrf-probes

Read-only CMSIS-DAP probe/target identification. Never assume the
probe↔board mapping — probes get replugged.

```
$ nrf-probes
SERIAL            PROBE                              TARGET    DPIDR       PART        VARIANT
8EE9B3FF          Seeed Studio XIAO nrf54 CMSIS-DAP  nRF54L15  0x6ba02477  0x00054b15  AAC0
E6635C08CB1F502B  Debugprobe on Pico (CMSIS-DAP)     nRF5340   0x6ba02477  0x00005340  QKAA

$ nrf-probes --find nrf53      # serial of the probe wired to an nRF53
E6635C08CB1F502B
```

Works on APPROTECT-locked chips via the DP/AP signature. Flash scripts should
select probes with `--find <family>` instead of hardcoding serials.

## Flash recipes (`tcl/`)

- **`nrf53_flash.tcl`** — nRF5340 dual-core flash with APPROTECT
  check/recovery and mandatory UICR.APPROTECT programming. Integrates with
  the west openocd runner (`check_approtect` / `flash_west`) or standalone
  (`flash_both`).
- **`nrf54l_flash.tcl`** — nRF54L RRAM flash (no flash driver; RRAMC
  write-enable + `load_image`/`verify_image`).

## Recovery coverage

| Chip | Recovery | Notes |
|------|----------|-------|
| nRF5340 | openocd `nrf53_recover` | proven; nRF53-specific CTRL-AP proc |
| nRF54L | **NONE** | upstream openocd has no nrf54l recovery. Fallback: `nrfutil device recover` with a J-Link. |

## Policy

openocd-master is the only flash backend. probe-rs was evaluated and rejected:
on the nRF5340 its attach model collides with soft-APPROTECT and its only
unlock remedy is a destructive mass erase that recreates the lock.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md). The repo uses Conventional Commits,
`nix fmt` (alejandra + black), and pre-commit hooks via git-hooks.nix. CI
builds all packages (cached via [Cachix](https://app.cachix.org) under
`qarnet`), runs smoke tests, flake checks, and TCL-parse tests on every PR.
Hardware integration tests run on a self-hosted runner — see
`tests/hardware/README.md`.

## License

MIT. See [LICENSE](LICENSE).
