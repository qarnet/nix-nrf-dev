# Native host capabilities, not firmware target architectures. Repository and
# initializer presets may select defaultBackend; the public factory retains its
# explicit nrfutil default and rejects unavailable combinations without fallback.
{
  x86_64-linux = {
    defaultBackend = "nrfutil";
    backends = [
      "nrfutil"
      "west"
    ];
    multilib = true;
  };
  aarch64-linux = {
    defaultBackend = "west";
    backends = ["west"];
    multilib = false;
  };
}
