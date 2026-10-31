{
  lib,
  rustPlatform,
  fetchFromGitHub,
  installShellFiles,
  nix-update-script,
  versionCheckHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "red-table";
  version = "0.7.0";
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "volker-schukai";
    repo = "red-table";
    tag = finalAttrs.version;
    hash = "sha256-uF2TGxn3vgF/o9qjLZIK+KPpRb918TxD7ubMc96s0qU=";
  };

  cargoHash = "sha256-ToWb6e/5S6bum/3NOS0PAT4vYDD4qGOFgVQ0NlcFyUY=";

  nativeBuildInputs = [ installShellFiles ];

  postPatch = ''
    # Atomic::fetch_update was renamed to try_update; upstream still uses the old
    # name, which our toolchain reports as a deprecated-method warning.
    substituteInPlace source/kitty.rs \
      --replace-fail ".fetch_update(Ordering::Relaxed, Ordering::Relaxed," \
      ".try_update(Ordering::Relaxed, Ordering::Relaxed,"
  '';

  postInstall = ''
    # `red-table shell-init <shell>` emits a self-registering completion
    # snippet. The zsh one defines _red_table_complete and compdefs it inline;
    # as a site-functions file it needs a #compdef modeline and a first-call
    # dispatch so the very first TAB also completes.
    $out/bin/red-table shell-init bash > red-table.bash
    $out/bin/red-table shell-init fish > red-table.fish
    {
      echo "#compdef red-table"
      $out/bin/red-table shell-init zsh
      echo '_red_table_complete "$@"'
    } > _red-table

    installShellCompletion \
      --bash --name red-table red-table.bash \
      --fish red-table.fish \
      --zsh _red-table
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  cargoTestFlags = [
    "--"
    "--skip=bash_and_fish_alt_i_bindings_insert_into_the_real_command_buffer"
    "--skip=bash_and_fish_complete_options_values_and_shell_names"
    "--skip=shells_resolve_the_fixture_picker_without_host_startup_overrides"
    "--skip=widgets_preserve_the_buffer_on_cancel_failure_empty_results_and_unfinished_quotes"
    "--skip=widgets_quote_arbitrary_filename_bytes_without_executing_them"
    "--skip=zsh_completion_and_alt_i_work_in_the_real_line_editor"
  ];

  passthru.updateScript = nix-update-script { };

  meta = {
    mainProgram = "red-table";
    description = ''
      Fast keyboard-driven terminal image browser for browsing,
      comparing, and selecting large image collections
    '';
    longDescription = ''
      red-table is a performance-first terminal image browser for large image collections.
      It provides a searchable, scrollable thumbnail grid controlled entirely from the keyboard,
      including arrow keys and Vim-style h, j, k, and l navigation.
    '';
    homepage = "https://github.com/volker-schukai/red-table";
    downloadPage = "https://github.com/volker-schukai/red-table/releases/tag/${finalAttrs.src.tag}";
    changelog = "https://github.com/volker-schukai/red-table/commits/${finalAttrs.src.tag}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    identifiers = {
      cpeParts = lib.meta.cpeFullVersionWithVendor "volker-schukai" finalAttrs.version;
      purlParts = {
        type = "github";
        namespace = "volker-schukai";
        name = "red-table";
        version = finalAttrs.version;
      };
    };
    platforms = lib.platforms.all;
    maintainers = with lib.maintainers; [ KristijanZic ];
  };
})
