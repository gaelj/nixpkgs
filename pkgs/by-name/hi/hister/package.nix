{
  buildGoModule,
  fetchFromGitHub,
  lib,
  nix-update-script,
  installShellFiles,
}:

buildGoModule (finalAttrs: {
  pname = "hister";
  version = "0.3.0";

  src = fetchFromGitHub {
    owner = "asciimoo";
    repo = "hister";
    tag = "v${finalAttrs.version}";
    hash = "sha256-nGvesnSuWCsGjM0/Zp0tfZuP/V+EHLTOXKCHvjRrgSw=";
  };

  vendorHash = "sha256-3rAw9YMvDqh7aA1cft2NghfQ8jEiZdwykajJUwu7Zus=";

  nativeBuildInputs = [
    installShellFiles
  ];

  postInstall = ''
    installShellCompletion --cmd hister \
      --bash <($out/bin/hister completion bash) \
      --fish <($out/bin/hister completion fish) \
      --zsh <($out/bin/hister completion zsh)
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Blazing fast, content-based search for visited websites";
    mainProgram = "hister";
    homepage = "https://github.com/asciimoo/hister";
    changelog = "https://github.com/asciimoo/hister/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.agpl3Only;
    platforms = lib.platforms.all;
    maintainers = with lib.maintainers; [ gaelj ];
  };
})
