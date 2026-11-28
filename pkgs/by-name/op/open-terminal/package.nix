{
  lib,
  python3Packages,
  fetchFromGitHub,
  nix-update-script,
}:

python3Packages.buildPythonApplication (finalAttrs: {
  pname = "open-terminal";
  version = "0.18.8";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "open-webui";
    repo = "open-terminal";
    tag = "v${finalAttrs.version}";
    hash = "sha256-/HTO4ZUmkToTBgCGdKI6KTQv4DlFpSAkyanLxDDYKtM=";
  };

  build-system = with python3Packages; [ hatchling ];

  dependencies =
    with python3Packages;
    [
      aiofiles
      click
      dbus-next # sys_platform == 'linux'
      fastapi
      httpx
      ipykernel
      mss
      nbclient
      openpyxl
      pillow
      pyautogui
      pypdf
      pyperclip
      python-docx
      python-multipart
      python-pptx
      striprtf
      uvicorn
      xlrd
    ]
    ++ uvicorn.optional-dependencies.standard;

  # nixpkgs ships pyautogui 0.9.53: the newer 0.9.54 was never tagged upstream,
  # only published as a PyPI sdist. Every pyautogui API used here (size, moveTo,
  # scroll/hscroll, click, keyDown/keyUp, mouseDown/mouseUp, hotkey,
  # KEYBOARD_KEYS, PAUSE, FAILSAFE) already exists in 0.9.53, so relax the bound
  # instead of disabling pythonRuntimeDepsCheck.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'pyautogui>=0.9.54' 'pyautogui>=0.9.53'
  '';

  # No python tests nor --version flag
  doCheck = false;

  pythonImportsCheck = [
    "open_terminal"
    "open_terminal.cli"
    "open_terminal.utils.notebooks"
  ];

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Self-hosted remote terminal API for AI agents, used by Open WebUI";
    homepage = "https://github.com/open-webui/open-terminal";
    changelog = "https://github.com/open-webui/open-terminal/blob/${finalAttrs.src.rev}/CHANGELOG.md";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [
      liberodark
      julm
    ];
    mainProgram = "open-terminal";
    platforms = lib.platforms.linux;
  };
})
