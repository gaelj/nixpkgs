{
  lib,
  stdenv,
  stdenvNoCC,
  makeWrapper,
  fuse,
  e2fsprogs,
  mesa,
  libgbm,
  fetchurl,
  fontconfig,
  freetype,
  harfbuzz,
  libgpg-error,
  libdrm,
  libglvnd,
  util-linux,
  libx11,
  libxcb,
  zlib,
  gmp,
  jack2,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "flirc-skip1s-app";
  version = "0.9.995";
  buildId = "10457-Beta";

  __structuredAttrs = true;

  src = fetchurl {
    url = "https://update.flirc.tv/skipapp/beta/${finalAttrs.version}/SkipApp-${finalAttrs.version}.${finalAttrs.buildId}-x64.AppImage.tar.gz?token=skipAppUpdate";
    name = "SkipApp-${finalAttrs.version}.${finalAttrs.buildId}-x64.AppImage.tar.gz";
    hash = "sha256-4hkpfVSDT+B3YAvAso0ZCI8E6o5S1NytqSkUSbB1mrQ=";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    tar -xzf "$src" -C "$TMPDIR"
    appimage="$(find "$TMPDIR" -maxdepth 1 -iname '*.AppImage' | head -n1)"
    if [ -z "$appimage" ]; then
      echo "No .AppImage found after extracting $src" >&2
      exit 1
    fi
    install -m755 "$appimage" "$out/bin/$pname.AppImage"

    makeWrapper "$out/bin/$pname.AppImage" "$out/bin/$pname" \
      --set LD_LIBRARY_PATH "${
        lib.makeLibraryPath [
          fuse
          e2fsprogs
          mesa
          libgbm
          libdrm
          libglvnd
          fontconfig
          freetype
          harfbuzz
          libgpg-error
          (util-linux.lib)
          libx11
          libxcb
          zlib
          gmp
          jack2
        ]
      }:${stdenv.cc}/lib"

    runHook postInstall
  '';

  meta = {
    description = "FLIRC Skip 1s companion app";
    longDescription = ''
      Tauri-based (GTK/WebKit) companion application for the FLIRC Skip 1s IR remote.
    '';
    homepage = "https://flirc.tv/products/skip1s-remote";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "flirc-skip1s-app";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    maintainers = with lib.maintainers; [ gaelj ];
  };
})
