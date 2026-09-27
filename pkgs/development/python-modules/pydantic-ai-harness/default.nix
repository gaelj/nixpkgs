{
  lib,
  buildPythonPackage,
  fetchurl,

  genai-prices,
  httpx,
  json-repair,
  pydantic-ai-slim,
}:

buildPythonPackage (finalAttrs: {
  pname = "pydantic-ai-harness";
  version = "0.36.0";
  format = "wheel";

  # Only a wheel is published for this package (no sdist on PyPI).
  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/de/07/b09528944d3897d6799f3a10a76d6bc59977d86200a61d0f042e2ee5e4ff/pydantic_ai_harness-0.36.0-py3-none-any.whl";
    sha256 = "sha256-JC352o0inK2v/pOnRE7ParGlJWf/uXfg77QLrFwEdmM=";
  };

  dependencies = [
    genai-prices
    httpx
    json-repair
    pydantic-ai-slim
  ];

  pythonImportsCheck = [ "pydantic_ai_harness" ];

  meta = {
    description = "The official capability library and harness for Pydantic AI";
    homepage = "https://github.com/pydantic/pydantic-ai-harness";
    changelog = "https://github.com/pydantic/pydantic-ai-harness/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    maintainers = [ ];
  };
})
