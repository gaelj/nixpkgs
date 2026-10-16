{ lib
, fetchFromGitHub
, rustPlatform
, rustc
, pkg-config
, copyDesktopItems
, makeDesktopItem
, patchelf
, libx11
, libxcb
, libGL
, libxkbcommon
, nix-update-script
, wayland
, libxcursor
, libxi
, vulkan-loader
, dbus
, versionCheckHook
,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "wordcraft";
  version = "0.7.0";
  __structuredAttrs = true;

  # Upstream releases build against this craft-fonts revision (release.yml CRAFT_FONTS_REF).
  craft-fonts = fetchFromGitHub {
    owner = "storytold";
    repo = "craft-fonts";
    rev = "8dcdacd5153e64560d109541a47d806f26f048c0";
    hash = "sha256-4E9OrthE5z39xFXpvpwn4Fn6RH3wX2sF56rZZejZT+I=";
  };

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "wordcraft";
    tag = "v${finalAttrs.version}";
    hash = "sha256-SfrnSydUVuh+3tJ69OINsc1thkubgVh8aEVBfZyXmsM=";
  };

  cargoHash = "sha256-D/CRhDoUbKvz/ev8NKRm2aDEyOA4NL5mdnx+O+iXHRI=";

  nativeBuildInputs = [
    pkg-config
    copyDesktopItems
  ];

  buildInputs = [
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
    CRAFT_FONTS_DIR = "${finalAttrs.craft-fonts}";
    CRAFT_FONTS_REQUIRED = "1";
  };

  cargoBuildFlags = [
    "-p"
    "wordcraft"
    "-p"
    "wordcraft-cli"
  ];

  postInstall = ''
    install -d $out/share/icons
    cp -r assets/app-icon/hicolor $out/share/icons

    docdir=$out/share/doc/${finalAttrs.pname}-${finalAttrs.version}
    install -d $docdir
    for lic in ${finalAttrs.craft-fonts}/fonts/*/OFL.txt; do
      install -Dm644 "$lic" "$docdir/OFL-$(basename "$(dirname "$lic")").txt"
    done
  '';

  postFixup = ''
    patchelf --set-rpath "${
      lib.makeLibraryPath [
        libx11
        libxcb
        libGL
        libxkbcommon
        wayland
        libxcursor
        libxi
        vulkan-loader
        dbus
      ]
    }" \
      $out/bin/wordcraft
  '';

  desktopItem = makeDesktopItem {
    name = "wordcraft";
    desktopName = "WordCraft";
    genericName = "Word Processor";
    icon = "ai.storyteller.wordcraft";
    tryExec = "wordcraft";
    exec = "wordcraft";
    comment = "Write and design documents; open and save Word files";
    mimeTypes = [
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      "application/vnd.oasis.opendocument.text"
      "application/rtf"
      "text/markdown"
      "text/html"
      "text/plain"
    ];
    categories = [
      "Office"
      "WordProcessor"
    ];
    startupNotify = true;
    startupWMClass = "ai.storyteller.wordcraft";
    keywords = [
      "word"
      "processor"
      "document"
      "docx"
      "writer"
      "text"
      "letter"
      "report"
    ];
  };

  desktopItems = [ finalAttrs.desktopItem ];

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "WordCraft desktop app";
    homepage = "https://github.com/storytold/wordcraft";
    changelog = "https://github.com/storytold/wordcraft/releases/tag/${finalAttrs.src.tag}";
    license = lib.licenses.OR [
      lib.licenses.asl20
      lib.licenses.mit
    ];
    mainProgram = "wordcraft";
    maintainers = with lib.maintainers; [
      gaelj
    ];
    platforms = rustc.meta.platforms;
  };
})
