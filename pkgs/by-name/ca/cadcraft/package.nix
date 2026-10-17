{ lib
, fetchFromGitHub
, rustPlatform
, pkg-config
, copyDesktopItems
, makeDesktopItem
, patchelf
, libx11
, libxcb
, libGL
, libxkbcommon
, wayland
, vulkan-loader
, libxcursor
, libxi
, dbus
, mesa
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "cadcraft";
  version = "0.7.0";
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "cadcraft";
    tag = "v${finalAttrs.version}";
    hash = "sha256-/7mlDxYCeE6vKKJWghfMj4WtHbjPWfPnhb+HoHgA0q4=";
  };

  cargoHash = "sha256-7/TxuM5jh6fncL0+pAT147GJuri/sD0xnN6lRxueD0E=";

  # Upstream releases build against this craft-fonts revision (release.yml craft-fonts-ref);
  # without it crates/fonts embeds no CRAFT_FONTS and the app loses its bundled UI fonts.
  craft-fonts = fetchFromGitHub {
    owner = "storytold";
    repo = "craft-fonts";
    rev = "3d9ab3a132ed0eff457e424226a435a901da30d3";
    hash = "sha256-mNnDzBcOp1X10dzmiW0iBAkb74QjuzMO4slWudxXCTE=";
  };

  nativeBuildInputs = [
    pkg-config
    copyDesktopItems
  ];

  # Software Vulkan driver (lavapipe) for the wgpu-based egui_kittest tests inside the sandbox;
  # upstream CI gets one from the runner image's mesa. A slim vulkanDrivers-only override breaks
  # this tree's multi-output mesa builder (no spirv2dxil output).
  lavapipe = mesa;

  buildInputs = [
    libx11
    libxcb
    libGL
    libxkbcommon
    wayland
    vulkan-loader
    finalAttrs.lavapipe
    # dlopened at runtime by winit/x11-dl, x11rb (dl-libxcb), xkbcommon-dl and g-desktop-portal;
    # the fork's libx11 also ships libX11-xcb.so.1 in the same dir.
    libxcursor
    libxi
    dbus
  ];

  cargoBuildFlags = [ "-p" "cadcraft" "-p" "cadcraft-cli" ];

  preCheck = ''
    # The wgpu-based egui_kittest tests dlopen libvulkan.so.1 at runtime and need a Vulkan ICD;
    # this tree's stdenv sets no LD_LIBRARY_PATH, so point them at the loader and lavapipe
    # explicitly (upstream CI gets both from the runner image).
    export VK_ICD_FILENAMES=$(ls ${finalAttrs.lavapipe}/share/vulkan/icd.d/*lvp*.json | tr '\n' ':')
    export LD_LIBRARY_PATH="${vulkan-loader}/lib:${finalAttrs.lavapipe}/lib"
  '';

  env = {
    CRAFT_FONTS_DIR = "${finalAttrs.craft-fonts}";
    CRAFT_FONTS_REQUIRED = "1";
  };

  postInstall = ''
    # Install under the hicolor theme and publish an index.theme; without one, GTK/KDE icon
    # lookups cannot see the icons (upstream ships no index.theme).
    install -d $out/share/icons/hicolor
    cp -r assets/app-icon/hicolor/* $out/share/icons/hicolor/
    printf '%s\n' \
      '[Icon Theme]' \
      'Name=Hicolor' \
      'Directories=16x16,24x24,32x32,48x48,64x64,128x128,256x256,256x256@2,512x512,scalable' \
      'Contexts=Apps' \
      > $out/share/icons/hicolor/index.theme

    docdir=$out/share/doc/${finalAttrs.pname}-${finalAttrs.version}
    install -d $docdir
    for lic in ${finalAttrs.craft-fonts}/fonts/*/OFL.txt; do
      install -Dm644 "$lic" "$docdir/OFL-$(basename "$(dirname "$lic")").txt"
    done
  '';

  postFixup = ''
    patchelf --set-rpath "${lib.makeLibraryPath [ libx11 libxcb libGL libxkbcommon wayland vulkan-loader libxcursor libxi dbus ]}" \
      $out/bin/cadcraft
  '';

  desktopItem = makeDesktopItem {
    name = "cadcraft";
    desktopName = "CADCraft";
    genericName = "Computer-Aided Design";
    icon = "ai.storyteller.cadcraft";
    tryExec = "cadcraft";
    exec = "cadcraft";
    comment = "Draft, dimension and plot 2D drawings; open DXF and DWG files";
    mimeTypes = [
      "image/vnd.dxf"
      "image/vnd.dwg"
      "application/x-dxf"
      "application/acad"
    ];
    categories = [ "Graphics" "Engineering" "VectorGraphics" ];
    startupNotify = true;
    startupWMClass = "ai.storyteller.cadcraft";
    keywords = [
      "cad"
      "drafting"
      "dxf"
      "dwg"
      "drawing"
      "engineering"
      "architecture"
      "mechanical"
    ];
  };

  desktopItems = [ finalAttrs.desktopItem ];

  meta = {
    description = "CADCraft desktop app";
    homepage = "https://github.com/storytold/cadcraft";
    license = lib.licenses.OR [
      lib.licenses.asl20
      lib.licenses.mit
    ];
    mainProgram = "cadcraft";
    maintainers = with lib.maintainers; [
      gaelj
    ];
  };
})
