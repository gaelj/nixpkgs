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
  pname = "photocraft";
  version = "0.5.0";
  __structuredAttrs = true;

  # v0.5.0 is released against this craft-fonts revision; newer revisions add non-Japanese
  # families that its text-engine test suite does not expect to be registered yet.
  craftFonts = fetchFromGitHub {
    owner = "storytold";
    repo = "craft-fonts";
    rev = "abb83316d96aa59c1cf64784289e378fe9fa5695";
    hash = "sha256-e+6HpOYoAFTh6mNfGBBw2njnBzcE8W8+Jybv1+dKOCA=";
  };

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "photocraft";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Ye8Fv4CPBUtqi1ZAJvXfpvyaXk7Ga9BAwl2nrsLEZWA=";
  };

  cargoLock = { lockFile = "${finalAttrs.src}/Cargo.lock"; };

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
    CRAFT_FONTS_DIR = "${finalAttrs.craftFonts}";
    CRAFT_FONTS_REQUIRED = "1";
  };

  cargoBuildFlags = [ "-p" "photocraft" "-p" "photocraft-cli" ];

  postInstall = ''
    install -d $out/share/icons
    cp -r assets/app-icon/hicolor/* $out/share/icons/

    docdir=$out/share/doc/${finalAttrs.pname}-${finalAttrs.version}
    install -d $docdir
    for lic in ${finalAttrs.craftFonts}/fonts/*/OFL.txt; do
      install -Dm644 "$lic" "$docdir/OFL-$(basename "$(dirname "$lic")").txt"
    done
  '';

  postFixup = ''
    patchelf --set-rpath "${lib.makeLibraryPath [ libx11 libxcb libGL libxkbcommon wayland vulkan-loader libxcursor libxi dbus ]}" \
      $out/bin/photocraft

    # The app's own startup lib probe only searches ldconfig/system dirs (not the binary's
    # RUNPATH), so store-provided libraries always look "missing" to it; skip its check for
    # packaged launches. Appended after build because desktop-file-validate rejects Environment=.
    sed -i '1a Environment=PHOTOCRAFT_SKIP_LIB_CHECK=1' \
      $out/share/applications/photocraft.desktop
  '';

  desktopItem = makeDesktopItem {
    name = "photocraft";
    desktopName = "PhotoCraft";
    genericName = "Image Editor";
    icon = "ai.storyteller.photocraft";
    tryExec = "photocraft";
    exec = "photocraft";
    comment = "Edit photos and layered PSD documents";
    mimeTypes = [
      "application/x-photocraft"
      "image/vnd.adobe.photoshop"
      "image/x-psd"
      "image/x-psb"
      "image/png"
      "image/jpeg"
      "image/tiff"
      "image/webp"
      "image/gif"
      "image/bmp"
      "image/x-tga"
      "image/x-icon"
      "image/vnd.microsoft.icon"
      "image/x-portable-anymap"
      "image/x-portable-bitmap"
      "image/x-portable-graymap"
      "image/x-portable-pixmap"
      "image/x-exr"
      "image/vnd.radiance"
      "image/avif"
      "image/qoi"
    ];
    categories = [ "Graphics" "2DGraphics" "RasterGraphics" "Photography" ];
    startupNotify = true;
    startupWMClass = "photocraft";
    keywords = [
      "photo"
      "image"
      "editor"
      "psd"
      "photoshop"
      "layers"
      "retouch"
      "paint"
    ];
  };

  desktopItems = [ finalAttrs.desktopItem ];

  meta = {
    description = "PhotoCraft desktop app";
    homepage = "https://github.com/storytold/photocraft";
    license = lib.licenses.OR [
      lib.licenses.asl20
      lib.licenses.mit
    ];
    mainProgram = "photocraft";
    maintainers = with lib.maintainers; [
      gaelj
    ];
  };
})
