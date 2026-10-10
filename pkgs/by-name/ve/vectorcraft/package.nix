{
  lib,
  fetchFromGitHub,
  rustPlatform,
  pkg-config,
  copyDesktopItems,
  makeDesktopItem,
  patchelf,
  libx11,
  libxcb,
  libGL,
  libxkbcommon,
  wayland,
  vulkan-loader,
  libxcursor,
  libxi,
  dbus,
  mesa,
  craftFonts,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "vectorcraft";
  version = "0.7.0";
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "vectorcraft";
    tag = "v${finalAttrs.version}";
    hash = "sha256-W76TxJHWIfLwFmocahH8MCaWARGJYS6q3YLJNoWb0AI=";
  };

  cargoLock = {
    lockFile = "${finalAttrs.src}/Cargo.lock";
  };

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
    CRAFT_FONTS_DIR = "${craftFonts}";
    CRAFT_FONTS_REQUIRED = "1";
  };

  cargoBuildFlags = [
    "-p"
    "vectorcraft"
    "-p"
    "vectorcraft-cli"
  ];

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
      $out/bin/vectorcraft
  '';

  desktopItem = makeDesktopItem {
    name = "vectorcraft";
    desktopName = "VectorCraft";
    genericName = "Vector Graphics Editor";
    icon = "ai.storyteller.vectorcraft";
    tryExec = "vectorcraft";
    exec = "vectorcraft";
    comment = "Draw and edit vector illustrations, SVG and PDF";
    mimeTypes = [
      "image/svg+xml"
      "application/pdf"
    ];
    categories = [
      "Graphics"
      "2DGraphics"
      "VectorGraphics"
    ];
    startupNotify = true;
    startupWMClass = "ai.storyteller.vectorcraft";
    keywords = [
      "vector"
      "illustration"
      "svg"
      "pdf"
      "drawing"
      "bezier"
    ];
  };

  desktopItems = [ finalAttrs.desktopItem ];

  meta = {
    description = "VectorCraft desktop app";
    homepage = "https://github.com/storytold/vectorcraft";
    license = lib.licenses.OR [
      lib.licenses.asl20
      lib.licenses.mit
    ];
    mainProgram = "vectorcraft";
    maintainers = with lib.maintainers; [
      gaelj
    ];
  };
})
