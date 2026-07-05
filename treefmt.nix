# treefmt.nix — project-wide formatter config (used by `nix fmt` and CI checks).
# See https://github.com/numtide/treefmt-nix for the full option list.
{
  programs = {
    alejandra.enable = true; # Nix formatter
    black.enable = true; # Python formatter (bin/nrf-probes)
    actionlint.enable = true; # GitHub Actions workflow linter (.github/workflows/*.yml)
  };
}
