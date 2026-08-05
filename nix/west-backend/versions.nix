# nix/west-backend/versions.nix — version metadata for the west backend
# prototype. Plain attrset keyed by NCS release. This file owns every
# release-specific version, requirement path, asset URL, and hash; builder
# files (zephyr-sdk.nix, environment.nix) and the setup-helper wrapper select
# metadata by key and contain no release-specific literals.
#
# Zephyr SDK asset hashes are verified against the official v0.17.0 release
# sha256.sum (https://github.com/zephyrproject-rtos/sdk-ng/releases/download/
# v0.17.0/sha256.sum) — see docs/development/west-backend-status.md.
#
# The prototype supports only x86_64-linux; builder files fail clearly on any
# other system.
{
  "v3.3.0" = {
    ncsVersion = "v3.3.0";
    # West pinned into the version-local venv before workspace creation. After
    # requirement installation the workspace's own west requirement wins; the
    # readiness check never demands this exact version again.
    testedWestVersion = "1.4.0";
    # Nix Python interpreter used to create the version-local venv.
    python = "3.12";
    zephyrSdk = {
      version = "0.17.0";
      # Compiler archives shipped inside the Nix Zephyr SDK package.
      targets = [
        "arm-zephyr-eabi"
        "riscv64-zephyr-elf"
      ];
      # Per-system official asset URLs + fixed hashes (x86_64-linux only in
      # this prototype).
      assets = {
        "x86_64-linux" = {
          minimal = {
            url = "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v0.17.0/zephyr-sdk-0.17.0_linux-x86_64_minimal.tar.xz";
            sha256 = "0514d2c684dfb5f6327374bfed0b3dcf727ff1500195d26b3730f98252fed095";
          };
          toolchains = [
            {
              target = "arm-zephyr-eabi";
              url = "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v0.17.0/toolchain_linux-x86_64_arm-zephyr-eabi.tar.xz";
              sha256 = "c3992a788a0896ecc87f7fb3a3be3f234ec0509220bd4e9dbd99b22edd55e97f";
            }
            {
              target = "riscv64-zephyr-elf";
              url = "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v0.17.0/toolchain_linux-x86_64_riscv64-zephyr-elf.tar.xz";
              sha256 = "cd97784c88de0207c93cf386f79d8d2606b46598dc74d4ad12cadd5617595964";
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
    # pip constraint lines applied (via `pip install -c`) to every venv pip
    # invocation. Grounds the loose NCS requirement files in NCS's own pinned
    # resolution: requirements-fixed.txt pins cbor2==5.9.0 for Python 3.12,
    # while nrf/scripts/requirements-build.txt allows cbor2>=5.4.2.post1 and
    # current PyPI resolves 6.x — which breaks zcbor 0.8.1 (cbor2 6 removed
    # the CBORDecodeValueError alias zcbor imports). The exact 5.9.0 pin (not
    # a `<6` range) matches requirements-fixed.txt verbatim and never admits
    # an unverified 5.x release.
    pipConstraints = ["cbor2==5.9.0"];
  };
}
