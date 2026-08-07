{pkgs}:
pkgs.openocd.overrideAttrs (old: {
  pname = "openocd-master";

  src = pkgs.fetchgit {
    url = "https://git.code.sf.net/p/openocd/code";
    rev = "da3920b0a52dc2d394afb222c688dac7e57acc1b";
    hash = "sha256-ILHycdQeoMbtZvpCl7nqPgMEXYD4A1LlR1XEiopvD9A=";
    fetchSubmodules = true;
  };

  # Git checkout needs bootstrap/autoreconf.
  nativeBuildInputs =
    (old.nativeBuildInputs or [])
    ++ [
      pkgs.autoreconfHook
      pkgs.pkg-config
    ];
})
