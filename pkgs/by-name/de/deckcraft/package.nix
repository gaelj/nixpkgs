{
  lib,
  stdenv,
  rustPlatform,
  rustc,
  fetchFromGitHub,
  pkg-config,
  patchelf,
  copyDesktopItems,
  makeDesktopItem,
  versionCheckHook,
  alsa-lib,
  vulkan-loader,
  libxkbcommon,
  libx11,
  libxcb,
  libxcursor,
  libxi,
  libxrandr,
  wayland,
  dbus,
  nix-update-script,
}:

let
  # Loaded with dlopen by winit, wgpu and rfd (libdbus, for the file dialogs).
  runtimeDeps = [
    libxkbcommon
    libx11
    libxcb
    libxcursor
    libxi
    libxrandr
    wayland
    vulkan-loader
    dbus
  ];
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "deckcraft";
  version = "0.8.0";
  __structuredAttrs = true;
  strictDeps = true;

  # Upstream releases build against this craft-fonts revision (release.yml CRAFT_FONTS_REF).
  craft-fonts = fetchFromGitHub {
    owner = "storytold";
    repo = "craft-fonts";
    rev = "43913056ce82a3fdad0ef69f6b88d1dc922a8104";
    hash = "sha256-u1fC5spekizPXnrK6uiKEZSr2SJOaBF4ffLDbKkywEY=";
  };

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "deckcraft";
    tag = "v${finalAttrs.version}";
    hash = "sha256-kO8YBFzyip+NJmH2eFGGOB7OCOZWUhIGvEuxBzSemgk=";
  };

  cargoHash = "sha256-TlPzzZqjfKPE0D6FUSQKYkfdENzED+zNRYfQxepEBzk=";

  cargoBuildFlags = [
    "--package=deckcraft"
    "--package=deckcraft-cli"
  ];

  nativeBuildInputs = [
    pkg-config
    patchelf
    copyDesktopItems
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ alsa-lib ];

  desktopItems = [
    (makeDesktopItem {
      name = "ai.storyteller.deckcraft";
      desktopName = "DeckCraft";
      genericName = "Presentation";
      comment = "Create and present slide decks";
      exec = "deckcraft %F";
      tryExec = "deckcraft";
      icon = "ai.storyteller.deckcraft";
      terminal = false;
      startupNotify = true;
      startupWMClass = "ai.storyteller.deckcraft";
      categories = [
        "Office"
        "Presentation"
      ];
      keywords = [
        "presentation"
        "slides"
        "slide show"
        "deck"
        "pptx"
        "keynote"
        "powerpoint"
      ];
      mimeTypes = [
        "application/x-deckcraft"
        "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        "application/vnd.openxmlformats-officedocument.presentationml.template"
        "application/vnd.openxmlformats-officedocument.presentationml.slideshow"
      ];
    })
  ];

  postInstall = lib.optionalString stdenv.hostPlatform.isLinux ''
    install -Dm644 packaging/linux/ai.storyteller.deckcraft.mime.xml $out/share/mime/packages/ai.storyteller.deckcraft.xml
    mkdir -p $out/share/icons
    cp -R assets/app-icon/hicolor $out/share/icons/
  '';

  postFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    patchelf --add-rpath ${lib.makeLibraryPath runtimeDeps} $out/bin/deckcraft
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Presentation app with PPTX support";
    homepage = "https://github.com/storytold/deckcraft";
    changelog = "https://github.com/storytold/deckcraft/releases/tag/${finalAttrs.src.tag}";
    license = lib.licenses.OR [
      lib.licenses.mit
      lib.licenses.asl20
    ];
    maintainers = with lib.maintainers; [ sophronesis ];
    mainProgram = "deckcraft";
    platforms = rustc.meta.platforms;
  };
})
