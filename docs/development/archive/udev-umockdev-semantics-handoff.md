# Phase 9 Handoff: umockdev Udev Semantics Gate

## Goal

Promote the successful umockdev feasibility spike into the existing offline
NixOS udev VM check. Prove through the real activated udev rules engine that a
synthetic CMSIS-DAP USB device receives the upstream OpenOCD rule's
`GROUP="plugdev"`, `MODE="660"`, and `TAG+="uaccess"` semantics, while an
otherwise equivalent non-CMSIS-DAP device does not.

Commit this phase after all requested verification passes. Do not push.

## Scope

### In scope

- Extend `nix/flake/checks/udev-vm.nix`; retain the existing `udev-vm` check
  name and existing VM instead of adding a second VM/check.
- Add two hand-constructed umockdev USB fixtures through Nix store files:
  one matching `*CMSIS-DAP*`, one negative control whose product string does
  not contain `CMSIS-DAP`.
- Run pinned umockdev's preload sandbox and pinned systemd's real
  `udevadm test --action=add --json=short` against the activated
  `/etc/udev/rules.d/60-openocd.rules` tree.
- Parse JSON in the NixOS Python test driver and assert public rule outcomes.
- Update Phase 9 status/outcome and limitations in
  `docs/development/nixos-safety-init-testing-plan.md`.
- Keep this handoff under `docs/development/archive/` in the phase commit.

### Out of scope

- Real USB passthrough, host udev reload/trigger, host group changes, host
  rebuild, or hardware access.
- Running a real kernel hotplug event through the VM's systemd-udevd daemon.
- Proving ACL materialization or executing the queued `uaccess` builtin.
- `dummy_hcd`, configfs, Raw Gadget, USB/IP, USB gadget work, CMSIS-DAP/SWD
  emulation, or doctor-classification changes.
- A second NixOS VM or new flake check key.
- Changes to the upstream rule, udev package, public module, or workstation
  configuration.

## Grounding evidence

- Repository worktree: `/tmp/opencode/nix-nrf-dev-nixos-plan`.
- Branch: `feat/nixos-safety-and-init`.
- Existing stable check: `nix/flake/checks/udev-vm.nix`, exported as
  `checks.x86_64-linux.udev-vm`; it already boots real systemd-udevd, activates
  the packaged rule through direct `services.udev.packages`, and declares
  `plugdev`.
- Pinned packages observed in the disposable spike:
  - umockdev `0.19.3`;
  - systemd `261.1`.
- Exact packaged rule is the byte-identical pinned OpenOCD file. Its final
  generic line is:

  ```udev
  ATTRS{product}=="*CMSIS-DAP*", MODE="660", GROUP="plugdev", TAG+="uaccess"
  ```

- A disposable NixOS VM experiment using the exact activated rule and a
  hand-built XIAO fixture produced deterministic JSON from
  `udevadm test --action=add --json=short`:
  - path `/devices/virtual/usb/usb1/1-9`;
  - USB node `/dev/bus/usb/001/009`;
  - owner group name `plugdev` (gid is dynamically assigned and must not be
    pinned);
  - mode `0660`;
  - `uaccess` in both `tags` and `currentTags`;
  - queued builtin command `uaccess`.
- Same fixture with product changed from
  `Seeed Studio XIAO nrf54 CMSIS-DAP` to
  `Seeed Studio XIAO nrf54 Debug Probe` produced:
  - no node owner object;
  - no `uaccess` tag/current tag;
  - no queued `uaccess` command;
  - baseline mode `0664` in the current pinned system. Do not assert exact
    baseline mode; assert only that the control did not receive project rule
    outcomes.
- `udevadm test` documents that it does not run `RUN` keys. JSON proves rule
  assignment and command queuing, not resulting ACL application.
- umockdev redirects `/sys`, `/dev`, `/proc`, netlink, and selected ioctl
  access only for its preload child. It does not add a kernel USB device to the
  VM's global device graph. Synchronous `udevadm test` inside that child is the
  meaningful supported boundary.

## Exact implementation shape

### `nix/flake/checks/udev-vm.nix`

1. Change the top-level function body to a `let ... in` form and define a small
   fixture constructor using `pkgs.writeText`. Produce two immutable store
   fixtures from the same structure, differing only in product text:
   - positive: `Seeed Studio XIAO nrf54 CMSIS-DAP`;
   - control: `Seeed Studio XIAO nrf54 Debug Probe`.

