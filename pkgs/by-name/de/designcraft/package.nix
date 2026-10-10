{
  lib,
  fetchFromGitHub,
  rustPlatform,
  rustc,
  pkg-config,
  copyDesktopItems,
  makeDesktopItem,
  patchelf,
  libx11,
  libxcb,
  libGL,
  libxkbcommon,
  nix-update-script,
  wayland,
  vulkan-loader,
  libxcursor,
  libxi,
  dbus,
  mesa,
  versionCheckHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "designcraft";
  version = "0.11.0";
  __structuredAttrs = true;

  # Upstream releases build against this craft-fonts revision (release.yml CRAFT_FONTS_REF).
  craft-fonts = fetchFromGitHub {
    owner = "storytold";
    repo = "craft-fonts";
    rev = "abb83316d96aa59c1cf64784289e378fe9fa5695";
    hash = "sha256-e+6HpOYoAFTh6mNfGBBw2njnBzcE8W8+Jybv1+dKOCA=";
  };

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "designcraft";
    tag = "v${finalAttrs.version}";
    hash = "sha256-DiQmSuFIm7ye7h508d8b/YSS3XNZwl5WihitoORKVx0=";
  };

  cargoHash = "sha256-wOq/THtTQNglpwuIgF8v69+TUrwwxPsLoL5OfTIfqaw=";

  # Provides the software Vulkan driver (lavapipe) for the wgpu-based egui_kittest tests inside the
  # sandbox; upstream CI gets one from the runner image's mesa. A slim vulkanDrivers-only override
  # breaks this tree's multi-output mesa builder (no spirv2dxil output).
  lavapipe = mesa;

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
    vulkan-loader
    finalAttrs.lavapipe
    # dlopened at runtime by winit/x11-dl, x11rb (dl-libxcb), xkbcommon-dl, wgpu and
    # g-desktop-portal; the fork's libx11 also ships libX11-xcb.so.1 in the same dir.
    libxcursor
    libxi
    dbus
  ];

  preCheck = ''
    # The wgpu-based egui_kittest test dlopens libvulkan.so.1 at runtime and picks the lavapipe ICD;
    # this tree's stdenv sets no LD_LIBRARY_PATH, so point it at them explicitly (upstream CI gets
    # both from the runner image).
    export VK_ICD_FILENAMES=$(ls ${finalAttrs.lavapipe}/share/vulkan/icd.d/*lvp*.json | tr '\n' ':')
    export LD_LIBRARY_PATH="${vulkan-loader}/lib:${finalAttrs.lavapipe}/lib"
  '';

  env = {
    CRAFT_FONTS_DIR = "${finalAttrs.craft-fonts}";
    CRAFT_FONTS_REQUIRED = "1";
  };

  cargoBuildFlags = [
    "-p"
    "designcraft"
    "-p"
    "designcraft-cli"
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
        vulkan-loader
        libxcursor
        libxi
        dbus
      ]
    }" \
      $out/bin/designcraft
  '';

  desktopItem = makeDesktopItem {
    name = "designcraft";
    desktopName = "DesignCraft";
    genericName = "Page Layout";
    icon = "ai.storyteller.designcraft";
    tryExec = "designcraft";
    exec = "designcraft";
    comment = "Lay out magazines, books and print documents";
    categories = [
      "Graphics"
      "Publishing"
    ];
    startupNotify = true;
    startupWMClass = "ai.storyteller.designcraft";
    keywords = [
      "layout"
      "page"
      "desktop publishing"
      "dtp"
      "magazine"
      "book"
      "indesign"
      "idml"
      "typesetting"
    ];
  };

  desktopItems = [ finalAttrs.desktopItem ];

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "DesignCraft desktop app";
    homepage = "https://github.com/storytold/designcraft";
    changelog = "https://github.com/storytold/designcraft/releases/tag/${finalAttrs.src.tag}";
    license = lib.licenses.OR [
      lib.licenses.asl20
      lib.licenses.mit
    ];
    mainProgram = "designcraft";
    maintainers = with lib.maintainers; [
      gaelj
    ];
    platforms = rustc.meta.platforms;
  };
})
