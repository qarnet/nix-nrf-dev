# Public mkNrfShell factory: validate caller options before backend construction.
# Backend selects tools; source selects ownership. Unsupported host/backend
# requests must fail without silently changing either selection.
# Caller examples and provisioning contracts: docs/backends.md and
# docs/application-types.md. Construction ownership: docs/development/architecture.md.
{
  pkgs,
  openocd-master,
  nrfutil,
  # Internal closure wiring, always supplied by nix/flake/components.nix at the module
  # import: the exact udev-rules package whose store path the shell-specific
  # `nix-nrf doctor` wrapper reports in its remediation
  # (NIX_NRF_DOCTOR_UDEV_RULES). Required here so the wiring can never be
  # silently dropped. It is internal wiring, not a public consumer option;
  # nix/flake/components.nix supplies it before public options are applied.
  udevRules,
  # West backend constructors, always supplied by nix/flake/components.nix at the module
  # import: the version metadata attrset and the builder imports. The west
  # branch of this module constructs per-shell SDK/venv/bootstrap/versions
  # instances from the selected metadata.
  westVersions,
  westZephyrSdkBuilder,
  westBootstrapBuilder,
  westVersionsCommandBuilder,
}: let
  system = pkgs.stdenv.hostPlatform.system;
  platform =
    (import ../platforms.nix).${system}
      or (throw "mkNrfShell: unsupported host '${system}'; supported hosts: x86_64-linux, aarch64-linux");
in
  {
    # Backend that provides the NCS toolchain environment. "nrfutil" is the
    # default (Nordic sdk-manager); "west" is the experimental hybrid backend
    # (Nix Zephyr SDK + host tools + Python, mutable west workspace + venv);
    # "sdk-nrf" remains reserved for a future Nix-native backend and fails
    # evaluation until implemented.
    backend ? "nrfutil",
    # NCS release (e.g. "v3.4.1"). Required: every caller selects a release
    # explicitly. For `backend = "west"` the release must be present in
    # nix/backends/west/versions.nix; unknown releases fail evaluation naming
    # the supported west versions.
    ncsVersion,
    # Source ownership, independent of application location/toolchain backend:
    # { mode = "managed"; } is default. Existing sources use
    # { mode = "workspace"; workspace = "."; }, with a non-empty string anchored
    # at shell-entry CWD. Nix paths are rejected to avoid copying SDK trees.
    # Resolution/checks are read-only; see docs/application-types.md for boundaries.
    source ? {
      mode = "managed";
    },
    # Workspace-mode west only: null selects <workspace>/.venv. A non-empty
    # string selects an existing environment, absolute or relative to workspace.
    # Readiness may run pip check; neither entry nor bootstrap installs or repairs it.
    pythonEnvironment ? null,
    # Optional version-defined SDK Python requirement groups for west only.
    # Managed bootstrap installs them with approval; existing Python is check-only.
    pythonRequirementGroups ? [],
    # Exact patched Nordic toolchain bundle ID (nrfutil backend only). null
    # (omission) selects the newest compatible patched toolchain for
    # `ncsVersion` (via --ncs-version); a non-null value selects that exact
    # bundle (via --toolchain-bundle-id). Rejected for `backend = "west"`.
    toolchainBundleId ? null,
    # Managed-source lazy SDK/toolchain bootstrap: SDK extensions check readiness
    # and install only when something is missing (with
    # confirmation). false switches west to check-only with exact manual
    # remediation; shell entry stays non-mutating either way. Existing workspace
    # sources are never provisioned; its west Python environment is check-only.
    autoBootstrap ? true,
    name ? "nrf-dev",
    # Extra packages for the shell (project-specific tools).
    packages ? [],
    # Multilib GCC for Zephyr native_sim (-m32) host builds on x86_64-linux.
    withMultilib ? platform.multilib,
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
    sourceValid =
      builtins.isAttrs source
      && builtins.all (
        key:
          builtins.elem key [
            "mode"
            "workspace"
          ]
      ) (builtins.attrNames source)
      && builtins.elem (source.mode or null) [
        "managed"
        "workspace"
      ]
      && (
        if source.mode == "workspace"
        then builtins.isString (source.workspace or null) && source.workspace != ""
        else !(source ? workspace)
      );
    sourceConfig = import ./source.nix {inherit pkgs;} {inherit source ncsVersion;};
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
    assert builtins.elem backend platform.backends
    || throw "mkNrfShell: backend '${backend}' is unavailable on ${system}: Nordic SDK toolchain management is not supported on Linux ARM64; select backend = \"west\" explicitly";
    assert !withMultilib
    || platform.multilib
    || throw "mkNrfShell: withMultilib = true is unsupported on ${system}; x86 native_sim -m32 requires x86_64-linux";
    assert sourceValid
    || throw "mkNrfShell: source must be { mode = managed; } or { mode = workspace; workspace = a non-empty string; }; use strings, not Nix paths";
    assert pythonEnvironment
    == null
    || (
      backend
      == "west"
      && source.mode == "workspace"
      && builtins.isString pythonEnvironment
      && pythonEnvironment != ""
    )
    || throw "mkNrfShell: pythonEnvironment requires backend west and source.mode workspace, and must be a non-empty string";
    assert backend != "west" || westReleaseSupported;
    assert builtins.isList pythonRequirementGroups
    && builtins.all builtins.isString pythonRequirementGroups
    || throw "mkNrfShell: pythonRequirementGroups must be a list of group names";
    assert backend
    == "west"
    || pythonRequirementGroups == []
    || throw "mkNrfShell: pythonRequirementGroups requires backend west; Nordic owns bundled Python";
    assert backend
    != "west"
    || builtins.all (
      group: builtins.hasAttr group (westVersions.${ncsVersion}.requirementGroups or {})
    )
    pythonRequirementGroups
    || throw "mkNrfShell: unknown pythonRequirementGroups; supported groups: ${
      builtins.concatStringsSep ", " (
        builtins.attrNames (westVersions.${ncsVersion}.requirementGroups or {})
      )
    }";
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
            sourceConfig
            pythonEnvironment
            pythonRequirementGroups
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
            sourceConfig
            ;
        }
