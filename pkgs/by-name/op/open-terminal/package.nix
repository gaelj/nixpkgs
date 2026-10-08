{
  lib,
  python3Packages,
  fetchFromGitHub,
}:

python3Packages.buildPythonApplication (finalAttrs: {
  pname = "open-terminal";
  version = "0.14.0";
  pyproject = true;

  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "open-webui";
    repo = "open-terminal";
    rev = "v${finalAttrs.version}";
    hash = "sha256-hEwnaDS73EjFXzjOypj1nHv4akMa/egOpoRnm2UoKZc=";
  };

  build-system = with python3Packages; [
    hatchling
  ];

  dependencies = with python3Packages; [
    fastapi
    uvicorn
    # uvicorn[standard] extras from pyproject.toml
    httptools
    uvloop
    watchfiles
    websockets
    click
    httpx
    python-multipart
    aiofiles
    pypdf
    python-docx
    openpyxl
    python-pptx
    striprtf
    xlrd
    nbclient
    ipykernel
  ];

  # Matches [project.optional-dependencies] in pyproject.toml.
  # Not installed by default: pull in what you need via
  # open-terminal.optional-dependencies.<name> when overriding, e.g.:
  #   open-terminal.overridePythonAttrs (old: {
  #     dependencies = old.dependencies ++ open-terminal.optional-dependencies.mcp;
  #   })
  passthru.optional-dependencies = with python3Packages; {
    mcp = [ fastmcp ];
  };

  # No test suite in the upstream repository; skip to keep the build hermetic
  doCheck = false;

  pythonImportsCheck = [ "open_terminal" ];

  meta = with lib; {
    description = "A remote terminal API for Open WebUI";
    homepage = "https://github.com/open-webui/open-terminal";
    license = licenses.mit;
    mainProgram = "open-terminal";
    maintainers = with lib.maintainers; [ gaelj ];
  };
})
