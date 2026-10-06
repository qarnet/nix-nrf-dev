# Contributor shells compose the public mkNrfShell factory without adding
# Backlog.md or hardware-harness dependencies to consumer shells. SDK-free
# product and hardware-tests shells keep planning and capture separate from
# SDK bootstrap.
{
  pkgs,
  mkNrfShell,
  pre-commit,
  backlog,
  nix-nrf,
}: let
  platform = (import ../platforms.nix).${pkgs.stdenv.hostPlatform.system};
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
    backend = platform.defaultBackend;
    ncsVersion = "v3.4.1";
    name = "nix-nrf-dev";
    packages = pre-commit.enabledPackages ++ [backlog];
    extraShellHook = pre-commit.shellHook;
  };

  # Product work needs neither the Nordic SDK nor probe tooling.
  product = pkgs.mkShell {
    name = "nix-nrf-dev-product";
    packages = [
      backlog
      pkgs.git
    ];
  };

  # Harness dependencies only; entering this shell never bootstraps an SDK.
  hardware-tests = pkgs.mkShell {
    name = "nix-nrf-hardware-tests";
    packages = [
      nix-nrf
      (pkgs.python3.withPackages (ps: [ps.pyelftools]))
    ];
  };

  # Clean-environment test shell: exercises shell-hook behavior to
  # prove Nordic sdk-manager variables do not poison external tools
  # (Node, Git, Python). The tools arrive via inputsFrom from the
  # internal cleanEnvFixture.
  clean-env-test = mkNrfShell {
    backend = platform.defaultBackend;
    ncsVersion = "v3.4.1";
    name = "nix-nrf-dev-clean-env-test";
    withMultilib = false;
    inputsFrom = [cleanEnvFixture];
  };
}
