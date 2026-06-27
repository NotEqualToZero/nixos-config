# ds4 (DwarfStar 4) — DeepSeek V4 Flash inference engine, Strix Halo ROCm build.
#
# Follows the project's STRIXHALO.md: target `make strix-halo`, ROCm/HIP deps.
# Plain C99 + a HIP backend; does NOT link GGML. Produces ds4 (cli) and
# ds4-server (the OpenAI/Anthropic HTTP server Odysseus talks to).
#
# Header discovery: the Makefile compiles ds4_rocm.cu with
#   $(HIPCC) $(ROCM_CFLAGS) -c -o ds4_rocm.o ds4_rocm.cu
# and ROCM_CFLAGS is defined with `?=` (override-able). The HIP compiler does
# not auto-find the separate rocmPackages header dirs, so we append -I flags to
# ROCM_CFLAGS (and the linker libs path) via the make invocation.

{ lib
, stdenv
, src
, rocmPackages
, makeWrapper
, gpuArch ? "gfx1150"
}:

let
  rocmDeps = with rocmPackages; [
    clr
    rocblas
    hipblas
    hipblas-common
    hipblaslt
    rocwmma
    hipcub
    rocprim
    rocm-runtime
    rocm-device-libs
    rocminfo
    rocm-smi
  ];

  # -I flags for every ROCm header dir (no separate dev outputs in this nixpkgs).
  includeFlags = lib.concatMapStringsSep " " (p: "-I${p}/include") rocmDeps;
  # -L flags so the linker finds libhipblas / libhipblaslt etc.
  libFlags = lib.concatMapStringsSep " " (p: "-L${p}/lib") rocmDeps;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "ds4";
  version = "main-" + (builtins.substring 0 7 (src.rev or "unknown"));

  inherit src;

  nativeBuildInputs = [
    rocmPackages.clr
    makeWrapper
  ];

  buildInputs = rocmDeps;

  ROCM_PATH = "${rocmPackages.clr}";
  HIP_PATH  = "${rocmPackages.clr}";
  AMDGPU_TARGETS = gpuArch;

  buildPhase = ''
    runHook preBuild

    # The Makefile's ROCM_CFLAGS / ROCM_LDLIBS use ?= so we can override them.
    # Append our include paths to ROCM_CFLAGS (fixes 'hipblas/hipblas.h not
    # found') and library search paths to the link libs. Keep the Makefile's
    # own default flags by re-stating them plus our additions.
    BASE_ROCM_CFLAGS="-O3 -ffast-math -g -fno-finite-math-only -pthread -D__HIP_PLATFORM_AMD__ -Wno-unused-command-line-argument --offload-arch=${gpuArch}"

    make strix-halo -j$NIX_BUILD_CORES \
      ROCM_ARCH=${gpuArch} \
      ROCM_CFLAGS="$BASE_ROCM_CFLAGS ${includeFlags}" \
      ROCM_LDLIBS="${libFlags} -lm -pthread -lhipblas -lhipblaslt"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    for b in ds4 ds4-server ds4-cli ds4-agent ds4-bench ds4-eval ds4_test; do
      if [ -f "$b" ]; then
        install -Dm755 "$b" "$out/bin/$b"
      fi
    done

    if [ ! -f "$out/bin/ds4-server" ]; then
      echo "ERROR: ds4-server was not produced by the build." >&2
      echo "Binaries found in build dir:" >&2; ls -la >&2
      exit 1
    fi

    for b in ds4 ds4-server ds4-cli ds4-agent; do
      if [ -f "$out/bin/$b" ]; then
        wrapProgram "$out/bin/$b" \
          --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath rocmDeps}" \
          --set-default ROCM_PATH "${rocmPackages.clr}"
      fi
    done

    runHook postInstall
  '';

  passthru = { inherit gpuArch; };

  meta = with lib; {
    description = "DwarfStar 4 — DeepSeek V4 Flash inference engine (Strix Halo ROCm build)";
    homepage = "https://github.com/antirez/ds4";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "ds4-server";
  };
})
