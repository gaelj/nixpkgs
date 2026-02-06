# https://downloads.zohocdn.com/vault-cli-desktop/linux/zv_cli.zip

{
  lib,
  fetchurl,
  stdenv,
  unzip,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "zoho-vault-cli";
  version = "1.1.1";

  src = fetchurl {
    url = "https://downloads.zohocdn.com/vault-cli-desktop/linux/zv_cli.zip";
    hash = "sha256-Pdj+oM6tYHJRE3Zc9iYy8Xo7NFB2ut98OEZbZSyXvBo=";
  };

  nativeBuildInputs = [
    unzip
  ];

  dontConfigure = true;

  dontUnpack = true;

  buildCommand = ''
    mkdir -p $out/bin
    unzip $src zv
    mv zv $out/bin
  '';

  meta = {
    description = "CLI client for Zoho Vault";
    homepage = "https://www.zoho.com/vault/password-manager-application-download.html";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    maintainers = with lib.maintainers; [ gaelj ];
    mainProgram = "zv";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
