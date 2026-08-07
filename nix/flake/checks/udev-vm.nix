# Booted NixOS VM clean-room gate: proves the direct least-intrusive
# `services.udev.packages` activation of the packaged upstream OpenOCD rule
# on a real systemd-udevd, on a system with no project tools installed.
#
# The VM config uses the documented primary path (direct package form, no
# `nixosModules.udevRules` import) plus the explicit `plugdev` host policy
# the upstream rule requires and NixOS does not provide. The test asserts
# activation and a clean system only: no synthetic USB device, no USB-gadget
# or device-event semantics — those are out of scope for this phase.
#
# `udevadm verify --resolve-names=early` is deliberately used against the
# activated rule: with early name resolution the pinned systemd (261.1)
# rejects the rule when `plugdev` does not exist and accepts it once the
# group does, proving NSS group resolution end-to-end.
{
  pkgs,
  nrfUdevRules,
}: {
  udev-vm = pkgs.testers.runNixOSTest {
    name = "nix-nrf-udev-vm";

    nodes.machine = _: {
      system.stateVersion = "26.11";

      # Upstream 60-openocd.rules assigns MODE="660", GROUP="plugdev",
      # TAG+="uaccess"; NixOS does not create `plugdev`, so the test host
      # declares the group and membership explicitly (the documented
      # host-policy contract).
      users.groups.plugdev = {};
      users.users.tester = {
        isNormalUser = true;
        extraGroups = ["plugdev"];
      };

      # Direct, least-intrusive integration (docs/hardware.md primary
      # path). No named module, no systemPackages additions, no project
      # tools or services, no network/hardware passthrough.
      services.udev.packages = [nrfUdevRules];
    };

    testScript = ''
      start_all()

      with subtest("systemd-udevd is active and reactive"):
          machine.wait_for_unit("systemd-udevd.service")
          machine.succeed("systemctl is-active systemd-udevd.service")
          machine.succeed("udevadm control --reload")
          machine.succeed("udevadm trigger")

      with subtest("packaged rule activated byte-identically from store tree"):
          machine.succeed("readlink -f /etc/udev/rules.d | grep -q '^/nix/store/'")
          machine.succeed("test -f /etc/udev/rules.d/60-openocd.rules")
          machine.succeed("test ! -L /etc/udev/rules.d/60-openocd.rules")
          machine.succeed("cmp -s /etc/udev/rules.d/60-openocd.rules ${nrfUdevRules}/lib/udev/rules.d/60-openocd.rules")
          machine.succeed("grep -F 'MODE=\"660\"' /etc/udev/rules.d/60-openocd.rules")
          machine.succeed("grep -F 'GROUP=\"plugdev\"' /etc/udev/rules.d/60-openocd.rules")
          machine.succeed("grep -F 'TAG+=\"uaccess\"' /etc/udev/rules.d/60-openocd.rules")
          machine.succeed("grep -F 'ATTRS{product}==\"*CMSIS-DAP*\"' /etc/udev/rules.d/60-openocd.rules")

      with subtest("explicit plugdev host policy"):
          machine.succeed("getent group plugdev | grep -q tester")
          machine.succeed("id tester | grep -q plugdev")
          machine.succeed("udevadm verify --resolve-names=early /etc/udev/rules.d/60-openocd.rules")

      with subtest("whole merged rules tree verifies with early name resolution"):
          machine.succeed("udevadm verify --resolve-names=early /etc/udev/rules.d/*.rules")

      with subtest("clean system: no project tools"):
          machine.fail("command -v nix-nrf")
          machine.fail("command -v nrfutil")
          machine.fail("command -v openocd")
          machine.succeed("test ! -e /run/current-system/sw/bin/nix-nrf")
          machine.succeed("test ! -e /run/current-system/sw/bin/nrfutil")
          machine.succeed("test ! -e /run/current-system/sw/bin/openocd")

      with subtest("clean system: no nix-nrf units or rule files"):
          # systemctl itself must work before absence can be concluded;
          # every absence check is exit-guarded (`&&`) so a failed
          # systemctl cannot masquerade as an empty result. Loaded units
          # use the working `list-units --all --no-legend PATTERN` form;
          # unit FILES are checked at the filesystem level because on the
          # pinned systemd 261.1 `systemctl list-unit-files` with a pattern
          # argument exits nonzero (observed), which the plain listing
          # cannot be trusted around. NixOS materializes all units under
          # /etc/systemd/system or /run/systemd/system, so the find covers
          # every unit source.
          machine.succeed("systemctl --version")
          machine.succeed("units=$(systemctl list-units --all --no-legend '*nix-nrf*.service') && test -z \"$units\"")
          machine.succeed("unitpaths=$(find /etc/systemd/system /run/systemd/system -name '*nix-nrf*.service') && test -z \"$unitpaths\"")
          machine.succeed("merged=$(find /etc/udev/rules.d -maxdepth 1 -name '*nix-nrf*') && test -z \"$merged\"")
    '';
  };
}
