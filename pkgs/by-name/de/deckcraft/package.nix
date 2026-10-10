{ lib
, fetchFromGitHub
, rustPlatform
, pkg-config
, copyDesktopItems
, makeDesktopItem
, patchelf
, alsa-lib
, libx11
, libxcb
, libGL
, libxkbcommon
, wayland
, libxcursor
, libxi
, vulkan-loader
, dbus
, craftFonts
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "deckcraft";
  version = "0.3.0";
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "deckcraft";
    tag = "v${finalAttrs.version}";
    hash = "sha256-mJTA41rZMHwrK8o/Yw2TcGfWSfz7MreX9SliFVAoDMc=";
  };

  cargoLock = { lockFile = "${finalAttrs.src}/Cargo.lock"; };

  nativeBuildInputs = [
    pkg-config
    copyDesktopItems
  ];

  buildInputs = [
    alsa-lib
    libx11
    libxcb
    libGL
    libxkbcommon
    wayland
    # dlopened at runtime by winit/x11-dl, x11rb (dl-libxcb), xkbcommon-dl, wgpu and
    # g-desktop-portal; the fork's libx11 also ships libX11-xcb.so.1 in the same dir.
    libxcursor
    libxi
    vulkan-loader
    dbus
  ];

  env = {
    CRAFT_FONTS_DIR = "${craftFonts}";
    CRAFT_FONTS_REQUIRED = "1";
  };

  cargoBuildFlags = [ "-p" "deckcraft" "-p" "deckcraft-cli" ];

  postInstall = ''
    install -d $out/share/icons
    cp -r assets/app-icon/hicolor/* $out/share/icons/

    docdir=$out/share/doc/${finalAttrs.pname}-${finalAttrs.version}
    install -d $docdir
    for lic in ${craftFonts}/fonts/*/OFL.txt; do
      install -Dm644 "$lic" "$docdir/OFL-$(basename "$(dirname "$lic")").txt"
    done
  '';

  postFixup = ''
    patchelf --set-rpath "${lib.makeLibraryPath [ alsa-lib libx11 libxcb libGL libxkbcommon wayland libxcursor libxi vulkan-loader dbus ]}" \
      $out/bin/deckcraft
  '';

  desktopItem = makeDesktopItem {
    name = "deckcraft";
    desktopName = "DeckCraft";
    genericName = "Presentation";
    icon = "ai.storyteller.deckcraft";
    tryExec = "deckcraft";
    exec = "deckcraft";
    comment = "Create and present slide decks";
    mimeTypes = [
      "application/x-deckcraft"
      "application/vnd.openxmlformats-officedocument.presentationml.presentation"
      "application/vnd.openxmlformats-officedocument.presentationml.template"
      "application/vnd.openxmlformats-officedocument.presentationml.slideshow"
    ];
    categories = [ "Office" "Presentation" ];
    startupNotify = true;
    startupWMClass = "ai.storyteller.deckcraft";
    keywords = [
      "presentation"
      "slides"
      "slide show"
      "deck"
      "pptx"
      "keynote"
      "powerpoint"
    ];
  };

  desktopItems = [ finalAttrs.desktopItem ];

  meta = {
    description = "DeckCraft desktop app";
    homepage = "https://github.com/storytold/deckcraft";
    license = lib.licenses.OR [
      lib.licenses.asl20
      lib.licenses.mit
    ];
    mainProgram = "deckcraft";
    maintainers = with lib.maintainers; [
      gaelj
    ];
  };
})
