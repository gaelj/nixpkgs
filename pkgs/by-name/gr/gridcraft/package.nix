{ lib
, stdenv
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
, libxcursor
, libxi
, vulkan-loader
, dbus
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "gridcraft";
  version = "0.3.0";
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "gridcraft";
    tag = "v${finalAttrs.version}";
    hash = "sha256-C7MOB7YvkYG3aE3PAEtRChdYCRi2tTfu6d/qQhTNX+c=";
  };

  cargoHash = "sha256-lYyBPwE04DrNzUtYPV3aH0mDFuryE/AWesDzV8W2NqA=";

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

  cargoBuildFlags = [ "-p" "gridcraft" "-p" "gridcraft-cli" ];

  postInstall = ''
    install -d $out/share/icons
    cp -r assets/app-icon/hicolor/* $out/share/icons/
  '';

  postFixup = ''
    patchelf --set-rpath "${lib.makeLibraryPath [ libx11 libxcb libGL libxkbcommon wayland libxcursor libxi vulkan-loader dbus ]}" \
      $out/bin/gridcraft
  '';

  desktopItem = makeDesktopItem {
    name = "gridcraft";
    desktopName = "GridCraft";
    genericName = "Spreadsheet";
    icon = "ai.storyteller.gridcraft";
    tryExec = "gridcraft";
    exec = "gridcraft";
    comment = "Calculate, analyse and chart data in workbooks";
    mimeTypes = [
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      "application/vnd.ms-excel.sheet.macroEnabled.12"
      "text/csv"
      "text/tab-separated-values"
    ];
    categories = [ "Office" "Spreadsheet" ];
    startupNotify = true;
    startupWMClass = "ai.storyteller.gridcraft";
    keywords = [
      "spreadsheet"
      "workbook"
      "sheet"
      "table"
      "formula"
      "chart"
      "pivot"
      "xlsx"
      "csv"
      "tsv"
      "excel"
    ];
  };

  desktopItems = [ finalAttrs.desktopItem ];

  meta = {
    description = "GridCraft desktop app";
    homepage = "https://github.com/storytold/gridcraft";
    license = lib.licenses.OR [
      lib.licenses.asl20
      lib.licenses.mit
    ];
    mainProgram = "gridcraft";
    maintainers = with lib.maintainers; [
      gaelj
    ];
  };
})