2. Fixture structure must model the proven USB device and its interface. Keep
   these values:

   ```text
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
   A: product=<fixture product>
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
   ```

   Preserve literal `\n` attribute suffixes for `busnum` and `devnum`, as in
   umockdev-record format. Do not capture data from a physical device.

3. Do not add umockdev to `environment.systemPackages`. Reference the exact
   store binary in the test script as
   `${pkgs.umockdev.bin}/bin/umockdev-run`; interpolation keeps it in the test
   closure without weakening the existing clean-system PATH assertions.

4. Update file comments: this check now covers synthetic USB rule semantics,
   but still has no hardware passthrough, project tools, network dependency, or
   real daemon hotplug.

5. In a new subtest after activated-rule/group verification:
   - run each fixture in a separate `umockdev-run` child;
   - inside child, verify expected product attribute is readable at
     `/sys/devices/virtual/usb/usb1/1-9/product`;
   - run
     `udevadm test --action=add --json=short /sys/devices/virtual/usb/usb1/1-9`;
   - redirect diagnostics to a temporary log and emit only JSON on stdout;
   - on `udevadm` failure, print diagnostics and fail;
   - parse stdout with Python stdlib `json.loads` in NixOS test driver.

6. Positive assertions must prove:
   - fixture path, subsystem/type, node path, and fixture identity are the
     expected synthetic USB device;
   - `result["node"]["owner"]["groupName"] == "plugdev"`;
   - `result["node"]["mode"] == "0660"`;
   - `uaccess` membership in both `tags` and `currentTags`, without asserting
     order or excluding unrelated baseline tags such as `seat`;
   - queued commands contain a builtin `uaccess` command, without requiring it
     to execute;
   - do not assert numeric gid, initialization timestamps, store paths, or full
     JSON equality.

7. Negative-control assertions must prove:
   - control fixture identity is visible;
   - node owner is absent or not `plugdev`;
   - node mode is not `0660`;
   - `uaccess` is absent from optional `tags` and `currentTags` arrays;
   - no queued builtin `uaccess` command exists;
   - handle omitted optional JSON fields with `.get(..., [])`/`.get(...)`.
   Do not pin baseline mode `0664` or full negative JSON.

8. Keep every existing VM assertion. No check wiring changes should be needed.

### `docs/development/nixos-safety-init-testing-plan.md`

- Change top status from “Phase 9 ... next and not started” to implemented and
  committed on this branch, referring to this archive handoff.
- Under Phase 9, record promotion decision: deterministic and meaningful, so
  semantics test lives in existing `udev-vm` check.
- Record exact tested versions and boundary limitations listed above.
- State clearly that this is rule-engine simulation, not real hotplug, ACL
  application, hardware access, gadget emulation, or workstation adoption.
- Keep Phase 10 deferred and all existing approval boundaries unchanged.

## Acceptance behavior

User-observable regression boundary: if pinned upstream OpenOCD rule stops
matching a XIAO-like `*CMSIS-DAP*` product, or stops assigning `plugdev`, `0660`,
or `uaccess`, `checks.x86_64-linux.udev-vm` fails. Equivalent nonmatching USB
device must not receive those outcomes. Test exercises activated packaged rule
through real pinned `udevadm`, not copied constants or a mock parser.

## Verification

Run from repository root:

```sh
nix build -L .#checks.x86_64-linux.udev-vm
nix flake check --all-systems --no-build -L
nix flake check -L
git diff --check
```

Inspect final status/diff/log. Stage only:

- `nix/flake/checks/udev-vm.nix`;
- `docs/development/nixos-safety-init-testing-plan.md`;
- `docs/development/archive/udev-umockdev-semantics-handoff.md`.

Commit message:

```text
test(nixos): verify CMSIS-DAP udev semantics
```

Do not push, merge, amend, force-push, mutate host configuration, reload host
udev, touch hardware, or add attribution footers.

## Escalation rule

Stop without committing and report back if two materially different attempts
fail, JSON differs from grounded evidence, implementation needs a second VM or
new architecture, assertions would need weakening, or any host/hardware action
appears necessary. Preserve worktree and return exact commands, errors, diff,
status, and one focused question.

## Required recap

Return:

- files changed;
- behavior proved;
- commands run and results;
- commit hash and message;
- blockers or deviations;
- suggested follow-up.
