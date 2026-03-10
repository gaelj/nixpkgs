{
  lib,
  python3Packages,
  fetchPypi,
  fetchFromGitHub,
  buildPythonApplication,
  setuptools,
  requests,
}:

buildPythonApplication rec {
  pname = "creditagricole_particuliers";
  version = "0.14.3";
  pyproject = true;
  #format = "setuptools";

  src = fetchFromGitHub {
    owner = "dmachard";
    repo = "python-creditagricole-particuliers";
    tag = "v${version}";
    hash = "sha256-oRODRxcWLvPPSO/2j0A/na+GoWieqVmLcvWUlBGMpyw=";
  };

  #build-system = with python3Packages; [ hatchling ];

  buildInputs = with python3Packages; [ jinja2 ];

  # Render the setup.py from setup.j2 during the build phase
  buildPhase = ''
python -c '
import jinja2

# Read the setup.j2 file
with open("setup.j2", "r") as template_file:
    template = jinja2.Template(template_file.read())

# Render the template
rendered = template.render(version="${version}")

# Write the rendered setup.py
with open("setup.py", "w") as setup_file:
    setup_file.write(rendered)

'
#mkdir dist
'';


  #src = fetchPypi {
  #  inherit pname version;
  #  hash = "sha256-fU2WyUrC7mfPcNuSs1y4guEeCVZilRidvgxwNFkivP4=";
  #};

  dependencies = [
    requests
  ];

  nativeBuildInputs = [
    #setuptools
  ];

  propagatedBuildInputs = [
    requests
    #wheel # Ensure wheel is available
    setuptools
  ];

  # Tests require a HTTP connection to ollama
  doCheck = false;

  meta = {
    description = "Ce client Python est à destination des particuliers souhaitant récupérer ses opérations bancaires stockées par le Crédit Agricole";
    homepage = "https://github.com/dmachard/python-creditagricole-particuliers";
    changelog = "https://github.com/dmachard/python-creditagricole-particuliers/releases/tag/${version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ gaelj ];
    mainProgram = "creditagricole_particuliers";
  };
}
