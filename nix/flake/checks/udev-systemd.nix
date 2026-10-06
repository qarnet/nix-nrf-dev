# Test-image-only compatibility fix for pinned systemd 261.1. The loader stores
# original rule paths while reload detection enumerates resolved parent paths;
# NixOS's symlinked rules tree otherwise forces reloads on unchanged files.
# Keep the package version, existing patches, rule parsing, and consumer tools.
{pkgs}:
pkgs.systemd.overrideAttrs (old: {
  postPatch =
    (old.postPatch or "")
    + ''
      substituteInPlace src/udev/udev-rules.c \
        --replace-fail \
        'hashmap_put_stats_by_path(&rules->stats_by_path, c->original_path, &c->st)' \
        'hashmap_put_stats_by_path(&rules->stats_by_path, c->result, &c->st)'
    '';
})
