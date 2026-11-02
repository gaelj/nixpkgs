{
  lib,
  stdenv,
  cudaPackages,
  fetchFromGitHub,
  autoAddDriverRunpath,
  cmake,
  ninja,
  pkg-config,
  openssl,
  rocmPackages,
  vulkan-headers,
  vulkan-loader,
  glslang,
  shaderc,
  config,
  cudaSupport ? config.cudaSupport or false,
  rocmSupport ? config.rocmSupport or false,
  vulkanSupport ? false,
  metalSupport ? stdenv.hostPlatform.isDarwin,
  rocmGpuTargets ? rocmPackages.clr.gpuTargets,
  nativeModelManagerSupport ? true,
  # Which model families to build; an empty list builds the "full" set.
  # Maps to the AUDIOCPP_MODEL_SET/AUDIOCPP_MODELS cache variables.
  models ? [ ],
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "audio-cpp";
  version = "0.9.4";

  src = fetchFromGitHub {
    owner = "0xShug0";
    repo = "audio.cpp";
    rev = "v${finalAttrs.version}";
    hash = "sha256-ilg+3M7iDG2/Cd+Xbted01VIZgT6KbWmy5KfqYYEjAQ=";
  };

  # CUDA builds need a host GCC within the toolkit's supported range.
  stdenv = if cudaSupport then cudaPackages.backendStdenv else stdenv;

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
  ]
  ++ lib.optionals cudaSupport [
    cudaPackages.cuda_nvcc
    autoAddDriverRunpath
  ]
  ++ lib.optionals rocmSupport [ rocmPackages.clr ];

  buildInputs =
    lib.optionals nativeModelManagerSupport [ openssl ]
    ++ lib.optionals vulkanSupport [
      vulkan-headers
      vulkan-loader
      glslang
      shaderc
    ]
    ++ lib.optionals cudaSupport [ cudaPackages.cudatoolkit ]
    ++ lib.optionals rocmSupport [
      rocmPackages.clr
      rocmPackages.hipblas
      rocmPackages.rocblas
    ];

  cmakeFlags = [
    (lib.cmakeBool "ENGINE_ENABLE_NATIVE_CPU" false) # -march=native would make builds non-deterministic
    (lib.cmakeBool "ENGINE_ENABLE_LLAMAFILE" true)
    (lib.cmakeBool "AUDIOCPP_BUILD_NATIVE_MODEL_MANAGER" nativeModelManagerSupport)
    (lib.cmakeBool "AUDIOCPP_USE_SYSTEM_OPENSSL" nativeModelManagerSupport)
    (lib.cmakeBool "ENGINE_ENABLE_OPENMP" (!stdenv.hostPlatform.isDarwin))
    (lib.cmakeBool "ENGINE_ENABLE_VULKAN" vulkanSupport)
    (lib.cmakeBool "ENGINE_ENABLE_CUDA" cudaSupport)
    (lib.cmakeBool "ENGINE_ENABLE_METAL" metalSupport)
    (lib.cmakeFeature "AUDIOCPP_MODEL_SET" (if models == [ ] then "full" else "custom"))
  ]
  ++ lib.optionals (models != [ ]) [
    (lib.cmakeFeature "AUDIOCPP_MODELS" (lib.concatStringsSep "," models))
  ]
  ++ lib.optionals cudaSupport [
    (lib.cmakeFeature "CMAKE_CUDA_ARCHITECTURES" cudaPackages.flags.cmakeCudaArchitecturesString)
  ]
  ++ lib.optionals rocmSupport [
    (lib.cmakeFeature "CMAKE_HIP_COMPILER" "${rocmPackages.llvm.clang}/bin/clang")
    (lib.cmakeFeature "GPU_TARGETS" (lib.concatStringsSep ";" rocmGpuTargets))
    (lib.cmakeBool "ENGINE_HIP_STRIX_HALO_OPTIMIZATIONS" (rocmGpuTargets == [ "gfx1151" ]))
  ];

  env = lib.optionalAttrs rocmSupport {
    ROCM_PATH = "${rocmPackages.clr}";
  };

  # The build writes its executables to bin/ inside the build directory.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    install -m755 bin/audiocpp_cli bin/audiocpp_server bin/audiocpp_gguf $out/bin/
    ${lib.optionalString nativeModelManagerSupport "install -m755 bin/audiocpp_model_manager $out/bin/"}

    # The server walks up from the executable's directory looking for a
    # model_specs/ dir (see find_repository_root in app/server), so install it
    # next to bin/ like upstream does. Specs live in the source tree, not the
    # CMake build dir.
    cp -R $src/model_specs $out/model_specs

    runHook postInstall
  '';

  meta = {
    description = "High-performance C++ audio inference framework built on ggml";
    homepage = "https://github.com/0xShug0/audio.cpp";
    changelog = "https://github.com/0xShug0/audio.cpp/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "audiocpp_cli";
    platforms = lib.platforms.unix;
    badPlatforms = lib.optionals (cudaSupport || rocmSupport) lib.platforms.darwin;
    # audio.cpp requires GCC >= 13 (or an equivalent C++20-capable compiler)
    broken = stdenv.hostPlatform.isLinux && stdenv.cc.isGNU && lib.versionOlder stdenv.cc.version "13";
    maintainers = with lib.maintainers; [
      gaelj
    ];
  };
})
