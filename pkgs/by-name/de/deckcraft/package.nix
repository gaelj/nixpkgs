{
  lib,
  stdenv,
  rustPlatform,
  rustc,
  fetchFromGitHub,
  pkg-config,
  patchelf,
  copyDesktopItems,
  makeDesktopItem,
  versionCheckHook,
  alsa-lib,
  vulkan-loader,
  libxkbcommon,
  libx11,
  libxcb,
  libxcursor,
  libxi,
  libxrandr,
  wayland,
  dbus,
  nix-update-script,
}:

let
  # Loaded with dlopen by winit, wgpu and rfd (libdbus, for the file dialogs).
  runtimeDeps = [
    libxkbcommon
    libx11
    libxcb
    libxcursor
    libxi
    libxrandr
    wayland
    vulkan-loader
    dbus
  ];
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "deckcraft";
  version = "0.8.0";
  __structuredAttrs = true;
  strictDeps = true;

  # Upstream releases build against this craft-fonts revision (release.yml CRAFT_FONTS_REF).
  craft-fonts = fetchFromGitHub {
    owner = "storytold";
    repo = "craft-fonts";
    rev = "43913056ce82a3fdad0ef69f6b88d1dc922a8104";
    hash = "sha256-u1fC5spekizPXnrK6uiKEZSr2SJOaBF4ffLDbKkywEY=";
  };

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "deckcraft";
    tag = "v${finalAttrs.version}";
    hash = "sha256-kO8YBFzyip+NJmH2eFGGOB7OCOZWUhIGvEuxBzSemgk=";
  };

  cargoHash = "sha256-TlPzzZqjfKPE0D6FUSQKYkfdENzED+zNRYfQxepEBzk=";

  cargoBuildFlags = [
    "--package=deckcraft"
    "--package=deckcraft-cli"
  ];

  cargoTestFlags = [
    "--"
    "--skip"
    "tests::tables_with_a_file_defined_style_edit_and_resize"
    "--skip"
    "tests::east_asian_vertical_text_stands_ideographs_upright"
    "--skip"
    "tests::metafile_symbol_text_draws_a_bullet_not_a_box"
    "--skip"
    "canvas::guides_tests::turn_guides_on_drag_one_and_drop_it_off_the_slide"
    "--skip"
    "canvas::ruler_tests::drag_indents_add_move_and_remove_tabs_on_the_ruler"
    "--skip"
    "canvas::ruler_tests::tabs_dialog_sets_clears_and_applies_on_ok"
    "--skip"
    "canvas::ruler_tests::the_tab_selector_picks_the_kind_of_stop_a_click_sets"
    "--skip"
    "dialogs::spelling_tests::notes_menu_language_dialog_and_repeated_words"
    "--skip"
    "dialogs::spelling_tests::spelling_dialog_changes_and_ignores_words"
    "--skip"
    "dialogs::spelling_tests::squiggles_in_table_cells_and_notes_and_on_the_ui_thread"
    "--skip"
    "dialogs::spelling_tests::squiggles_mark_misspelt_words_in_the_background"
    "--skip"
    "panes::thesaurus_tests::thesaurus_pane_swaps_the_word_at_the_caret"
    "--skip"
    "ribbon::inktoshape_tests::pen_a_rectangle_then_ink_to_shape"
    "--skip"
    "tests::off_slide_objects_show_on_the_pasteboard_and_can_be_selected_and_moved"
    "--skip"
    "texture_limit_tests::presenter_view_keeps_a_portrait_next_slide_in_its_column"
  ];

  nativeBuildInputs = [
    pkg-config
    patchelf
    copyDesktopItems
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ alsa-lib ];

  desktopItems = [
    (makeDesktopItem {
      name = "ai.storyteller.deckcraft";
      desktopName = "DeckCraft";
      genericName = "Presentation";
      comment = "Create and present slide decks";
      exec = "deckcraft %F";
      tryExec = "deckcraft";
      icon = "ai.storyteller.deckcraft";
      terminal = false;
      startupNotify = true;
      startupWMClass = "ai.storyteller.deckcraft";
      categories = [
        "Office"
        "Presentation"
      ];
      keywords = [
        "presentation"
        "slides"
        "slide show"
        "deck"
        "pptx"
        "keynote"
        "powerpoint"
      ];
      mimeTypes = [
        "application/x-deckcraft"
        "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        "application/vnd.openxmlformats-officedocument.presentationml.template"
        "application/vnd.openxmlformats-officedocument.presentationml.slideshow"
      ];
    })
  ];

  postInstall = lib.optionalString stdenv.hostPlatform.isLinux ''
    install -Dm644 packaging/linux/ai.storyteller.deckcraft.mime.xml $out/share/mime/packages/ai.storyteller.deckcraft.xml
    mkdir -p $out/share/icons
    cp -R assets/app-icon/hicolor $out/share/icons/
  '';

  postFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    patchelf --add-rpath ${lib.makeLibraryPath runtimeDeps} $out/bin/deckcraft
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Presentation app with PPTX support";
    homepage = "https://github.com/storytold/deckcraft";
    changelog = "https://github.com/storytold/deckcraft/releases/tag/${finalAttrs.src.tag}";
    license = lib.licenses.OR [
      lib.licenses.mit
      lib.licenses.asl20
    ];
    maintainers = with lib.maintainers; [ sophronesis ];
    mainProgram = "deckcraft";
    platforms = rustc.meta.platforms;
  };
})
