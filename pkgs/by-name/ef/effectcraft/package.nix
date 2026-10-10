{ lib
, fetchFromGitHub
, rustPlatform
, pkg-config
, copyDesktopItems
, makeDesktopItem
, patchelf
, alsa-lib
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
  pname = "effectcraft";
  version = "0.6.0";
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "effectcraft";
    tag = "v${finalAttrs.version}";
    hash = "sha256-O3s4cFkqcQS3+xxby/oY7uqkBLbQsRsPR1xQsw+5FQ8=";
  };

  cargoLock = {
    lockFile = "${finalAttrs.src}/Cargo.lock";
    # filmcraft-aac is a git dependency (pinned in the lockfile); its unpacked tree needs an
    # explicit recursive output hash.
    outputHashes = {
      "filmcraft-aac-0.1.1" = "sha256-WXiX4rF7zSwfu3yu9aNH2/xWYhAYFVX1rdrnccuTD7g=";
    };
  };

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

  cargoBuildFlags = [ "-p" "effectcraft" "-p" "effectcraft-cli" ];

  # The effectcraft-gpu parity suite compares GPU kernels against the CPU renderer and skips every
  # comparison when no wgpu adapter is present (upstream's headless-CI behaviour). We deliberately
  # do not force one here: the only adapter a build sandbox can provide is lavapipe, whose software
  # path returns `None` (CPU fallback) for many effect families, which those tests score as a
  # failure. Leaving the adapter absent keeps the suite green and matches upstream CI.
  # One egui_kittest test (`on_draw_concave_fills_and_images_render`) unconditionally builds a
  # `.wgpu()` harness (not `#[ignore]`d at this version) and cannot run without an adapter.

  cargoTestFlags = [ "--" "--skip" "on_draw_concave_fills_and_images_render" ];

  postInstall = ''
    install -d $out/share/icons
    cp -r assets/app-icon/hicolor/* $out/share/icons/
  '';

  postFixup = ''
    patchelf --set-rpath "${lib.makeLibraryPath [ alsa-lib libx11 libxcb libGL libxkbcommon wayland vulkan-loader libxcursor libxi dbus ]}" \
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
    categories = [ "AudioVideo" "Video" "Graphics" "2DGraphics" ];
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
  };
})
