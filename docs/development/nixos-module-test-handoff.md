# Public NixOS module evaluation-test handoff

## Goal

Add cheap public-boundary regression coverage proving
`nixosModules.default` contributes exact packaged OpenOCD udev rules to a real
pinned-Nixpkgs NixOS configuration.

## Scope

### In scope

- Add `checks.nixos-module` to `nix/flake/checks/core.nix`.
- Evaluate public `self.nixosModules.default` through
  `nixpkgs.lib.nixosSystem` for supported `x86_64-linux`.
- Assert exact `nrfUdevRules` output appears exactly once in evaluated
  `config.services.udev.packages`.
- Assert same path equals public `self.packages.${system}.udev-rules`.
- Wire required `self`, `nixpkgs`, and `system` args into core check module.
- Export check explicitly and update README/architecture count/list.

### Out of scope

- NixOS VM boot test. Module only contributes package to existing udev option;
  VM adds cost without stronger signal for this contract.
- Testing udev rule bytes. Existing `checks.udev-rules` already proves installed
  rule is byte-identical to pinned OpenOCD contrib rule.
- Real udev reload, USB permissions, groups, devices, hardware, or sudo.
- NixOS module options or behavior changes.
- Unsupported platforms.

## Grounding

- Public module lives in `flake.nix` and sets
  `services.udev.packages = [ self.packages.${system}.udev-rules ];`.
- Existing `checks.udev-rules` proves package contents but never imports public
  NixOS module.
- Existing `checks.doctor-udev-wiring` proves shell doctor reports package path
  but does not prove host module activation.
- Verified local expression using pinned input succeeds:

```nix
let
  f = builtins.getFlake (toString ./.);
  evaluated = f.inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ f.nixosModules.default { system.stateVersion = "26.11"; } ];
  };
in map (p: p.outPath) evaluated.config.services.udev.packages
```

Result includes repository `nix-nrf-udev-rules` plus normal NixOS defaults.
Therefore test membership/count, not whole package-list equality.

## Exact implementation

Extend `core.nix` arguments with `self`, `nixpkgs`, and `system`. Define
evaluation:

```nix
evaluated = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    self.nixosModules.default
    { system.stateVersion = "26.11"; }
  ];
};
```

Read `evaluated.config.services.udev.packages`; filter derivations whose
`outPath == nrfUdevRules.outPath`. Also compare
`self.packages.${system}.udev-rules.outPath` with `nrfUdevRules.outPath`.

Create `pkgs.runCommand "nix-nrf-nixos-module-check"` whose generated script
fails with clear diagnostics unless:

- matching module package count is exactly `1`;
- public package output path equals internal package path.

Pass only already evaluated booleans/count/store paths into derivation. Do not
build full NixOS system. Export key `nixos-module` and pass args from
`nix/flake/per-system.nix`.

Use existing derivation check style rather than `lib.debug.runTests`: this is
one integration assertion over module evaluation, not library of pure helper
functions. Do not add `nix-unit`.

## Verification

```sh
nix build .#checks.x86_64-linux.nixos-module -L
nix flake check --all-systems --no-build -L
nix flake check -L
```

## Acceptance

- Public NixOS module evaluated through pinned Nixpkgs.
- Exact public udev-rules package appears once in `services.udev.packages`.
- No full NixOS build/VM/hardware required.
- Existing package-content and doctor wiring checks remain unchanged and pass.
- Check count/docs match.

## Executor instructions

Implement exactly this small phase. Escalate before changing module behavior or
adding VM/dependencies. Run verification, inspect status/diff/log, stage scoped
files, and commit concise conventional message. No push, amend, PR, or
attribution. Return files, behavior, tests, hash/message, blockers, deviations,
and follow-up.
