# This file was generated by pkgs.mastodon.updateScript.
{ fetchFromGitHub, applyPatches }: let
  src = fetchFromGitHub {
    owner = "mastodon";
    repo = "mastodon";
    rev = "v4.1.10";
    sha256 = "22AhrI4wk/FhVJeRfhiI10MeYOJFoS0dwg3fWuWltoM=";
  };
in applyPatches {
  inherit src;
  patches = [];
}
