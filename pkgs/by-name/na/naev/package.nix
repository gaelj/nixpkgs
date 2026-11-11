{
  lib,
  stdenv,
  fetchFromCodeberg,
  rustPlatform,
  cargo,
  rustc,
  rust-bindgen,
  clang,
  pkg-config,
  python3,
  enet,
  freetype,
  glpk,
  intltool,
  libunibreak_7,
  libvorbis,
  libxml2,
  luajit,
  meson,
  ninja,
  openal,
  openblas,
  opus,
  pcre2,
  physfs,
  suitesparse,
  cmark,
  sdl3,
  dav1d,
  libgit2,
  libssh2,
  openssl,
  zlib,
  perl,
  nasm,
  cmake,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "naev";
  version = "0.13.5";

  # naev 0.13.x is a Rust/SDL3 rewrite whose source ships no Cargo.lock (the
  # lockfile is generated at build time from Cargo.toml.in templates), so
  # inject one: rustPlatform.fetchCargoVendor and the offline meson-driven
  # cargo build both need src/Cargo.lock.
  # The `assets` submodule stores game data in Git LFS; without fetchLFS the
  # fonts and music are 130-byte pointer files and naev segfaults at startup.
  src = fetchFromCodeberg {
    owner = "naev";
    repo = "naev";
    tag = "v${finalAttrs.version}";
    hash = "sha256-kGVG0ZNZmyaBIkZ7lnXW4sazW/ZqTCMrK2dXeEV0Sko=";
    fetchSubmodules = true;
    fetchLFS = true;
    postFetch = "cp ${./Cargo.lock} $out/Cargo.lock";
  };

  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit (finalAttrs) pname version src;
    hash = "sha256-2CGkVxh7AqMPtMvyv8oVLWYmj7I0KQKqF0nMXnYRmdE=";
  };

  patches = [ ./offline-cargo.patch ];

  buildInputs = [
    enet
    freetype
    glpk
    libunibreak_7
    libvorbis
    libxml2
    luajit
    openal
    openblas
    opus
    pcre2
    physfs
    suitesparse
    cmark
    sdl3
    dav1d
    libgit2
    libssh2
    openssl
    zlib
  ];

  nativeBuildInputs = [
    cargo
    rustc
    rust-bindgen
    clang
    rustPlatform.cargoSetupHook
    (python3.withPackages (
      ps: with ps; [
        pyyaml
        mutagen
      ]
    ))
    meson
    ninja
    pkg-config
    intltool
    perl
    nasm
    cmake
  ];

  mesonFlags = [
    "-Ddocs_c=disabled"
    "-Ddocs_lua=disabled"
    "-Dluajit=enabled"
  ];

  postPatch = ''
    # naev runs many .py/.sh scripts at meson configure and build time
    # (dat/tech/*.sh, src/*_c_gen.py, utils/build/*.py, ...) with
    # `#!/bin/bash` / `#!/usr/bin/env python3` shebangs that do not resolve
    # in the build sandbox. Skip the assets submodule: pure game data.
    patchShebangs --build dat utils src po test subprojects/packagefiles
  '';

  meta = {
    description = "2D action/rpg space game";
    mainProgram = "naev";
    homepage = "https://naev.org";
    license = lib.licenses.gpl3Plus;
    maintainers = with lib.maintainers; [ ralismark ];
    platforms = lib.platforms.linux;
  };
})
