# Choose tools and SDK sources separately

An application can live inside an SDK repository, elsewhere in a west workspace,
or outside that workspace. You do not need a different toolchain backend for each
layout. Choose **tools** with `backend`, then choose **SDK sources** with `source`.

| Choice | Meaning |
| --- | --- |
| `backend = "nrfutil"` | Use Nordic's selected toolchain bundle, scoped to west and its children |
| `backend = "west"` | Use the Nix-packaged compiler SDK and a prepared Python environment; experimental, NCS v3.3.0 only |
| `source.mode = "managed"` | Let the backend manage its SDK workspace; current default |
| `source.mode = "workspace"` | Use an existing workspace that you own; do not download or update its sources |

Host regression tests cover source routing through both backends with real west
and CMake. A separate [16-case firmware matrix](development/application-source-status.md)
passed for NCS v3.3.0 and `xiao_nrf54l15/nrf54l15/cpuapp`, covering all layouts and
single-image/sysbuild with both backends. Other boards, releases, and arbitrary
consumer manifests are not inferred from those results.
The opt-in [firmware matrix](../tests/application-types/README.md) records actual
source/compiler/module selections with already prepared application fixtures.

## Keep the current managed workflow

Existing configurations need no changes:

```nix
nix-nrf-dev.lib.x86_64-linux.mkNrfShell {
  backend = "nrfutil";
  ncsVersion = "v3.3.0";
  # source = { mode = "managed"; }; # optional; this is the default
}
```

`nix-nrf bootstrap` manages SDK sources and tools as before. Change `backend` to
`"west"` for its managed west workspace and Python venv. See [Backends](backends.md)
for provisioning, approval, and release restrictions.

## Use your own existing workspace

Example layout, with the flake at the workspace root:

```text
product-workspace/
├── .west/config
├── flake.nix
├── product/
│   ├── west.yml
│   └── app/
├── nrf/
├── zephyr/
└── modules/...
```

The project manifest and checked-out repositories own the source revisions.
Initialize and populate this workspace explicitly before using workspace mode;
shell entry and `nix-nrf bootstrap` will not run `west init` or `west update` for it.

Use Nordic tools without requiring another sdk-manager SDK source installation:

```nix
nix-nrf-dev.lib.x86_64-linux.mkNrfShell {
  backend = "nrfutil";
  ncsVersion = "v3.3.0";
  source = {
    mode = "workspace";
    workspace = ".";
  };
}
```

Use the same sources with Nix compiler tools:

```nix
nix-nrf-dev.lib.x86_64-linux.mkNrfShell {
  backend = "west";
  ncsVersion = "v3.3.0";
  source = {
    mode = "workspace";
    workspace = ".";
  };
  # pythonEnvironment = ".venv"; # default in workspace mode
}
```

`workspace` is a **string**, not a Nix path. Use `"."`, `".."`, or an absolute
string such as `"/home/me/product-workspace"`. Relative strings are anchored at
the directory where you enter the shell, then stay fixed when you change directory.
For a flake entered from `product/`, use `workspace = ".."` in this layout.
Do not pass `workspace = ./.`: Nix paths can copy a large SDK checkout into the store.
Zephyr firmware builds do not support spaces in SDK/application paths; diagnostic
quoting tests do not establish build support for such paths.

The manifest must identify a project named `zephyr`. A project named `nrf`, or
the SDK's own Nordic manifest repository, must provide `Kconfig.nrf` and `VERSION`.
Nonstandard paths such as `vendor/rtos` are resolved from the manifest. Zephyr and
Nordic source projects, including resolved symlink targets, must stay inside the
selected workspace. Missing imports or source files fail without fetching them.

`ncsVersion` remains the explicit source/toolchain compatibility baseline.
Nordic's `VERSION` must match it. A fork retaining that version is allowed; source
diagnostics report Git revisions separately. This is not a complete dependency
lock or a guarantee that arbitrary modifications work with the selected tools.

## Python and bootstrap ownership

For **nrfutil + existing workspace**, `nix-nrf bootstrap` only provisions a missing
Nordic toolchain, after approval. It never installs another SDK source tree or
registers CMake packages. The toolchain bundle supplies normal SDK Python tools;
additional project dependencies remain your responsibility.

For **west + existing workspace**, prepare the Python environment yourself.
`nix-nrf bootstrap`, even with `--yes`, only checks it and the sources; it does not
repair a venv or run pip. The default location is `<workspace>/.venv`.
`pythonEnvironment` may select another existing environment; relative strings
resolve from the workspace root, not the application directory. This option is
only valid with the west backend and workspace source mode.

