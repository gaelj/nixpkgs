{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  nix-update-script,
}:

# Distributed on PyPI as "crontab"; not to be confused with python-crontab,
# which is packaged as python3Packages.crontab and installs a module with the
# same name.
buildPythonPackage (finalAttrs: {
  pname = "crontab";
  version = "1.0.5";
  pyproject = true;

  src = fetchPypi {
    inherit (finalAttrs) pname version;
    hash = "sha256-+A4BtPByGXY6mGn5Jt0XFHJ455ZakoCJvKbT3ICuRtU=";
  };

  build-system = [ setuptools ];

  # sdist does not ship tests
  doCheck = false;

  pythonImportsCheck = [ "crontab" ];

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Parse crontab schedules and compute execution times";
    homepage = "https://github.com/josiahcarlson/parse-crontab";
    license = with lib.licenses; [
      lgpl21Only
      lgpl3Only
    ];
    maintainers = with lib.maintainers; [ denzonl ];
  };
})
