{ lib
, fetchFromGitHub
, rustPlatform
, pkg-config
, git
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
, craftFonts
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "pdfcraft";
  version = "0.4.0";
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "pdfcraft";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Fkzo9qb9obrXa1X4klio+gRgM2UZIO8QwfI0/xSYwmo=";
  };

  cargoLock = { lockFile = "${finalAttrs.src}/Cargo.lock"; };

  # `rten-gemm` has AVX-512 VNNI int8 kernels that call `_mm512_dpbusd_epi32`. With the
  # current toolchain, stdarch's signature for that intrinsic mismatches LLVM's
  # `llvm.x86.avx512.vpdpbusd.512`, so the crate fails to compile (same workaround as
  # python3Packages.rerun-sdk). Drop the AVX-512 VNNI dispatch branch: the kernels then
  # become dead code, so they are never codegen'd and runtime dispatch falls back to the
  # equivalent AVX2 / scalar kernels.
  postPatch = ''
    rtenGemmi8dot="$cargoDepsCopy/rten-gemm-0.26.0/src/i8dot.rs"

    sed -i '/if let Some(isa) = x86_64::Avx512VnniIsa::new() {$/,+2d' "$rtenGemmi8dot"
    if grep -qF 'dispatch_avx512_vnni(isa, self)' "$rtenGemmi8dot"; then
      echo "postPatch: failed to remove the rten-gemm AVX-512 VNNI dispatch" >&2
      exit 1
    fi
  '';

  # Provides the software Vulkan driver (lavapipe) for the wgpu-based egui_kittest tests inside the
  # sandbox; upstream CI gets one from the runner image's mesa. A slim vulkanDrivers-only override
  # breaks this tree's multi-output mesa builder (no spirv2dxil output).
  lavapipe = mesa;

  nativeBuildInputs = [
    pkg-config
    git
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

    # `xtask assets`'s the_real_manifest_passes test lists the tree with `git ls-files`; the sandbox
    # has no VCS. Initialise a throwaway repository over the unpacked source: with an empty index,
    # `git ls-files --cached --others --exclude-standard` reports exactly the non-ignored files, i.e.
    # the set a real checkout tracks (/target is gitignored). Same repo serves xtask/src/gates.rs.
    # Point global config into $TMPDIR: the sandbox's HOME (/homeless-shelter) does not exist, so a
    # plain `git config --global ...` would fail to write ~/.gitconfig.
    export GIT_CONFIG_GLOBAL="$TMPDIR/pdfcraft.gitconfig"
    printf '[safe]\n\tdirectory = *\n' > "$GIT_CONFIG_GLOBAL"
    git init -q
  '';

  env = {
    CRAFT_FONTS_DIR = "${craftFonts}";
    CRAFT_FONTS_REQUIRED = "1";
  };

  cargoBuildFlags = [ "-p" "pdfcraft" "-p" "pdfcraft-cli" ];

  postInstall = ''
    install -d $out/share/icons
    cp -r assets/app-icon/hicolor/* $out/share/icons/

    docdir=$out/share/doc/${finalAttrs.pname}-${finalAttrs.version}
    install -d $docdir
    for lic in ${craftFonts}/fonts/*/OFL.txt; do
      install -Dm644 "$lic" "$docdir/OFL-$(basename "$(dirname "$lic")").txt"
    done
  '';

  postFixup = ''
    patchelf --set-rpath "${lib.makeLibraryPath [ libx11 libxcb libGL libxkbcommon wayland vulkan-loader libxcursor libxi dbus ]}" \
      $out/bin/pdfcraft
  '';

  desktopItem = makeDesktopItem {
    name = "pdfcraft";
    desktopName = "PdfCraft";
    genericName = "PDF Editor";
    icon = "ai.storyteller.pdfcraft";
    tryExec = "pdfcraft";
    exec = "pdfcraft";
    comment = "Read, organize, combine, split and secure PDFs";
    mimeTypes = [
      "application/pdf"
    ];
    categories = [ "Office" "Viewer" "Graphics" ];
    startupNotify = true;
    startupWMClass = "pdfcraft";
    keywords = [
      "pdf"
      "viewer"
      "editor"
      "annotate"
      "sign"
      "forms"
      "merge"
      "split"
    ];
  };

  desktopItems = [ finalAttrs.desktopItem ];

  meta = {
    description = "PdfCraft desktop app";
    homepage = "https://github.com/storytold/pdfcraft";
    license = lib.licenses.OR [
      lib.licenses.asl20
      lib.licenses.mit
    ];
    mainProgram = "pdfcraft";
    maintainers = with lib.maintainers; [
      gaelj
    ];
  };
})
