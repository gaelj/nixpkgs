{ lib
, fetchFromGitHub
, rustPlatform
, rustc
, pkg-config
, copyDesktopItems
, makeDesktopItem
, patchelf
, alsa-lib
, libx11
, libxcb
, libGL
, libxkbcommon
, nix-update-script
, wayland
, vulkan-loader
, libxcursor
, libxi
, dbus
, versionCheckHook
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "effectcraft";
  version = "0.8.0";
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "effectcraft";
    tag = "v${finalAttrs.version}";
    hash = "sha256-3AXfnxlerTqw/5QLClauTvlpEXpXwksuLfzpe96HAoA=";
  };

  # Single recursive hash over the whole vendored tree (the filmcraft-aac git dependency is
  # covered by it too).
  cargoHash = "sha256-WJo1nqiP1uQA5hXs1jaLO0CmyxZ1oqEOQ90N9BEsxSc=";

  nativeBuildInputs = [
    pkg-config
    copyDesktopItems
  ];

  buildInputs = [
    alsa-lib
    libx11
    libxcb
    libGL
    libxkbcommon
    wayland
    vulkan-loader
    # dlopened at runtime by winit/x11-dl, x11rb (dl-libxcb), xkbcommon-dl, wgpu, cpal and
    # g-desktop-portal; the fork's libx11 also ships libX11-xcb.so.1 in the same dir.
    libxcursor
    libxi
    dbus
  ];

  cargoBuildFlags = [
    "-p"
    "effectcraft"
    "-p"
    "effectcraft-cli"
  ];

  # The effectcraft-gpu parity suite compares GPU kernels against the CPU renderer and skips every
  # comparison when no wgpu adapter is present (upstream's headless-CI behaviour). We deliberately
  # do not force one here: the only adapter a build sandbox can provide is lavapipe, whose software
  # path returns `None` (CPU fallback) for many effect families, which those tests score as a
  # failure. Leaving the adapter absent keeps the suite green and matches upstream CI.
  # A handful of egui_kittest tests cannot cope with the missing adapter: one builds a `.wgpu()`
  # harness unconditionally (not `#[ignore]`d at this version), and four ui_viewer tests lazily
  # create a wgpu RenderState when rendering viewer content mid-drag, aborting with "No adapter
  # found" (egui_kittest 0.36.2). A full `--no-fail-fast` pass over the whole workspace confirmed
  # these five are the only adapter-dependent tests at this version.
  cargoTestFlags = [
    "--"
    "--skip"
    "on_draw_concave_fills_and_images_render"
    "--skip"
    "a_layer_drag_moves_the_picture_while_the_button_is_down"
    "--skip"
    "shape_drag_ghost_normalises_the_same_way_as_the_release"
    "--skip"
    "shape_drag_ghost_shows_the_tools_own_shape_while_dragging"
    "--skip"
    "shape_drag_ghost_shows_where_the_shape_will_land"
  ];

  # stdenv points TMPDIR at /build/<drv>, but footage_check::tests::relative_footage_is_found_next_to_the_project
  # sorts the paths it stores against a literal "/nonexistent/..." entry and assumes its temp_dir()-based path
  # sorts after that. "/build/..." sorts before "/nonexistent/...", so restore /tmp (writable, disk-backed in
  # the sandbox) to keep the assertion's ordering assumption true.
  preCheck = ''
    export TMPDIR=/tmp
  '';

  postInstall = ''
    install -d $out/share/icons
    cp -r assets/app-icon/hicolor $out/share/icons
  '';

  postFixup = ''
    patchelf --set-rpath "${
      lib.makeLibraryPath [
        alsa-lib
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
      $out/bin/effectcraft
  '';

  desktopItem = makeDesktopItem {
    name = "effectcraft";
    desktopName = "EffectCraft";
    genericName = "Motion Graphics Editor";
    icon = "ai.storyteller.effectcraft";
    tryExec = "effectcraft";
    exec = "effectcraft";
    comment = "Motion graphics and visual effects compositor";
    categories = [
      "AudioVideo"
      "Video"
      "Graphics"
      "2DGraphics"
    ];
    startupNotify = true;
    startupWMClass = "ai.storyteller.effectcraft";
    keywords = [
      "motion"
      "graphics"
      "animation"
      "compositor"
      "effects"
      "keyframe"
      "vfx"
    ];
  };

  desktopItems = [ finalAttrs.desktopItem ];

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "EffectCraft desktop app";
    homepage = "https://github.com/storytold/effectcraft";
    license = lib.licenses.OR [
      lib.licenses.asl20
      lib.licenses.mit
    ];
    mainProgram = "effectcraft";
    maintainers = with lib.maintainers; [
      gaelj
    ];
    platforms = rustc.meta.platforms;
  };
})
