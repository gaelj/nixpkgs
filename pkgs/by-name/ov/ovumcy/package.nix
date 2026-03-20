{
  lib,
  buildGoModule,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs,
}:

buildGoModule (finalAttrs: {
  pname = "ovumcy";
  version = "0.7.2";

  src = fetchFromGitHub {
    owner = "ovumcy";
    repo = "ovumcy-web";
    tag = "v${finalAttrs.version}";
    hash = "sha256-mS3e2UavbfYQTDa4kU1QuYY852480PhVEH+uhoIoF0E=";
  };

  frontend = buildNpmPackage {
    pname = "ovumcy-frontend";
    inherit (finalAttrs) version src;
    inherit nodejs;

    npmDepsHash = "sha256-UV4Bn9DLwdE0FS0+pA/9y/DtBp8aibamCaZATJVSLhQ=";

    installPhase = ''
      runHook preInstall
      cp -r web/static $out
      runHook postInstall
    '';
  };

  vendorHash = "sha256-zc/U9LoDYg2s1giW/5/2z5g3N/Hlq6XVZ6CMcvk0HYo=";

  subPackages = [ "cmd/ovumcy" ];

  preBuild = ''
    cp -r ${finalAttrs.frontend}/. web/static/
  '';

  postInstall = ''
    share=$out/share/ovumcy

    # Locale JSON files
    mkdir -p $share/internal/i18n
    cp -r internal/i18n/locales $share/internal/i18n/locales

    # HTML templates
    mkdir -p $share/internal/templates
    cp -r internal/templates/. $share/internal/templates/

    # Compiled static assets (css / js output from npm build)
    mkdir -p $share/web
    cp -r web/static $share/web/static
  '';

  meta = with lib; {
    description = "Privacy-first, self-hosted menstrual cycle tracker";
    homepage = "https://github.com/ovumcy/ovumcy-web";
    license = licenses.agpl3Only;
    maintainers = with lib.maintainers; [ gaelj ];
    mainProgram = "ovumcy";
    platforms = platforms.linux ++ platforms.darwin;
  };
})
