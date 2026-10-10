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
  version = "0.3.0";
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "cadcraft";
    tag = "v${finalAttrs.version}";
    hash = "sha256-VFw6np9BSOdBQrKlIiNnQ0kKKNfGnYMctbceBpmE778=";
  };

  cargoLock = { lockFile = "${finalAttrs.src}/Cargo.lock"; };

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
    install -d $out/share/icons
    cp -r assets/app-icon/hicolor/* $out/share/icons/
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
