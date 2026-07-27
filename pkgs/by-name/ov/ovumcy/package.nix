{
  lib,
  buildGoModule,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs,
}:

buildGoModule (finalAttrs: {
  pname = "ovumcy";
  version = "2.2.1";
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "ovumcy";
    repo = "ovumcy-web";
    tag = "v${finalAttrs.version}";
    hash = "sha256-tDER9/b9MsL/bteuD1ZKTH61OPtiPM3tYtG98cdIDlk=";
  };

  frontend = buildNpmPackage {
    pname = "ovumcy-frontend";
    inherit (finalAttrs) version src;
    inherit nodejs;

    npmDepsHash = "sha256-L6ru6pbBBDnm5w2o40qOBvg2jMXFEAWe6FVpXNjZ6rQ=";

    installPhase = ''
      runHook preInstall
      cp -r web/static $out
      runHook postInstall
    '';
  };

  # go.mod requires go 1.27.4, but nixpkgs only has go 1.27.3. The patch release
  # adds no language or standard library features, so trim it.
  postPatch = ''
    substituteInPlace go.mod --replace-fail 'go 1.27.4' 'go 1.27.3'
  '';

  vendorHash = "sha256-JYmKyTW/eemmtQ6bGNEWMuXVVtL0KmYA83li3KWnPnc=";

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