For a conventional NCS v3.3.0 workspace, enter its west-backend shell, confirm the
provided Python version, and then prepare dependencies explicitly:

> These commands create a Python environment and download/install packages.
> Review them before running. They do not initialize or update source repositories.

```bash
python3 --version              # this backend provides Python 3.12 for NCS v3.3.0
env -u PYTHONHOME -u PYTHONPATH python3 -m venv .venv
env -u PYTHONHOME -u PYTHONPATH .venv/bin/python -m pip install \
  -r zephyr/scripts/requirements-base.txt \
  -r nrf/scripts/requirements-base.txt \
  -r nrf/scripts/requirements-build.txt \
  -r bootloader/mcuboot/scripts/requirements.txt \
  'cbor2==5.9.0' 'west==1.5.0'
nix-nrf bootstrap --check
```

These are build profiles; the two explicit pins match NCS v3.3.0's fixed
requirements. Use your SDK's own versions for another release. Clearing foreign
Python variables applies only to pip's child process, not the surrounding shell.
For the larger SDK-wide pinned environment, install
`nrf/scripts/requirements-fixed.txt` with `-r`, not `-c`: its extras are invalid
in pip constraints. Nordic mirror outages are dependency-supply errors, not a
reason to change SDK pins. Adjust paths and add project-specific requirements. Do not
activate this environment globally: the west wrapper selects it for child
processes. Both backends preserve the parent shell's loader, Python, and Git
environment; every west build receives its selected toolchain.

## Build any application layout

All examples below use the same selected SDK workspace. Choose a board supported
by your sources; these examples use the repository's NCS v3.3.0 baseline.

```bash
# Zephyr repository application:
west build --no-sysbuild -b xiao_nrf54l15/nrf54l15/cpuapp \
  -d build/hello zephyr/samples/hello_world

# Project workspace application:
west build --sysbuild -b xiao_nrf54l15/nrf54l15/cpuapp \
  -d build/product product/app

# Freestanding application, outside the selected workspace:
west build --no-sysbuild -b xiao_nrf54l15/nrf54l15/cpuapp \
  -d build/experiment /home/me/experiment
```

NCS repository applications under `nrf/` work with the same selection. If you
relocate the SDK projects, use their actual paths in commands. For new production
projects, prefer a workspace application rather than adding files to a shared
sdk-manager installation.

NCS v3.3.0 enables sysbuild by default. Explicit `--sysbuild`/`--no-sysbuild` makes
your intended workflow clear. Use fresh build directories when changing source
workspaces. This wrapper rejects detected conflicting caches rather than deleting
them, even if `-p always` is requested. With a templated `build.dir-fmt`, specify
`--build-dir` explicitly so cache validation does not guess a directory.

## Source discovery and troubleshooting

Workspace-mode parent shells do not export `ZEPHYR_BASE` or `Zephyr_DIR`. The west
child gets a validated base, package directory, and explicit `-z`, so plain
`find_package(Zephyr)` works without registry export and west need not persist
a `zephyr.base` setting.
No automatic `west zephyr-export` is performed.

```bash
nix-nrf source --json           # workspace mode only; source identity, no probe access
nix-nrf bootstrap --check       # source/toolchain or Python readiness
nix-nrf doctor --json           # combined environment and host probe-access diagnostics
```

- **Conflicting `ZEPHYR_BASE` or `Zephyr_DIR`:** unset stale variables before
  entering the shell. A matching base is accepted, then removed from the parent
  environment. Conflicts remain errors, not silent overrides.
- **Wrong west workspace in current directory:** leave that other workspace.
  You can build from the selected workspace or an unrelated freestanding directory,
  but cannot silently mix its manifest with another workspace's extension commands.
- **Conflicting `zephyr.base`:** correct your west configuration explicitly so it
  agrees with the manifest project. The resolver does not rewrite configuration.
- **Missing sources/imports:** populate your project workspace explicitly. Changing
  toolchain backend does not acquire source repositories.
- **Missing Python tools:** prepare the selected environment and its dependencies.
  A structural/import check is not proof that every board or custom module will build.
- **Stale build cache:** use a new build directory; perform any desired cleanup
  separately and deliberately. Default and immediate sysbuild image caches are checked;
  arbitrary custom build layouts are not a universal cache-validation guarantee.

Zephyr source discovery is different from compiler SDK discovery.
`west zephyr-export` registers source packages, while `ZEPHYR_SDK_INSTALL_DIR`
selects the compiler SDK. Direct outer-shell CMake is not a scoped Nordic-toolchain
execution interface; use west for these supported workflows. Initializer manifest
scaffolding and automatic source acquisition are not part of workspace mode.
