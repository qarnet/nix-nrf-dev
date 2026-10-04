{
  pkgs,
  backlog,
}: {
  backlog =
    pkgs.runCommand "backlog-validation"
    {
      nativeBuildInputs = [
        backlog
        pkgs.git
        pkgs.python3
      ];
    }
    ''
      export HOME="$TMPDIR/home"
      mkdir -p "$HOME" repo/docs/product
      cp ${../../../backlog.config.yml} repo/backlog.config.yml
      cp -r ${../../../docs/product/backlog} repo/docs/product/backlog
      chmod -R u+w repo
      cd repo
      git init -q
      backlog task list --plain
      backlog doctor
      python3 ${../../../tests/product/test_backlog.py} "$PWD/backlog.config.yml"
      touch "$out"
    '';
}
