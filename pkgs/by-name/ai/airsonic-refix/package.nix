{
  lib,
  stdenv,
  fetchzip,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "airsonic-refix";
  version = "sha-f5a14e3f95814c13c95deb17c061635c9247401c";
  __structuredAttrs = true;

  src = fetchzip {
    url = "https://github.com/tamland/airsonic-refix/releases/download/${finalAttrs.version}/dist.tar.gz";
    hash = "sha256-xPKwLtNeYGmIbAEZgNCsObno2aPFNYThy+q6PsnEbjI=";
    stripRoot = false;
  };

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/airsonic-refix
    cp -r . $out/share/airsonic-refix
    runHook postInstall
  '';

  meta = {
    description = "Modern web UI for Subsonic compatible servers";
    homepage = "https://github.com/tamland/airsonic-refix";
    license = lib.licenses.agpl3Only;
    maintainers = with lib.maintainers; [ gaelj ];
    mainProgram = "airsonic-refix";
    platforms = lib.platforms.all;
  };
})
