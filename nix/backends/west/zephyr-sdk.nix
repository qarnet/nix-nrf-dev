# nix/backends/west/zephyr-sdk.nix assembles the exact Zephyr SDK package from
# official release assets, selected by version metadata (see versions.nix).
#
# The minimal distribution bundle plus the selected compiler archives are
# unpacked into one store path matching the official SDK directory layout:
#
#   $out/sdk_version, $out/sdk_gnu_toolchains, $out/cmake/, $out/gnu/<target>/...
#
# so ZEPHYR_SDK_INSTALL_DIR can point straight at $out. The interactive
# setup/registration script and the host-tools installer are removed; there is
# no CMake package-registry registration (the environment exports
# ZEPHYR_SDK_INSTALL_DIR instead) and no installer runs during the build.
# The derivation builds inside the Nix sandbox, which has no network.
#
# Supported hosts and archive layout come from version metadata.
{
  pkgs,
  # Zephyr SDK metadata entry (versions.nix `zephyrSdk` attr): version,
  # targets, assets.<system>.{minimal,toolchains}.
  sdk,
}: let
  assets =
    sdk.assets.${pkgs.stdenv.hostPlatform.system}
      or (throw "no Zephyr SDK assets for ${pkgs.stdenv.hostPlatform.system} in west-backend metadata");
  fetch = asset:
    pkgs.fetchurl {
      inherit (asset) url sha256;
    };
  minimal = fetch assets.minimal;
  toolchains = map fetch assets.toolchains;
  compilerSubdir = sdk.compilerSubdir or "";
  compilerRoot =
    if compilerSubdir == ""
    then "$out"
    else "$out/${compilerSubdir}";
  cmakeSubdir =
    if compilerSubdir == ""
    then ""
    else "/${compilerSubdir}";
  # Each toolchain archive already carries <target>/ at the top level (with
  # the <target>/<target>/ sysroot nested inside, as the CMake package
  # expects: SYSROOT_DIR = <SDK>/gnu/<target>/<target>), so unpack WITHOUT
  # stripping into the selected compiler root.
  unpackToolchains = pkgs.lib.concatStringsSep "\n" (
    map (t: "tar -xf ${t} -C \"${compilerRoot}\"") toolchains
  );
  # Compiler binaries that must execute --version inside the build.
  checkCompilers = pkgs.lib.concatStringsSep "\n" (
    map (target: ''
      test -x "${compilerRoot}/${target}/bin/${target}-gcc" || {
        echo "zephyr-sdk validation: missing ${target} compiler at ${compilerRoot}/${target}/bin/${target}-gcc" >&2
        exit 1
      }
      "${compilerRoot}/${target}/bin/${target}-gcc" --version >/dev/null || {
        echo "zephyr-sdk validation: ${target} compiler failed --version" >&2
        exit 1
      }
      echo "zephyr-sdk validation: ${target} compiler OK" >&2
    '')
    sdk.targets
  );
in
  pkgs.stdenv.mkDerivation {
    pname = "zephyr-sdk";
    inherit (sdk) version;

    nativeBuildInputs = [
      pkgs.autoPatchelfHook
      pkgs.xz
    ];
    buildInputs = [
      pkgs.gcc-unwrapped.lib
      pkgs.libxcrypt
      pkgs.ncurses
      pkgs.python312
    ];
    # SDK 1.0.1 links Python-enabled GDB to Python 3.12. Keep any unsupported
    # legacy crypt dependency visible during executable qualification.
    autoPatchelfIgnoreMissingDeps = [
      "libcrypt.so.1"
    ];

    # Archives are unpacked manually in installPhase (the official archives
    # carry different top-level layouts), so the default unpackPhase no-ops.
    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      # Minimal bundle: strip the single top-level zephyr-sdk-<version>/ dir.
      tar -xf ${minimal} -C "$out" --strip-components=1
      mkdir -p "${compilerRoot}"
      # Selected compiler archives, one <target>/ dir each.
      ${unpackToolchains}
      # Remove the interactive setup/registration script and the host-tools
      # installer: this package never registers the SDK in a CMake package
      # registry and never downloads anything at build time.
      rm -f "$out/setup.sh" "$out"/zephyr-sdk-*-hosttools-standalone-*.sh
      rm -f "$out"/hosttools/zephyr-sdk-*-hosttools-standalone-*.sh
      runHook postInstall
    '';

    postInstall = ''
      # Validation: sdk_version matches the metadata version.
      test "$(cat "$out/sdk_version")" = "${sdk.version}" || {
        echo "zephyr-sdk validation: sdk_version mismatch: '$(cat "$out/sdk_version")' != '${sdk.version}'" >&2
        exit 1
      }
      # Validation: CMake package files exist.
      test -f "$out/cmake/Zephyr-sdkConfig.cmake" || {
        echo "zephyr-sdk validation: missing cmake/Zephyr-sdkConfig.cmake" >&2
        exit 1
      }
      test -f "$out/cmake/Zephyr-sdkConfigVersion.cmake" || {
        echo "zephyr-sdk validation: missing cmake/Zephyr-sdkConfigVersion.cmake" >&2
        exit 1
      }
      test -f "$out/cmake/zephyr${cmakeSubdir}/generic.cmake" || {
        echo "zephyr-sdk validation: missing cmake/zephyr${cmakeSubdir}/generic.cmake" >&2
        exit 1
      }
      test -f "$out/cmake/zephyr${cmakeSubdir}/target.cmake" || {
        echo "zephyr-sdk validation: missing cmake/zephyr${cmakeSubdir}/target.cmake" >&2
        exit 1
      }
      # Validation: interactive installer scripts must not remain in the
      # output (they would prompt/download if executed).
      test ! -e "$out/setup.sh" || {
        echo "zephyr-sdk validation: setup.sh still present in output" >&2
        exit 1
      }
      echo "zephyr-sdk validation: sdk_version, CMake package files OK" >&2
    '';

    # Setup hook: any consumer that puts this package in buildInputs gets the
    # Zephyr toolchain variables without running the SDK's interactive setup.
    postFixup = ''
      mkdir -p "$out/nix-support"
      cat > "$out/nix-support/setup-hook" <<EOF
      export ZEPHYR_TOOLCHAIN_VARIANT=zephyr
      export ZEPHYR_SDK_INSTALL_DIR=$out
      EOF
    '';

    # Compiler execution validation must run after fixupPhase, when
    # auto-patchelf (registered as a postFixup hook, i.e. after this
    # derivation's own postFixup) has rewritten the SDK binaries' ELF
    # interpreters from /lib64/ld-linux-x86-64.so.2 to the Nix glibc and
    # added RPATHs for their runtime libraries. Inside the build sandbox
    # there is no /lib64, so unpatched binaries cannot execute here.
    doInstallCheck = true;
    installCheckPhase = ''
      # Validation: compiler binaries execute --version.
      ${checkCompilers}
      echo "zephyr-sdk validation: compilers OK" >&2
    '';

    meta = {
      description = "Exact Zephyr SDK ${sdk.version} (minimal bundle + selected compiler archives) from official release assets";
      homepage = "https://github.com/zephyrproject-rtos/sdk-ng";
      license = pkgs.lib.licenses.asl20;
      platforms = builtins.attrNames sdk.assets;
    };
  }
