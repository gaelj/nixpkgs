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
  versionCheckHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "figcraft";
  version = "0.7.0";
  __structuredAttrs = true;

  # Upstream releases build against this craft-fonts revision (release.yml craft-fonts-ref); it
  # embeds the latin presentation fonts plus the non-CJK families from manifest.txt.
  craft-fonts = fetchFromGitHub {
    owner = "storytold";
    repo = "craft-fonts";
    rev = "43913056ce82a3fdad0ef69f6b88d1dc922a8104";
    hash = "sha256-u1fC5spekizPXnrK6uiKEZSr2SJOaBF4ffLDbKkywEY=";
  };

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "figcraft";
    tag = "v${finalAttrs.version}";
    hash = "sha256-0K9K3EEe/HKpufzW8ym9NUwsNpioUvPUxV9rxpoJU2Q=";
  };

  cargoHash = "sha256-BdDJmIoTAH06y+bvfY8WyzxgV7572oxSdkA8kN4wz4E=";

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
    # dlopened at runtime by winit/x11-dl, x11rb (dl-libxcb), xkbcommon-dl, wgpu and zbus; the
    # fork's libx11 also ships libX11-xcb.so.1 in the same dir. No audio stack.
    libxcursor
    libxi
    dbus
  ];

  env = {
    CRAFT_FONTS_DIR = "${finalAttrs.craft-fonts}";
    CRAFT_FONTS_REQUIRED = "1";
  };

  cargoBuildFlags = [
    "-p"
    "figcraft"
    "-p"
    "figcraft-cli"
  ];

  # The recovery tests in the app binary race on parallel test threads (shared pid-based temp dirs
  # and local mock servers) and flake under load; serialize them, as lightcraft does for its flock
  # tests. every_column_fits_the_about_window measures egui text layout, which the sandbox's bare
  # font set renders wider than ABOUT_WIDTH (desktop hosts with a full fontconfig pass it).
  cargoTestFlags = [
    "--"
    "--test-threads=1"
    "--skip"
    "every_column_fits_the_about_window"
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
      $out/bin/figcraft
  '';

  desktopItem = makeDesktopItem {
    name = "figcraft";
    desktopName = "FigCraft";
    genericName = "Interface Design Tool";
    icon = "ai.storyteller.figcraft";
    tryExec = "figcraft";
    exec = "figcraft";
    comment = "Design and prototype user interfaces";
    mimeTypes = [
      "application/x-figcraft"
      "image/svg+xml"
      "image/png"
      "image/jpeg"
    ];
    categories = [
      "Graphics"
      "2DGraphics"
      "VectorGraphics"
    ];
    startupNotify = true;
    startupWMClass = "figcraft";
    keywords = [
      "design"
      "interface"
      "ui"
      "ux"
      "prototype"
      "wireframe"
      "mockup"
      "vector"
      "layout"
      "components"
    ];
  };

  desktopItems = [ finalAttrs.desktopItem ];

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "FigCraft interface design and prototyping";
    homepage = "https://github.com/storytold/figcraft";
    changelog = "https://github.com/storytold/figcraft/releases/tag/${finalAttrs.src.tag}";
    license = lib.licenses.OR [
      lib.licenses.asl20
      lib.licenses.mit
    ];
    mainProgram = "figcraft";
    maintainers = with lib.maintainers; [
      gaelj
    ];
    platforms = rustc.meta.platforms;
  };
})
