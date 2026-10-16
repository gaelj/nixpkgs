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
    # dlopened at runtime by winit/x11-dl, x11rb (dl-libxcb), xkbcommon-dl and g-desktop-portal;
    # the fork's libx11 also ships libX11-xcb.so.1 in the same dir.
    libxcursor
    libxi
    dbus
  ];

  cargoBuildFlags = [ "-p" "cadcraft" "-p" "cadcraft-cli" ];

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
