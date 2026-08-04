{
  stdenv,
  fetchFromGitHub,
  installShellFiles,
  lib,
  makeWrapper,
  rustPlatform,
  wget,
  libiconv,
  withFzf ? true,
  fzf,
  nix-update-script,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "navi";
  version = "2.24.0";

  src = fetchFromGitHub {
    owner = "denisidoro";
    repo = "navi";
    tag = "v${finalAttrs.version}";
    hash = "sha256-zvqxVu147u/m/4B3fhbuQ46txGMrlgQv9d4GGiR8SoQ=";
  };

  cargoHash = "sha256-tQCm8KMVWo6KiKVOMDitHtDXwYGM7INXcT+7fEEiIiI=";

  nativeBuildInputs = [
    installShellFiles
    makeWrapper
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isDarwin [ libiconv ];

  postInstall = ''
    wrapProgram $out/bin/navi \
      --prefix PATH : "$out/bin" \
      --prefix PATH : ${lib.makeBinPath ([ wget ] ++ lib.optionals withFzf [ fzf ])}
  ''
  + lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    installShellCompletion --cmd navi \
      --bash <($out/bin/navi widget bash) \
      --fish <($out/bin/navi widget fish) \
      --zsh <($out/bin/navi widget zsh)
  '';

  checkFlags = [
    # error: Found argument '--test-threads' which wasn't expected, or isn't valid in this context
    "--skip=test_parse_variable_line"
  ];

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Interactive cheatsheet tool for the command-line and application launchers";
    homepage = "https://github.com/denisidoro/navi";
    license = lib.licenses.asl20;
    platforms = lib.platforms.unix;
    mainProgram = "navi";
    maintainers = with lib.maintainers; [ cust0dian ];
  };
})
