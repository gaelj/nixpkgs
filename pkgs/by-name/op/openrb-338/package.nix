{
  alsa-lib,
  dbus,
  fetchFromGitHub,
  lib,
  libGL,
  libx11,
  libxcb,
  libxcursor,
  libxi,
  libxkbcommon,
  nix-update-script,
  pkg-config,
  python3,
  rustPlatform,
  vulkan-loader,
  wayland,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "openrb-338";
  version = "2026.1113.1528";
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "pingw33n";
    repo = "OpenRB-338";
    tag = "v${finalAttrs.version}";
    hash = "sha256-05kLn+yL5a/TfNbGz7UIS/qpVyLL7dBnQCLGEu5S0us=";
  };

  cargoHash = "sha256-/39AE6DrlIMWfyHoMRt2/KrpxiN6jQiyRX+cMxcT6/s=";

  nativeBuildInputs = [
    pkg-config
  ];

  # winit 0.30 dlopens the X11 client libraries by bare soname, and wgpu
  # libvulkan.so.1; every dlopen target must be in the closure and in the
  # RUNPATH (patchelf below). The observed chain is libX11 -> libXcursor ->
  # libX11-xcb (shipped by this tree's libx11) -> libXi; libXrender/libXfixes/
  # libXext then resolve through the RUNPATHs of the packages that need them.
  # The AppImage script also bundles libxkbcommon-x11.so.0 and libxcb-xkb.so.1,
  # which this tree's libxkbcommon and libxcb ship.
  buildInputs = [
    alsa-lib
    libx11
    libxcb
    libxcursor
    libxi
    libxkbcommon
    libGL
    wayland
    vulkan-loader
    dbus
  ];

  # Several cross-format tests (rb1x_messages, rbsmsg_corpus, corpus, recrypt,
  # thirdparty) compare against the reference tools in tools/*.py and panic
  # when no Python 3 is on PATH (they honour ORB_PYTHON; python3 suffices).
  nativeCheckInputs = [
    python3
  ];

  postInstall = ''
    rm $out/bin/ui-art # developer icon-rendering tool, not a user command

    # substitute does not create the target's parent directory
    mkdir -p $out/share/applications
    substitute scripts/OpenRB-338.desktop.in $out/share/applications/OpenRB-338.desktop \
      --replace-fail '@EXEC@' 'OpenRB-338' \
      --replace-fail '@ICON@' 'OpenRB-338'

    # Upstream renders PNGs from assets/ui/app_icon.svg with `ui-art iconset`
    # for the AppImage; the scalable SVG is what the icon theme lookup needs.
    install -Dm644 assets/ui/app_icon.svg $out/share/icons/hicolor/scalable/apps/OpenRB-338.svg
  '';

  postFixup = ''
    patchelf --set-rpath "${
      lib.makeLibraryPath [
        alsa-lib
        libx11
        libxcb
        libxcursor
        libxi
        libxkbcommon
        libGL
        wayland
        vulkan-loader
        dbus
      ]
    }" $out/bin/OpenRB-338
  '';

  # Neither binary implements --version (and versionCheckHook greps for the
  # version string), so smoke-test the help paths instead. OpenRB-338 prints
  # its usage and exits 0 before it touches the display.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/OpenRB-338" --help > /dev/null
    "$out/bin/orb" --help > /dev/null
    runHook postInstallCheck
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "ReBirth RB-338 reimplementation";
    homepage = "https://github.com/pingw33n/OpenRB-338";
    changelog = "https://github.com/pingw33n/OpenRB-338/releases/tag/${finalAttrs.src.tag}";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ gaelj ];
    mainProgram = "OpenRB-338";
    platforms = lib.platforms.linux;
  };
})
