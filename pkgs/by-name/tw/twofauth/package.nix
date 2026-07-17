{
  lib,
  fetchFromGitHub,
  php' ? php84,
  php84,
  nix-update-script,
  dataDir ? "/var/lib/2fauth",
}:

let
  # Build a PHP with only the extensions 2FAuth needs that aren't already
  # compiled in. The following are built-in and must NOT be listed here:
  # ctype, dom, json, openssl, tokenizer (and others enabled by default).
  php = php'.withExtensions (
    { enabled, all }:
    enabled
    ++ (with all; [
      bcmath
      fileinfo
      gd
      mbstring
      pdo
      pdo_sqlite
    ])
  );

in
php.buildComposerProject2 (finalAttrs: {
  pname = "2fauth";
  version = "8.0.1";
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "Bubka";
    repo = "2FAuth" ;
    tag = "v${finalAttrs.version}";
    hash = "sha256-ssvmiYcLrSCk5xXKnFl5osVVC+KFzwlaTIo9RMNbBwA=";
  };

  vendorHash = "sha256-MUWWjNXZWXb5Pfjf6RKnFd2QlphBDMmlXzrfI69RORs=";

  composerNoDev = true;
  composerNoPlugins = true;
  composerNoScripts = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/2fauth
    cp -r . $out/share/2fauth/

    # Symlink writable paths into dataDir at build time.
    # The NixOS module creates these in stateDir before the service starts.
    # This avoids any bind-mounting — Laravel follows the symlinks directly.
    rm -rf $out/share/2fauth/storage
    ln -s ${dataDir}/storage       $out/share/2fauth/storage
    ln -s ${dataDir}/.env          $out/share/2fauth/.env

    # bootstrap/cache is handled via APP_*_CACHE env vars (see module),
    # but keep an empty dir as a fallback so Laravel doesn't complain.
    mkdir -p $out/share/2fauth/bootstrap/cache

    chmod +x $out/share/2fauth/artisan

    mkdir -p $out/bin
    cat > $out/bin/2fauth-artisan << 'EOF'
    #!/bin/sh
    exec ${lib.getExe php} ${placeholder "out"}/share/2fauth/artisan "$@"
    EOF
    chmod +x $out/bin/2fauth-artisan

    runHook postInstall
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "A web app to manage Two-Factor Authentication (2FA) accounts and generate their security codes";
    longDescription = ''
      2FAuth is a self-hosted web app that manages your TOTP/HOTP two-factor
      authentication accounts and generates their security codes. It is a
      lightweight alternative to authenticator apps running on mobile devices.
    '';
    homepage = "https://2fauth.app/";
    changelog = "https://github.com/Bubka/2FAuth/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.agpl3Only;
    maintainers = with lib.maintainers; [ gaelj ];
    platforms = lib.platforms.linux;
  };
})
