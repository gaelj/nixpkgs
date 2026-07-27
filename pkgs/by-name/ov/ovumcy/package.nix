{
  lib,
  buildGoModule,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs,
}:

buildGoModule (finalAttrs: {
  pname = "ovumcy";
  version = "1.9.2";
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "ovumcy";
    repo = "ovumcy-web";
    tag = "v${finalAttrs.version}";
    hash = "sha256-cHnNPK8nVgFIsS+OnhMO9Bko9zJQwoBYxssCjLecRD4=";
  };

  frontend = buildNpmPackage {
    pname = "ovumcy-frontend";
    inherit (finalAttrs) version src;
    inherit nodejs;

    npmDepsHash = "sha256-P2ByiIVYf3tT0JShyWazDCg0M38HAEKuiStrymhHmmc=";

    installPhase = ''
      runHook preInstall
      cp -r web/static $out
      runHook postInstall
    '';
  };

  vendorHash = "sha256-rl3ElPKXgP9SDQI3mpYByC8Z+ClnkXx/HvFUaE/Khg8=";

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
