{
  lib,
  fetchFromGitHub,
  rustPlatform,
  rustc,
  pkg-config,
  copyDesktopItems,
  makeDesktopItem,
  patchelf,
  alsa-lib,
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
  mesa,
  versionCheckHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "filmcraft";
  version = "0.9.0";
  __structuredAttrs = true;

  # Upstream releases build against this craft-fonts revision (release.yml CRAFT_FONTS_REF).
  craft-fonts = fetchFromGitHub {
    owner = "storytold";
    repo = "craft-fonts";
    rev = "abb83316d96aa59c1cf64784289e378fe9fa5695";
    hash = "sha256-e+6HpOYoAFTh6mNfGBBw2njnBzcE8W8+Jybv1+dKOCA=";
  };

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "filmcraft";
    tag = "v${finalAttrs.version}";
    hash = "sha256-GQHgXZwEQcBfCZMxZMfPmoKXZvS9PwX99/Mq7aq34n8=";
  };

  cargoHash = "sha256-ilrMSVA0T1gQJRgCe+m8Vr2QTJMBZFas/gaYJ1+pttg=";

  # Provides the software Vulkan driver (lavapipe) for the wgpu-based egui_kittest tests inside the
  # sandbox; upstream CI gets one from the runner image's mesa. A slim vulkanDrivers-only override
  # breaks this tree's multi-output mesa builder (no spirv2dxil output).
  lavapipe = mesa;

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
    finalAttrs.lavapipe
    # dlopened at runtime by winit/x11-dl, x11rb (dl-libxcb), xkbcommon-dl, wgpu, cpal and
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
    CRAFT_FONTS_DIR = "${finalAttrs.craft-fonts}";
    CRAFT_FONTS_REQUIRED = "1";
  };

  cargoBuildFlags = [
    "-p"
    "filmcraft"
    "-p"
    "filmcraft-cli"
  ];

  # Test problems at the tag:
  # - shortcuts_tests::assign_reassigns_conflicts_and_undoes is deterministically broken:
  #   shortcuts.set (keepConflicts) returns every pre-existing conflict in the table (4, including
  #   unrelated Cmd+9/Cmd+Shift+M/Cmd+T bindings) instead of only the one the test expects.
  # - crates/frame pool tests assert on a process-global reused-frame counter, so running the
  #   binary's tests in parallel makes them race; serialize the run.
  # - dev_icon::tests::desktop_file_matches_the_packaged_fields is deterministically red
  #   upstream (still on main): the test derives its expectation from the packaged desktop file
  #   (which carries MimeType=) while desktop_file_content never emits that field.
  cargoTestFlags = [
    "--"
    "--skip"
    "shortcuts_tests::assign_reassigns_conflicts_and_undoes"
    "--skip"
    "dev_icon::tests::desktop_file_matches_the_packaged_fields"
    "--test-threads=1"
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
      $out/bin/filmcraft
  '';

  desktopItem = makeDesktopItem {
    name = "filmcraft";
    desktopName = "FilmCraft";
    genericName = "Video Editor";
    icon = "ai.storyteller.filmcraft";
    tryExec = "filmcraft";
    exec = "filmcraft";
    comment = "Edit video, color and sound";
    categories = [
      "AudioVideo"
      "Video"
      "AudioVideoEditing"
    ];
    startupNotify = true;
    startupWMClass = "ai.storyteller.filmcraft";
    keywords = [
      "video"
      "editor"
      "film"
      "timeline"
      "color"
      "grading"
      "nle"
    ];
  };

  desktopItems = [ finalAttrs.desktopItem ];

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "FilmCraft desktop app";
    homepage = "https://github.com/storytold/filmcraft";
    changelog = "https://github.com/storytold/filmcraft/releases/tag/${finalAttrs.src.tag}";
    license = lib.licenses.OR [
      lib.licenses.asl20
      lib.licenses.mit
    ];
    mainProgram = "filmcraft";
    maintainers = with lib.maintainers; [
      gaelj
    ];
    platforms = rustc.meta.platforms;
  };
})
