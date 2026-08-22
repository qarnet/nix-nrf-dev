# Installation

Use this guide to install nix-nrf-dev. See [README quick start](../README.md#quick-start)
for shorter setup steps.

## Prerequisites

- Nix with flake support on `x86_64-linux`. Enable the `flakes` and
  `nix-command` experimental features (NixOS:
  `nix.settings.experimental-features = [ "nix-command" "flakes" ]`; other
  distros: `experimental-features = nix-command flakes` in `/etc/nix/nix.conf`).
- `direnv` is optional. It loads the dev shell when you
  enter the project directory. Without it, run `nix develop` manually. See
  the [direnv wiki](https://github.com/direnv/direnv/wiki).
- Disk space and network access. NCS SDK source and toolchain download is
  several GiB from Nordic.
- Probe access is host policy, not part of shell. See
  [hardware.md](hardware.md) when CMSIS-DAP probes are involved.

## What it installs

| Component | What | Where |
|-----------|------|-------|
| `nix-nrf` helper | `bootstrap`, `versions`, `probes`, `doctor` for provisioning and diagnostics | Nix store; on `PATH` inside shell |
| NCS SDK source + toolchain | Nordic sdk-manager install | `$HOME/ncs/<version>` (nrfutil backend) |
| `west` wrapper | loads sdk-manager environment only inside west process tree. `PYTHONHOME`, `PYTHONPATH`, `LD_LIBRARY_PATH`, and `GIT_EXEC_PATH` do not enter shell | shell `PATH` |
| `ZEPHYR_BASE` | derived from the installed SDK at shell entry | shell environment |
| `openocd-master` | pinned build from source, wrapped for libudev | Nix store (first build ~10 min; `cachix use qarnet` pulls it from cache) |
| `nrfutil` | sdk-manager; includes J-Link and its unfree license. See [backends.md#segger--j-link-caveat](backends.md#segger--j-link-caveat) | Nix store |
| multilib GCC | for Zephyr `native_sim` (`-m32`) host builds on x86_64-linux | shell `PATH` |
| udev rules package | upstream OpenOCD `60-openocd.rules` | Nix store; activating it is host policy. See [hardware.md](hardware.md) |

## Create a project with `init-project`

The initializer writes `.envrc` and `flake.nix` with current `mkNrfShell`
configuration instead of copying a stale NCS version.

```bash
mkdir my-project && cd my-project
nix run github:qarnet/nix-nrf-dev#init-project -- .
```

It:

- Writes `.envrc` containing `use flake` and `flake.nix` into
  the destination (`.` above, or any path), calling `mkNrfShell` with the
  backend and NCS release you choose.
- Pins one concrete NCS release. Generated flake never contains
  `"latest"`.
- Refuses to overwrite. Existing `flake.nix` or `.envrc`, a symlink
  escape attempt, or invalid backend/version aborts with
  `init-project: ...` on stderr and leaves no generated output.

Then enter the shell and provision:

```bash
direnv allow        # or: nix develop
nix-nrf bootstrap   # prompts before downloading several GiB
nix-nrf doctor      # verify environment and probe access
```

### Version selection

- `--ncs-version latest` (default) resolves to one concrete release at
  generation time. For the `nrfutil` backend that asks the packaged
  sdk-manager for the newest stable remotely installable release; for the
  `west` backend it selects the newest release in the local west
  metadata. Either way the release is written into the generated flake.
- `--ncs-version v3.3.0` generates offline without a remote query.
- `--backend nrfutil` (default, recommended) or `--backend west`
  (experimental). See [backends.md](backends.md) for backend behavior.
- `--non-interactive` for scripted use; `nix run
  ...#init-project -- --help` shows the full CLI.

### Release-tag pinning

For reproducible consumer builds, pin the project to an immutable release
tag (`v<version>` tags are created automatically from trusted pushes to
`main` after CI passes):

```bash
nix run github:qarnet/nix-nrf-dev/v0.1.0#init-project -- ./my-project
```

```nix
# flake.nix
inputs.nix-nrf-dev.url = "github:qarnet/nix-nrf-dev/v0.1.0";
```

### First run

- The first evaluation builds openocd-master from source (~10 min) unless
  the [Cachix](https://app.cachix.org) cache is enabled:
  `cachix use qarnet`.
- `nix-nrf bootstrap` then downloads the NCS SDK source and toolchain
  (several GiB). It prompts for confirmation; `nix-nrf bootstrap --yes`
  approves up front.

## Add nix-nrf-dev to an existing project

Add nix-nrf-dev to a project that already exists.

1. Open your project's `flake.nix`.
2. Add the input:

   ```nix
   {
     inputs.nix-nrf-dev.url = "github:qarnet/nix-nrf-dev";
   }
   ```

   Adding `inputs.nixpkgs.follows = "nixpkgs"` is optional. nix-nrf-dev
   works with the nixpkgs revision it pins itself. See
   [backends.md#should-i-use-inputsnixpkgsfollows](backends.md#should-i-use-inputsnixpkgsfollows).

3. Add the dev shell to `outputs`:

   ```nix
   {
     outputs = { nix-nrf-dev, ... }: {
       devShells.x86_64-linux.default =
         nix-nrf-dev.lib.x86_64-linux.mkNrfShell {
           backend = "nrfutil";   # default; "west" is experimental
           ncsVersion = "v3.3.0"; # required, exact release, never "latest"
         };
     };
   }
   ```

   - `backend` selects the NCS toolchain provider: `nrfutil`
     (default, recommended) or `west` (experimental). See
     [backends.md](backends.md).
   - `ncsVersion` is required in every configuration; there is no
     `"latest"` alias or default.
   - `autoBootstrap` defaults to `true`. `west` wrapper bootstraps
     lazily on first `west` invocation (with confirmation). Set
     `autoBootstrap = false` to make the wrapper check-only and print the
     exact `nix-nrf bootstrap` remediation when something is missing.
   - Other options include `packages`, `extraShellHook`, `inputsFrom`, and
     `toolchainBundleId` for nrfutil. See
     [backends.md](backends.md).

4. Enter the shell and provision:

   ```bash
   nix develop         # or: direnv allow
   nix-nrf bootstrap   # prompts before downloading several GiB
   nix-nrf doctor      # verify environment and probe access
   ```

## After installing

- `nix-nrf doctor` reports environment and probe access without changing state.
- `nix-nrf versions` lists available NCS versions.
- Everyday commands are in the [README](../README.md#everyday-commands).
- [backends.md](backends.md) covers backend behavior and bootstrap.
- [hardware.md](hardware.md) covers probe access, udev, flashing, and recovery.
