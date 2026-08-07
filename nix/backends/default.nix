# mkNrfShell — devShell factory for nRF Connect SDK projects.
#
# Two backends provide the NCS toolchain environment:
#
# nrfutil (default): provides openocd-master (wrapped), the nix-nrf CLI
# facade (which owns the internal `nix-nrf probes`, `nix-nrf bootstrap`, and
# `nix-nrf doctor` command modules), the packaged nrfutil with the sdk-manager
# extension, multilib GCC (for native_sim -m32 builds), a scoped-env `west`
# wrapper with lazy SDK/toolchain bootstrap, and ZEPHYR_BASE derivation. The
# shell-specific `nix-nrf doctor` carries the exact udev-rules package path
# (internal `udevRules` closure wiring from nix/flake/components.nix).
#
#   Scoped toolchain env: Nordic's `nrfutil sdk-manager toolchain env` script
#   exports PYTHONHOME, PYTHONPATH, LD_LIBRARY_PATH, GIT_EXEC_PATH, ... —
#   variables that break any non-toolchain tool run from the same shell (nix
#   itself fails to load shared libraries, nix-store pythons pick up the
#   wrong stdlib, git may misbehave). Instead of eval'ing that script into
#   the whole shell, the `west` wrapper evals it only inside west's process
#   tree. Builds still see the full
#   toolchain because cmake/ninja/gcc are spawned by west.
#
#   Lazy bootstrap: the `west` wrapper invokes the shell-specific
#   `nix-nrf bootstrap --print-sdk-path` on every call. That checks the
#   configured NCS SDK source and selected toolchain, installs only when
#   something is missing (with interactive confirmation unless
#   NIX_NRF_BOOTSTRAP_YES=1 / `--yes`), and returns the absolute SDK root for
#   ZEPHYR_BASE. With `autoBootstrap = false` it only checks and, when anything
#   is missing, reports that automatic bootstrap is disabled plus the exact
#   `nix-nrf bootstrap` remediation — it never mutates. The shell hook itself
#   stays non-mutating (read-only `--check` path).
#
# west (experimental; v3.3.0 / x86_64-linux only): Nix owns the exact Zephyr
# SDK package, host tools, and the metadata-selected Python interpreter; the
# official mutable west workspace and a version-local venv own the NCS source,
# west, and workspace Python requirements (see nix/backends/west/). No
# nrfutil/sdk-manager participates. `nix-nrf versions`, `nix-nrf bootstrap`,
# and `nix-nrf doctor` become backend-aware via exact west command modules.
# `toolchainBundleId` and non-default `nrfutilPackage` overrides are rejected
# for west; `autoBootstrap`, `name`, `packages`, `withMultilib`,
# `extraShellHook`, and `inputsFrom` behave like the nrfutil backend.
#
# The NCS release is a required argument for both backends: every caller
# selects a release explicitly (no "latest" alias or default).
#
# Usage from a consumer flake:
#   devShells.default = nix-nrf-dev.lib.${system}.mkNrfShell {
#     backend = "nrfutil";
#     ncsVersion = "v3.3.0";
#   };
#
# West backend (experimental, metadata-supported releases only):
#   devShells.default = nix-nrf-dev.lib.${system}.mkNrfShell {
#     backend = "west";
#     ncsVersion = "v3.3.0";
#   };
#
# Advanced callers may replace the composed nrfutil derivation (which must
# still provide `nrfutil` with the sdk-manager extension):
#   devShells.default = nix-nrf-dev.lib.${system}.mkNrfShell {
#     backend = "nrfutil";
#     ncsVersion = "v3.3.0";
#     nrfutilPackage = myNrfutil;
#   };
#
# Hybrid consumers may compose additional derivations via inputsFrom:
#   devShells.default = nix-nrf-dev.lib.${system}.mkNrfShell {
#     backend = "nrfutil";
#     ncsVersion = "v3.3.0";
#     inputsFrom = [ myPackage ];
#   };
{
  pkgs,
  openocd-master,
  nrfutil,
  # Internal closure wiring, always supplied by nix/flake/components.nix at the module
  # import: the exact udev-rules package whose store path the shell-specific
  # `nix-nrf doctor` wrapper reports in its remediation
  # (NIX_NRF_DOCTOR_UDEV_RULES). Required here so the wiring can never be
  # silently dropped — it is not a public consumer option; the public
  # `mkNrfShell { ... }` call signature is unchanged (only
  # nix/flake/components.nix imports this module).
  udevRules,
  # West backend constructors, always supplied by nix/flake/components.nix at the module
  # import: the version metadata attrset and the builder imports. The west
  # branch of this module constructs per-shell SDK/venv/bootstrap/versions
  # instances from the selected metadata; the builders contain no
  # release-specific literals.
  westVersions,
  westZephyrSdkBuilder,
  westBootstrapBuilder,
  westVersionsCommandBuilder,
}: {
  # Backend that provides the NCS toolchain environment. "nrfutil" is the
  # default (Nordic sdk-manager); "west" is the experimental hybrid backend
  # (Nix Zephyr SDK + host tools + Python, mutable west workspace + venv);
  # "sdk-nrf" remains reserved for a future Nix-native backend and fails
  # evaluation until implemented.
  backend ? "nrfutil",
  # NCS release (e.g. "v3.3.0"). Required: every caller selects a release
  # explicitly. For `backend = "west"` the release must be present in
  # nix/backends/west/versions.nix; unknown releases fail evaluation naming
  # the supported west versions.
  ncsVersion,
  # Exact patched Nordic toolchain bundle ID (nrfutil backend only). null
  # (omission) selects the newest compatible patched toolchain for
  # `ncsVersion` (via --ncs-version); a non-null value selects that exact
  # bundle (via --toolchain-bundle-id). Rejected for `backend = "west"`.
  toolchainBundleId ? null,
  # Lazy SDK/toolchain bootstrap: `west` checks the selection on every
  # invocation and installs only when something is missing (with
  # confirmation). false switches west to check-only with exact manual
  # remediation; shell entry stays non-mutating either way.
  autoBootstrap ? true,
  name ? "nrf-dev",
  # Extra packages for the shell (project-specific tools).
  packages ? [],
  # Multilib GCC for Zephyr native_sim (-m32) host builds on x86_64-linux.
  withMultilib ? true,
  # Appended after the environment setup.
  extraShellHook ? "",
  # Additional derivations whose environment to compose (propagated directly
  # to pkgs.mkShell). Use this for hybrid projects that need Node, Python,
  # or other non-Nordic tooling alongside the NCS toolchain.
  inputsFrom ? [],
  # Composed nrfutil derivation used for every nrfutil invocation and shell
  # inclusion (west wrapper, nix-nrf versions/bootstrap subcommands). Defaults
  # to the repository's packaged nrfutil with the sdk-manager extension;
  # advanced callers may supply another compatible derivation. Rejected for
  # `backend = "west"` (no nrfutil participates).
  nrfutilPackage ? nrfutil,
}: let
  # Backend selector: exact-match only, no aliases, no silent fallback.
  supportedBackends = [
    "nrfutil"
    "west"
  ];
  supportedBackendsMsg = builtins.concatStringsSep ", " supportedBackends;
  # Throws with the invalid value and the supported list; the assert below
  # forces it whenever the returned shell derivation is evaluated.
  backendSupported =
    builtins.elem backend supportedBackends
    || throw "mkNrfShell: unsupported backend '${backend}'; supported backends: ${supportedBackendsMsg}";

  # West release resolution: only forced when backend == "west" (the nrfutil
  # branch never evaluates it). Fails evaluation for unknown releases and
  # names the supported west versions.
  westSupportedMsg = builtins.concatStringsSep ", " (
    builtins.sort builtins.lessThan (builtins.attrNames westVersions)
  );
  westReleaseSupported =
    builtins.hasAttr ncsVersion westVersions
    || throw "mkNrfShell: west backend: unknown NCS release '${ncsVersion}'; supported west releases: ${westSupportedMsg}";
  # Backend constructors, imported once here: each owns its branch
  # construction. The nrfutil backend receives the shared nix-nrf
  # constructor; the west backend receives its metadata and builders.
  nrfutilBackend = import ./nrfutil/default.nix {
    inherit
      pkgs
      openocd-master
      nrfutil
      udevRules
      ;
    nixNrf = import ../commands/default.nix;
  };
  westBackend = import ./west/default.nix {
    inherit
      pkgs
      openocd-master
      udevRules
      westVersions
      westZephyrSdkBuilder
      westBootstrapBuilder
      westVersionsCommandBuilder
      ;
  };
