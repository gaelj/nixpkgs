{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:

stdenvNoCC.mkDerivation {
  pname = "craft-fonts";
  version = "0-unstable-2026-10-11";
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "craft-fonts";
    rev = "3d9ab3a132ed0eff457e424226a435a901da30d3";
    hash = "sha256-mNnDzBcOp1X10dzmiW0iBAkb74QjuzMO4slWudxXCTE=";
  };

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r fonts $out/fonts

    install -d $out/share/doc/craft-fonts
    install -m644 ATTRIBUTION.md README.md LICENSE-MIT LICENSE-APACHE \
      $out/share/doc/craft-fonts/

    runHook postInstall
  '';

  meta = {
    description = "Craft shared font collection (SIL OFL) consumed via CRAFT_FONTS_DIR";
    homepage = "https://github.com/storytold/craft-fonts";
    license = lib.licenses.OR [
      lib.licenses.asl20
      lib.licenses.mit
    ];
    maintainers = with lib.maintainers; [
      gaelj
    ];
  };
}
