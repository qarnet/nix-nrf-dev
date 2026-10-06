# nix/backends/west/versions.nix contains version metadata for the west backend
# prototype. Plain attrset keyed by NCS release. This file owns every
# release-specific version, requirement path, asset URL, and hash; builder
# files (zephyr-sdk.nix, shell.nix) and the setup-helper wrapper select
# metadata by key and contain no release-specific literals.
#
# Zephyr SDK asset hashes are verified against the official v1.0.1 release
# sha256.sum (https://github.com/zephyrproject-rtos/sdk-ng/releases/download/
# v1.0.1/sha256.sum). See docs/development/west-backend-status.md.
#
# Active baseline supports both declared Linux hosts.
{
  "v3.4.1" = {
    ncsVersion = "v3.4.1";
    # West pinned into the version-local venv before workspace creation. After
    # requirement installation the workspace's own west requirement wins; the
    # readiness check never demands this exact version again.
    testedWestVersion = "1.5.0";
    # Nix Python interpreter used to create the version-local venv: display
    # version (`python`) and the pkgs attribute name (`pythonPackage`). The
    # builders select `pkgs.${pythonPackage}`; the display string is for
    # shell banners/messages.
    python = "3.12";
    pythonPackage = "python312";
    zephyrSdk = {
      version = "1.0.1";
      compilerSubdir = "gnu";
      # Compiler archives shipped inside the Nix Zephyr SDK package.
      targets = [
        "arm-zephyr-eabi"
        "riscv64-zephyr-elf"
      ];
      # Per-system official asset URLs and publisher checksums.
      assets = {
        "aarch64-linux" = {
          minimal = {
            url = "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v1.0.1/zephyr-sdk-1.0.1_linux-aarch64_minimal.tar.xz";
            sha256 = "d79c5bfc68e679488659bea289a4026e52a64f03338875c8c9c850fff13cee30";
          };
          toolchains = [
            {
              target = "arm-zephyr-eabi";
              url = "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v1.0.1/toolchain_gnu_linux-aarch64_arm-zephyr-eabi.tar.xz";
              sha256 = "b9805b691f2f0a8926c92694cae378d05ba07b76abca745e216fcc52753cc4d6";
            }
            {
              target = "riscv64-zephyr-elf";
              url = "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v1.0.1/toolchain_gnu_linux-aarch64_riscv64-zephyr-elf.tar.xz";
              sha256 = "7000feff1cdcf872b88bb987696035aab0807b566e9a9842881438187df6e848";
            }
          ];
        };
        "x86_64-linux" = {
          minimal = {
            url = "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v1.0.1/zephyr-sdk-1.0.1_linux-x86_64_minimal.tar.xz";
            sha256 = "ca9bc0ff66fafca1dac9d592a36d953cf16d096a9d09b1c0357f021cf9f6a7eb";
          };
          toolchains = [
            {
              target = "arm-zephyr-eabi";
              url = "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v1.0.1/toolchain_gnu_linux-x86_64_arm-zephyr-eabi.tar.xz";
              sha256 = "21b85981cb5a1818d9bc53d82af80f208946ec038b982ff1907287572ed3a634";
            }
            {
              target = "riscv64-zephyr-elf";
              url = "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v1.0.1/toolchain_gnu_linux-x86_64_riscv64-zephyr-elf.tar.xz";
              sha256 = "01750834c471fbdb335c1b8b8aee17010a1968938957db85640c366235771a38";
            }
          ];
        };
      };
    };
    # Requirement files installed into the version-local venv, relative to the
    # workspace, in declared order.
    requirements = [
      "zephyr/scripts/requirements.txt"
      "nrf/scripts/requirements.txt"
      "bootloader/mcuboot/scripts/requirements.txt"
    ];
    requirementGroups = {
      ncs-extra = {
        requirements = ["nrf/scripts/requirements-extra.txt"];
        imports = ["pygit2"];
        # Nordic's requirements index lacks Linux ARM64 pygit2 distributions.
        # Seed this public package from PyPI before resolving the SDK group;
        # this is an explicit recipe, not an implicit multi-index fallback.
        preinstallRequirements = ["pygit2>=1.15.0"];
      };
      ncs-ci = {
        requirements = ["nrf/scripts/requirements-ci.txt"];
        imports = ["usb.core"];
      };
    };
    readinessImports = ["natsort"];
    # pip constraint lines applied (via `pip install -c`) to every venv pip
    # invocation. Grounds the loose NCS requirement files in NCS's own pinned
    # resolution: v3.4.1 requirements-fixed.txt pins cbor2==5.9.0 for Python 3.12,
    # while nrf/scripts/requirements-build.txt allows cbor2>=5.4.2.post1 and
    # current PyPI resolves 6.x, which breaks zcbor 0.8.1 (cbor2 6 removed
    # the CBORDecodeValueError alias zcbor imports). The exact 5.9.0 pin (not
    # a `<6` range) matches requirements-fixed.txt verbatim and never admits
    # an unverified 5.x release.
    pipConstraints = ["cbor2==5.9.0"];
  };
}