in
  # Force backend validation when the returned shell derivation is
  # evaluated: unsupported values fail Nix evaluation instead of silently
  # falling back to nrfutil. West-specific restrictions (unknown release,
  # toolchainBundleId, non-default nrfutilPackage) are asserted only in the
  # selected west branch, so the nrfutil branch keeps today's behavior.
  assert backendSupported;
  assert backend != "west" || westReleaseSupported;
  assert backend
  != "west"
  || toolchainBundleId == null
  || throw "mkNrfShell: backend 'west' does not support toolchainBundleId (Nix owns the exact Zephyr SDK; the west workspace/venv own the source)";
  assert backend
  != "west"
  || (nrfutilPackage != null && nrfutilPackage.outPath == nrfutil.outPath)
  || throw "mkNrfShell: backend 'west' does not support a non-default nrfutilPackage override (no nrfutil participates in the west backend)";
    if backend == "west"
    then
      westBackend {
        inherit
          ncsVersion
          autoBootstrap
          name
          packages
          withMultilib
          extraShellHook
          inputsFrom
          ;
      }
    else
      nrfutilBackend {
        inherit
          ncsVersion
          toolchainBundleId
          autoBootstrap
          name
          packages
          withMultilib
          extraShellHook
          inputsFrom
          nrfutilPackage
          ;
      }
