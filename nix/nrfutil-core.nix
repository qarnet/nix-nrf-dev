# Minimal upstream nrfutil packaging for sdk-manager usage in dev shells.
# Avoid nixpkgs nrfutil because it depends on SEGGER J-Link.
{ pkgs, system }:

let
  srcInfo =
    {
      x86_64-linux = {
        triplet = "x86_64-unknown-linux-gnu";
        version = "8.1.1";
        hash = "sha256-SAD4tx/uwMqvPBQ9KbC3/W8zxqJY2hDmYHQ/DbGJCgs=";
      };
      aarch64-linux = {
        triplet = "aarch64-unknown-linux-gnu";
        version = "8.1.1";
        hash = "sha256-y7ywCr9Ze3Uz1JQh0hNg2BOPKW2yEftYDaD8WzHWSxY=";
      };
    }
    .${system} or null;
in
if srcInfo == null then
  null
else
  pkgs.stdenvNoCC.mkDerivation {
    pname = "nrfutil-core";
    inherit (srcInfo) version;
    src = pkgs.fetchurl {
      url = "https://files.nordicsemi.com/artifactory/swtools/external/nrfutil/executables/${srcInfo.triplet}/nrfutil";
      hash = srcInfo.hash;
    };
    dontUnpack = true;
    nativeBuildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.autoPatchelfHook ];
    buildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [
      pkgs.glibc
      pkgs.stdenv.cc.cc.lib
      pkgs.zlib
      pkgs.xz
      pkgs.libusb1
      pkgs.udev
    ];
    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin
      install -Dm755 $src $out/bin/nrfutil
      runHook postInstall
    '';
    meta = with pkgs.lib; {
      description = "Nordic nrfutil core CLI";
      homepage = "https://www.nordicsemi.com/Products/Development-tools/nRF-Util";
      license = licenses.unfree;
      platforms = [ system ];
      sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    };
  }
