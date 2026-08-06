# nix/lib/mk-python-command.nix — narrow shared packaging helper for the
# internal Python command modules installed under $out/libexec/nix-nrf/.
#
# Owns exactly:
#   1. pkgs.runCommand pname;
#   2. nativeBuildInputs = [ pkgs.makeWrapper pkgs.python3 ];
#   3. install the executable script at $out/libexec/nix-nrf/${destination};
#   4. patchShebangs the exact destination;
#   5. flatten and shell-escape the ordered wrapperArgs;
#   6. call wrapProgram once.
#
# wrapperArgs is an ordered list of argument lists, e.g.
#
#   mkPythonCommand {
#     pname = "nix-nrf-doctor";
#     script = ../../bin/commands/nix-nrf-doctor;
#     destination = "doctor";
#     wrapperArgs = [
#       [ "--set" "NAME" value ]
#       [ "--unset" "PYTHONPATH" ]
#       [ "--prefix" "PATH" ":" path ]
#     ];
#   }
#
# — not an attrset — so the current wrapper argument order stays explicit and
# stable. Callers own every wrapper argument, including explicit PYTHONPATH
# and PYTHONHOME unsets; the helper adds no default environment variables,
# runtime inputs, standalone $out/bin commands, dynamic command discovery, or
# backend policy. Values are shell-escaped before interpolation so wrapProgram
# arguments never break the generated build script (spaces, quotes, and
# newlines survive).
{pkgs}: {
  pname,
  script,
  destination,
  wrapperArgs,
}:
assert builtins.isString pname;
assert builtins.isString destination;
assert builtins.isString script || builtins.isPath script;
assert builtins.isList wrapperArgs;
assert builtins.all (
  args:
    builtins.isList args
    && builtins.all (
      a: builtins.isString a || builtins.isPath a || (builtins.isAttrs a && a ? outPath)
    )
    args
)
wrapperArgs; let
  # Flatten in declared order and shell-escape every argument; the escaped
  # line is interpolated as literal script text, so wrapProgram re-parses the
  # quoting exactly as the previous per-module builders did.
  escapedArgs =
    builtins.concatMap (
      args: map (a: pkgs.lib.escapeShellArg (toString a)) args
    )
    wrapperArgs;
in
  pkgs.runCommand pname
  {
    nativeBuildInputs = [
      pkgs.makeWrapper
      pkgs.python3
    ];
    inherit script destination;
  }
  ''
    install -Dm755 "$script" "$out/libexec/nix-nrf/$destination"
    patchShebangs "$out/libexec/nix-nrf/$destination"
    wrapProgram "$out/libexec/nix-nrf/$destination" ${builtins.concatStringsSep " " escapedArgs}
  ''
