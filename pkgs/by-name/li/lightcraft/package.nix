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
  libxinerama,
  libxt,
  dbus,
  craft-fonts,
  versionCheckHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "lightcraft";
  version = "0.6.0";
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "lightcraft";
    tag = "v${finalAttrs.version}";
    hash = "sha256-hPRTJQql7TzmqZgkmDU1W3/IQMLQD/XzHNi6Lyv4XE0=";
  };

  cargoHash = "sha256-UyQP8+z8gd5g0uoeGK6C8O0uw318vJ1l/IZ7ShTdcek=";

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
    # dlopened at runtime by winit/x11-dl, x11rb (dl-libxcb), xkbcommon-dl, wgpu and
    # g-desktop-portal; the fork's libx11 also ships libX11-xcb.so.1 in the same dir.
    # libxinerama/libxt are additionally dlopened by lightcraft's X11 helpers.
    libxcursor
    libxi
    libxinerama
    libxt
    dbus
  ];

  env = {
    CRAFT_FONTS_DIR = "${craft-fonts}";
    CRAFT_FONTS_REQUIRED = "1";
  };

  cargoBuildFlags = [
    "-p"
    "lightcraft"
    "-p"
    "lightcraft-cli"
  ];

  # Run the test binaries single-threaded: the catalog lock tests (issue #99) race on high-core
  # machines — a child spawned by one test inherits the flock file descriptors of concurrently
  # running sibling tests, so an open can be refused right after the first one lets go.
  cargoTestFlags = [
    "--"
    "--test-threads=1"
  ];

  postInstall = ''
    install -d $out/share/icons
    cp -r assets/app-icon/hicolor $out/share/icons

    docdir=$out/share/doc/${finalAttrs.pname}-${finalAttrs.version}
    install -d $docdir
    for lic in ${craft-fonts}/fonts/*/OFL.txt; do
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
        libxinerama
        libxt
        dbus
      ]
    }" \
      $out/bin/lightcraft
  '';

  desktopItem = makeDesktopItem {
    name = "lightcraft";
    desktopName = "LightCraft";
    genericName = "Photo Library and Raw Developer";
    icon = "ai.storyteller.lightcraft";
    tryExec = "lightcraft";
    exec = "lightcraft";
    comment = "Organise photos and develop raw files, non-destructively";
    mimeTypes = [
      "image/jpeg"
      "image/png"
      "image/tiff"
      "image/webp"
      "image/x-adobe-dng"
      "image/x-sony-arw"
      "image/x-canon-cr2"
      "image/x-canon-cr3"
      "image/x-nikon-nef"
      "image/x-fuji-raf"
      "image/x-olympus-orf"
      "image/x-panasonic-rw2"
      "image/x-panasonic-rw"
      "image/x-pentax-pef"
    ];
    categories = [
      "Graphics"
      "2DGraphics"
      "RasterGraphics"
      "Photography"
    ];
    startupNotify = true;
    startupWMClass = "ai.storyteller.lightcraft";
    keywords = [
      "photo"
      "raw"
      "camera"
      "library"
      "develop"
    ];
  };

  desktopItems = [ finalAttrs.desktopItem ];

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "LightCraft desktop app";
    homepage = "https://github.com/storytold/lightcraft";
    changelog = "https://github.com/storytold/lightcraft/releases/tag/${finalAttrs.src.tag}";
    license = lib.licenses.OR [
      lib.licenses.asl20
      lib.licenses.mit
    ];
    mainProgram = "lightcraft";
    maintainers = with lib.maintainers; [
      gaelj
    ];
    platforms = rustc.meta.platforms;
  };
})
