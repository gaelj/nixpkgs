{
  lib,
  stdenv,
  fetchzip,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "airsonic-refix";
  version = "sha-92950465a4f863d9b2c3ae83859a719a678674c4";

  src = fetchzip {
    url = "https://github.com/tamland/airsonic-refix/releases/download/${finalAttrs.version}/dist.tar.gz";
    hash = "sha256-8dHFmlp0BQgXs+wIzuZH8GXQPVh/j850me/57gBE4kQ=";
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
