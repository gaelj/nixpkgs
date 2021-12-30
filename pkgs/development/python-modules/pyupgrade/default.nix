{ lib
, buildPythonPackage
, fetchFromGitHub
, pythonOlder
, pytestCheckHook
, tokenize-rt
}:

buildPythonPackage rec {
  pname = "pyupgrade";
  version = "2.30.0";
  format = "setuptools";

  disabled = pythonOlder "3.6";

  src = fetchFromGitHub {
    owner = "asottile";
    repo = pname;
    rev = "v${version}";
    sha256 = "sha256-Fku95ar5i+QV21GhomO6/ivlJcnOhPyximyPsh2/dc0=";
  };

  checkInputs = [
    pytestCheckHook
  ];

  propagatedBuildInputs = [
    tokenize-rt
  ];

  pythonImportsCheck = [
    "pyupgrade"
  ];

  meta = with lib; {
    description = "Tool to automatically upgrade syntax for newer versions of the language";
    homepage = "https://github.com/asottile/pyupgrade";
    license = licenses.mit;
    maintainers = with maintainers; [ lovesegfault ];
  };
}
