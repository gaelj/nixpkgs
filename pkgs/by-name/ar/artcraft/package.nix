{ lib
, fetchFromGitHub
, rustPlatform
, buildNpmPackage
, cargo-tauri
, pkg-config
, patchelf
, webkitgtk_4_1
, gtk3
, glib
, librsvg
 , libsoup_3
 , pango
 , gdk-pixbuf
 , cairo
 , dbus
 , git
 , cmake
 , ninja
 , perl
}:

let
  version = "0.41.0";
  src = fetchFromGitHub {
    owner = "storytold";
    repo = "artcraft";
    tag = "artcraft-v${version}";
    hash = "sha256-kO4kHtU6cINVDpzxtTzq8s1nf8zqilHcJc7Fsi+iN0U=";
  };

  # ArtCraft's frontend is an Nx monorepo rooted at `frontend/`, where `apps/artcraft` is an npm
  # workspace member whose "build" script runs Vite. buildNpmPackage fetches the (fixed-output) node
  # dependency tree, then runs `npm run --workspace=artcraft build`; installPhase keeps the built
  # bundle in apps/artcraft/dist.
  frontend = buildNpmPackage (fa: {
    pname = "artcraft-frontend";
    inherit version src;
    sourceRoot = "${src.name}/frontend";

    npmDepsFetcherVersion = 2;        # monorepo / workspace support
    npmWorkspace = "artcraft";
    npmBuildScript = "build";         # the app's `vite build` target
    npmDepsHash = "sha256-MdPy2OlDsZKVE6lcKzUNvPzWAAalKgECWwcQjOyhMNc=";

    env.NODE_OPTIONS = "--max-old-space-size=8192";

    # `npm ci` (in the npm config hook) runs `patchShebangs node_modules`, but that only walks the
    # top-level node_modules; the app's nested workspace node_modules (apps/artcraft/node_modules)
    # keeps "#!/usr/bin/env node" shebangs. The nix build environment has no /usr/bin/env, so the
    # vite shim fails with "bad interpreter". Repoint any remaining env shebangs at the store node
    # (resolved at build time, where node is on PATH).
    preBuild = ''
      grep -rlZ '^#!/usr/bin/env node' node_modules apps 2>/dev/null \
        | xargs -0 -r sed -i "1s|^#!/usr/bin/env node|#!$(command -v node)|"
    '';

    installPhase = ''
      runHook preInstall
      cp -a apps/artcraft/dist/. $out/
      runHook postInstall
    '';
  });
in
# ArtCraft is a Tauri 2 desktop app: a Rust shell wrapping the React/Vite frontend. The JS bundle is
# produced inside Nix by `frontend` above, then wired in so `cargo tauri build` finds it at the path
# its tauri.conf.json expects (`../../../frontend/apps/artcraft/dist`) instead of rebuilding it. It is
# packaged on the same `webkitgtk_4_1` + `gtk3` Linux webview stack that Tauri / wry require; the
# cargo-tauri hook bundles a .deb whose data/usr tree (binary, .desktop and icons) is extracted to $out.
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "artcraft";
  inherit version;
  __structuredAttrs = true;

  src = src;
  cargoLock = { lockFile = "${src}/Cargo.lock"; };

  # Tauri builds from the desktop crate, a member of the workspace rooted at the repo top. The
  # hook pushd's into buildAndTestSubdir and points cargo's target dir there too.
  buildAndTestSubdir = "crates/desktop/artcraft";

  nativeBuildInputs = [
    pkg-config
    # boring-sys2 (pulled in by wreq) runs bindgen against the BoringSSL headers at build time.
    rustPlatform.bindgenHook
    # boring-sys2 compiles its vendored BoringSSL from source (it first `git init`s the vendored tree
    # and `git apply`s its custom patches, then builds with cmake + ninja); see the postPatch comment.
    git
    perl
    # Replaces cargo build with `cargo tauri build` (bundle) and the corresponding install/fixup hooks.
    cargo-tauri.hook
  ];

  # cmake and ninja are deliberately NOT in nativeBuildInputs: registering a build system there makes
  # stdenv run its own make/cmake buildPhase (invoking ninja at the top level, where there is no
  # top-level CMakeLists.txt) instead of the cargo-tauri hook's buildPhase, so the Tauri build would
  # never start. boring-sys2's build.rs (cmake-rs) only needs them on PATH, so they are prepended here;
  # preBuild runs in the build phase and is inherited by the cargo build's build.rs invocations.
  preBuild = ''
    export PATH="${cmake}/bin:${ninja}/bin:$PATH"
  '';

  buildInputs = [
    webkitgtk_4_1
    gtk3
    glib
    librsvg
    libsoup_3
  ];

  # sqlx compile-time-checked queries read the committed .sqlx/ cache. wreq pulls in boring2 ->
  # boring-sys2, which compiles Google BoringSSL from its vendored source. The bleeding-edge TLS API
  # it links against (delegated_credentials, record_size_limit, zstd cert compression, ALPS, ...) is
  # added by a build-time patch (boringssl-<base>.patch) that boring-sys2 applies to a plain upstream
  # BoringSSL tree; no prebuilt BoringSSL carries it, so the source path (not a BORING_BSSL_PATH
  # precompiled lib) is used. `git init` + `git apply` are local (no network) and run against the
  # vendored tree, whose CMakeLists.txt is already present, so no submodule clone is needed.
  env = {
    SQLX_OFFLINE = "true";
    # boring-sys2 builds BoringSSL with the `cmake` crate, which drives a Ninja build; force the
    # matching generator at configure time so build.ninja is actually produced.
    CMAKE_GENERATOR = "Ninja";
  };

  # Provide the prebuilt frontend where Tauri expects it, and stop `cargo tauri build` from trying to
  # rebuild it (the config's beforeBuildCommand is an Nx target with no Node.js in this closure).
  postPatch = ''
    substituteInPlace crates/desktop/artcraft/tauri.conf.json \
      --replace-fail '"npx nx run artcraft:build"' '""'
    mkdir -p frontend/apps/artcraft/dist
    cp -a ${frontend}/* frontend/apps/artcraft/dist/
  '';

  # First packaging pass: skip the check phase (the JS unit/playwright suites need a display and
  # network); revisit once the build is green.
  doCheck = false;

  passthru = { inherit frontend; };

  postFixup = ''
    # The app directly links (DT_NEEDED) pango, gdk-pixbuf, cairo(+cairo-gobject) and dbus in
    # addition to the gtk3/glib/webkitgtk/libsoup set, so all of them must be in DT_RUNPATH or the
    # dynamic linker can't resolve them at load time. Transitive deps (harfbuzz, freetype,
    # fontconfig, gstreamer, ...) are resolved by each library's own DT_RUNPATH.
    patchelf --set-rpath "${lib.makeLibraryPath [ webkitgtk_4_1 gtk3 glib librsvg libsoup_3 pango gdk-pixbuf cairo dbus ]}" \
      $out/bin/artcraft
  '';

  meta = {
    description = "ArtCraft AI creative studio desktop app (Tauri 2)";
    homepage = "https://github.com/storytold/artcraft";
    # TODO(license): the repo ships an undefined custom "ArtCraft License (WIP)" in LICENSE.md;
    # replace with a proper SPDX id once it is finalised.
    license = lib.licenses.unfree;
    mainProgram = "artcraft";
    maintainers = with lib.maintainers; [
      gaelj
    ];
  };
})
