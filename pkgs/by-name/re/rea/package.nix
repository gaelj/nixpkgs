{
  lib,
  buildNpmPackage,
  fetchzip,
  nix-update-script,
  versionCheckHook,
}:
buildNpmPackage (finalAttrs: {
  __structuredAttrs = true;

  pname = "rea";
  version = "6.7.0";

  src = fetchzip {
    url = "https://registry.npmjs.org/rea-agents/-/rea-agents-${finalAttrs.version}.tgz";
    hash = "sha256-ndbkugbnjnJHuGK/WsSShghBEfH7ZPPZHG6mitdcsC8=";
  };

  npmDepsHash = "sha256-BWMsF0ja+AyQg3w7BKVjzbI372HOKd2bFpFwbCAB5cA=";

  postPatch = ''
    # The npm tarball ships no lock file; vendor the one from the release tag.
    cp ${./package-lock.json} package-lock.json
  '';

  # The tarball ships a prebuilt dist/.
  dontNpmBuild = true;

  # No runtime dependency needs install scripts (@lydell/node-pty ships
  # prebuilds); skip them everywhere, including `npm rebuild`.
  npmFlags = [ "--ignore-scripts" ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Reverse-engineer-anything (REA) MCP server and CLI for analyzing programs";
    homepage = "https://github.com/morluto/rea";
    downloadPage = "https://www.npmjs.com/package/rea-agents";
    changelog = "https://github.com/morluto/rea/releases";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ gaelj ];
    mainProgram = "rea";
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
  };
})
