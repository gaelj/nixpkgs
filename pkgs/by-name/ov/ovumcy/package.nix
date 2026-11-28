{
  lib,
  buildGoModule,
  buildNpmPackage,
  fetchFromGitHub,
  fetchNpmDeps,
  nodejs,
}:

buildGoModule (finalAttrs: {
  pname = "ovumcy";
  version = "2.3.0";
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "ovumcy";
    repo = "ovumcy-web";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Yq+hh8O9ymxXI8MXM5M2uSaGGTCOJwjj6QKI5fw4hkU=";
  };

  # Kept at the top level because nix-update only refreshes `pkg.npmDeps`; it
  # never looks at hashes nested inside sub-derivations such as `frontend`.
  npmDeps = fetchNpmDeps {
    name = "ovumcy-frontend-${finalAttrs.version}-npm-deps";
    inherit (finalAttrs) src;
    hash = "sha256-/jv0hxrwgM+A2rOVM8ElZiErUO85gwW3uUfEc/+2blc=";
  };

  frontend = buildNpmPackage {
    pname = "ovumcy-frontend";
    inherit (finalAttrs) version src npmDeps;
    inherit nodejs;

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

  vendorHash = "sha256-Cvuq1ZjFpvr0dk6RFYYU4tyVoYuWN6zl3HcrIV3UlFg=";

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
