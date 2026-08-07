# Per-system dev shells: the dogfood `default` shell and the
# `clean-env-test` regression shell. Receives pkgs (for the internal
# hybrid-input fixture), the public mkNrfShell factory, and the pre-commit
# module (enabledPackages + shellHook).
{
  pkgs,
  mkNrfShell,
  pre-commit,
}: let
  # Internal hybrid-input fixture: plain mkShell whose packages provide
  # the regression tools (Node, Git, Python). clean-env-test pulls them in
  # via inputsFrom so CI's tool execution proves inputsFrom propagation
  # through mkNrfShell and that the scoped toolchain variables do not
  # poison Node/Git/Python.
  cleanEnvFixture = pkgs.mkShell {
    packages = [
      pkgs.nodejs_24
      pkgs.git
      pkgs.python3
    ];
  };
in {
  # Dogfood shell for hacking on this repo / ad-hoc probe work.
  # Composes mkNrfShell with pre-commit hooks (packages + shellHook).
  # autoBootstrap defaults to true: lazy SDK/toolchain bootstrap on
  # the first `west` invocation.
  default = mkNrfShell {
    backend = "nrfutil";
    ncsVersion = "v3.3.0";
    name = "nix-nrf-dev";
    packages = pre-commit.enabledPackages;
    extraShellHook = pre-commit.shellHook;
  };

  # Clean-environment test shell: exercises shell-hook behavior to
  # prove Nordic sdk-manager variables do not poison external tools
  # (Node, Git, Python). The tools arrive via inputsFrom from the
  # internal cleanEnvFixture.
  clean-env-test = mkNrfShell {
    backend = "nrfutil";
    ncsVersion = "v3.3.0";
    name = "nix-nrf-dev-clean-env-test";
    withMultilib = false;
    inputsFrom = [cleanEnvFixture];
  };
}
