# Repository-owned nrfutil composition. Nixpkgs supplies the versioned core;
# this module fixes sdk-manager at 1.16.1 because consumer Nixpkgs revisions
# carry incompatible extension versions. The Nordic archive URL names its
# version and fetchurl verifies its content before any binary is installed.
{pkgs}: let
  sdkManagerVersion = "1.16.1";

  sdkManager = pkgs.stdenvNoCC.mkDerivation {
    pname = "nrfutil-sdk-manager";
    version = sdkManagerVersion;

    src = pkgs.fetchurl {
      url = "https://files.nordicsemi.com/artifactory/swtools/external/nrfutil/packages/nrfutil-sdk-manager/nrfutil-sdk-manager-x86_64-unknown-linux-gnu-${sdkManagerVersion}.tar.gz";
      hash = "sha256-0v6X8UP4iKZ5Ij2cbgtR1zDrYLSl9KXa/JcKzSAg/jg=";
    };

    nativeBuildInputs = [pkgs.autoPatchelfHook];
    buildInputs = [
      pkgs.libusb1
      pkgs.segger-jlink-headless
      pkgs.xz
      pkgs.zlib
      pkgs.gcc.cc.lib
    ];

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      mkdir -p "$out"
      mv data/* "$out/"

      runHook postInstall
    '';

    doInstallCheck = true;
    nativeInstallCheckInputs = [pkgs.versionCheckHook];
    versionCheckProgramArg = "--version";
    versionCheckKeepEnvironment = ["HOME"];
    preVersionCheck = ''
      export HOME="$(mktemp -d)"
      export NRFUTIL_HOME="$HOME/.nrfutil"
    '';

    meta =
      pkgs.nrfutil.meta
      // {
        mainProgram = "nrfutil-sdk-manager";
        platforms = ["x86_64-linux"];
      };
  };

  # Preserve Nixpkgs' extension API for callers, but never compose its older
  # sdk-manager beside the repository-pinned manager. A duplicate extension
  # binary would make dispatch depend on PATH order instead of this contract.
  mkNrfutil = requestedExtensions: let
    extensions = pkgs.lib.filter (extension: extension != "nrfutil-sdk-manager") requestedExtensions;
    core = pkgs.nrfutil.withExtensions extensions;
  in
    pkgs.symlinkJoin {
      pname = "nrfutil";
      inherit (core) version;
      paths = [
        core
        sdkManager
      ];
      nativeBuildInputs = [pkgs.makeWrapper];

      # nrfutil dispatches extensions from PATH. The joined package owns the
      # sdk-manager binary, so its bin directory must remain ahead of ambient
      # paths and any core wrapper path.
      postBuild = ''
        wrapProgram "$out/bin/nrfutil" --prefix PATH : "$out/bin"
      '';

      passthru = {
        inherit sdkManager sdkManagerVersion;
        allExtensions = pkgs.nrfutil.allExtensions;
        withExtensions = mkNrfutil;
        withAllExtensions = mkNrfutil pkgs.nrfutil.allExtensions;
      };

      meta =
        pkgs.nrfutil.meta
        // {
          mainProgram = "nrfutil";
        };
    };
in
  mkNrfutil []
