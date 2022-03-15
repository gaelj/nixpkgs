{  buildGoPackage, fetchFromGitHub, lib  }:

with lib;

buildGoPackage rec {
  pname   = "nats-server";
  version = "2.6.0";

  goPackagePath = "github.com/nats-io/${pname}";

  src = fetchFromGitHub {
    rev    = "v${version}";
    owner  = "nats-io";
    repo   = pname;
    sha256 = "sha256-DggzXYPyu0dQ40L98VzxgN9S/35vLJJow9UjDtMz9rY=";
  };

  patches = [
    ./2.6.0-CVE-2022-24450.patch
    ./2.6.0-CVE-2022-26652.patch
  ];

  meta = {
    description = "High-Performance server for NATS";
    license = licenses.asl20;
    maintainers = [ maintainers.swdunlop ];
    homepage = "https://nats.io/";
  };
}
