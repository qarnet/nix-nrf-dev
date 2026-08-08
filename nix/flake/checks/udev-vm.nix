# Booted NixOS VM clean-room gate: proves the direct least-intrusive
# `services.udev.packages` activation of the packaged upstream OpenOCD rule
# on a real systemd-udevd, on a system with no project tools installed.
#
# The VM config uses the documented primary path (direct package form, no
# `nixosModules.udevRules` import) plus the explicit `plugdev` host policy
# the upstream rule requires and NixOS does not provide. The test asserts
# activation and a clean system only: no hardware passthrough, no project
# tools, no network dependency, and no real daemon hotplug.
#
# The check also proves synthetic rule semantics: two hand-constructed
# umockdev USB fixtures are replayed with the pinned umockdev preload sandbox
# (0.19.3, referenced by its exact store binary — deliberately not added to
# systemPackages) against the pinned systemd (261.1)
# `udevadm test --action=add --json=short` and the activated
# `/etc/udev/rules.d/60-openocd.rules` tree. The CMSIS-DAP fixture must
# receive the upstream rule's `GROUP="plugdev"`, `MODE="660"`, and
# `TAG+="uaccess"` semantics; the otherwise identical nonmatching control must
# not. JSON is parsed at the NixOS test-driver boundary. `udevadm test` runs
# the real rule engine but never executes `RUN` keys, so queued builtins prove
# rule assignment and command queuing, not resulting ACL application; no
# kernel device enters the VM's device graph.
#
# `udevadm verify --resolve-names=early` runs against the activated rule tree
# with the declared `plugdev` policy: early name resolution fails on
# unresolved group names, so a successful verify proves the activated tree
# resolves the explicit `plugdev` policy end-to-end. This check proves
# acceptance with the declared group only; it does not exercise a host without
# the group.
{
  pkgs,
  nrfUdevRules,
}: let
  # One immutable store fixture per product string, built from the same
  # structure. Format is umockdev-record's: `P:` sysfs path, `N:` device node
  # with hex contents, `E:` udev property, `A:` ASCII sysfs attribute with
  # backslash escaping (`\n` decodes to a newline). The USB identity is
  # hand-constructed to be XIAO-compatible (Seeed Studio vendor/product ids
  # and a CMSIS-DAP-style interface): the upstream rule matches on the generic
  # `ATTRS{product}=="*CMSIS-DAP*"` semantics, so a synthetic XIAO identity is
  # required to exercise it. No data is captured from a physical device.
  mkUsbFixture = name: product:
    pkgs.writeText name ''
      P: /devices/virtual/usb/usb1/1-9
      N: bus/usb/001/009=1201000200000040862866000102030101
      E: BUSNUM=001
      E: DEVNAME=/dev/bus/usb/001/009
      E: DEVNUM=009
      E: DEVTYPE=usb_device
      E: MAJOR=189
      E: MINOR=8
      E: PRODUCT=2886/66/100
      E: SUBSYSTEM=usb
      A: busnum=1\n
      A: dev=189:8
      A: devnum=9\n
      A: idProduct=0066
      A: idVendor=2886
      A: manufacturer=Seeed Studio
      A: product=${product}
      A: serial=8EE9B3FF

      P: /devices/virtual/usb/usb1/1-9/1-9:1.0
      E: DEVTYPE=usb_interface
      E: DRIVER=usbfs
      E: INTERFACE=255/0/0
      E: MODALIAS=usb:v2886p0066d0100dc00dsc00dp00icFFisc00ip00in00
      E: PRODUCT=2886/66/100
      E: SUBSYSTEM=usb
      A: bAlternateSetting= 0
      A: bInterfaceClass=ff
      A: bInterfaceNumber=00
      A: bInterfaceProtocol=00
      A: bInterfaceSubClass=00
      A: bNumEndpoints=02
      A: modalias=usb:v2886p0066d0100dc00dsc00dp00icFFisc00ip00in00
    '';

  # Positive fixture matches the upstream `ATTRS{product}=="*CMSIS-DAP*"` line;
  # the control differs only in product text and must match nothing.
  fixtureCmsisDap = mkUsbFixture "xiao-cmsis-dap.umockdev" "Seeed Studio XIAO nrf54 CMSIS-DAP";
  fixtureControl = mkUsbFixture "xiao-control.umockdev" "Seeed Studio XIAO nrf54 Debug Probe";
in {
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
      import json
      import shlex

      start_all()

      def synthetic_event_json(fixture, product, label):
          # Replay one fixture through the pinned umockdev preload sandbox and
          # the real pinned `udevadm test` rules engine against the activated
          # rule tree. `umockdev-run` is referenced by its exact store binary,
          # not added to systemPackages, so the clean-system PATH assertions
          # stay meaningful. The product string travels via the environment;
          # diagnostics go to a temporary log and stdout carries only the JSON.
          script = (
              "PRODUCT="
              + shlex.quote(product)
              + " ${pkgs.umockdev.bin}/bin/umockdev-run --device="
              + fixture
              + " -- sh -c 'test \"$(cat /sys/devices/virtual/usb/usb1/1-9/product)\" = \"$PRODUCT\""
              + " || { echo \"synthetic product mismatch\" >/tmp/udevadm-diag.log; exit 1; };"
              + " exec udevadm test --action=add --json=short"
              + " /sys/devices/virtual/usb/usb1/1-9 2>>/tmp/udevadm-diag.log'"
              + " || { echo \"--- udevadm diagnostics ---\"; cat /tmp/udevadm-diag.log; exit 1; }"
          )
          status, out = machine.execute(script)
          if status != 0:
              raise RuntimeError(
                  "udevadm test failed for %s (exit %d):\n%s" % (label, status, out)
              )
          return json.loads(out)

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

      with subtest("synthetic CMSIS-DAP device receives upstream rule semantics"):
          result = synthetic_event_json(
              "${fixtureCmsisDap}",
              "Seeed Studio XIAO nrf54 CMSIS-DAP",
              "CMSIS-DAP fixture",
          )
          # fixture identity: the expected synthetic USB device, not another node
          assert result["path"] == "/devices/virtual/usb/usb1/1-9", result
          assert result["subsystem"] == "usb", result
          assert result["type"] == "usb_device", result
          assert result["node"]["path"] == "/dev/bus/usb/001/009", result
          # upstream rule outcomes: plugdev group, 0660 mode, uaccess semantics
          assert result["node"]["owner"]["groupName"] == "plugdev", result
          assert result["node"]["mode"] == "0660", result
          assert "uaccess" in result.get("tags", []), result
          assert "uaccess" in result.get("currentTags", []), result
          # queued (not executed) uaccess builtin from the merged 73-seat-late rules
          assert any(
              c.get("type") == "builtin" and c.get("command") == "uaccess"
              for c in result.get("queuedCommands", [])
          ), result

      with subtest("nonmatching control device receives no project rule outcomes"):
          control = synthetic_event_json(
              "${fixtureControl}",
              "Seeed Studio XIAO nrf54 Debug Probe",
              "control fixture",
          )
          assert control["path"] == "/devices/virtual/usb/usb1/1-9", control
          assert control["subsystem"] == "usb", control
          assert control["type"] == "usb_device", control
          node = control.get("node", {})
          assert node.get("owner", {}).get("groupName") != "plugdev", control
          assert node.get("mode") != "0660", control
          assert "uaccess" not in control.get("tags", []), control
          assert "uaccess" not in control.get("currentTags", []), control
          assert not any(
              c.get("type") == "builtin" and c.get("command") == "uaccess"
              for c in control.get("queuedCommands", [])
          ), control

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
