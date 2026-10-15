{ lib
, fetchFromGitHub
, rustPlatform
, rustc
, pkg-config
, copyDesktopItems
, makeDesktopItem
, patchelf
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
  pname = "craft-launcher";
  version = "0.4.1";
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "craft-launcher";
    tag = "v${finalAttrs.version}";
    hash = "sha256-mq8MeSsWRFoLhKl/7YHQiwS+yPUaUidofOXEJOZznFI=";
  };

  cargoHash = "sha256-tUkHXAaklHqAh0/gjN2ebkgL81PnQ0KjCBrxjrGw/Vw=";

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
    # dlopened at runtime by winit/x11-dl, x11rb (dl-libxcb), xkbcommon-dl, wgpu and zbus
    # (tray icon + notifications); the fork's libx11 also ships libX11-xcb.so.1 in the same dir.
    libxcursor
    libxi
    vulkan-loader
    dbus
  ];

  # Single native binary; artcraft-launcher-web is the wasm32 web build and not shipped here.
  cargoBuildFlags = [
    "-p"
    "artcraft-launcher"
  ];

  # Host-tool tests that cannot run in a nix build sandbox: one shells out to pgrep (absent; /bin
  # carries only sh and is read-only) and the other spawns hardcoded /bin/sleep and /usr/bin/touch,
  # which exist on upstream CI runners but not in the sandbox (coreutils arrive on $PATH only).
  cargoTestFlags = [
    "--"
    "--skip"
    "running_paths_are_matched_literally"
    "--skip"
    "the_restart_waits_for_the_old_process_to_exit"
  ];

  postInstall = ''
    install -d $out/share/icons
    cp -r assets/app-icon/hicolor $out/share/icons
  '';

  postFixup = ''
    patchelf --set-rpath "${
      lib.makeLibraryPath [
        libx11
        libxcb
        libGL
        libxkbcommon
        wayland
        libxcursor
        libxi
        vulkan-loader
        dbus
      ]
    }" \
      $out/bin/artcraft-launcher
  '';

  desktopItem = makeDesktopItem {
    name = "craft-launcher";
    desktopName = "ArtCraft Launcher";
    genericName = "App Launcher";
    icon = "ai.storyteller.artcraft-launcher";
    tryExec = "artcraft-launcher";
    exec = "artcraft-launcher";
    comment = "Install, update and launch the Craft App Suite";
    categories = [
      "Utility"
      "PackageManager"
    ];
    startupNotify = true;
    startupWMClass = "artcraft-launcher";
    keywords = [
      "artcraft"
      "craft"
      "launcher"
      "installer"
      "updater"
      "photocraft"
      "filmcraft"
      "apps"
    ];
  };

  desktopItems = [ finalAttrs.desktopItem ];

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "ArtCraft Launcher: install, update and open the Craft App Suite";
    homepage = "https://github.com/storytold/craft-launcher";
    changelog = "https://github.com/storytold/craft-launcher/releases/tag/${finalAttrs.src.tag}";
    license = lib.licenses.OR [
      lib.licenses.asl20
      lib.licenses.mit
    ];
    mainProgram = "artcraft-launcher";
    maintainers = with lib.maintainers; [
      gaelj
    ];
    platforms = rustc.meta.platforms;
  };
})
