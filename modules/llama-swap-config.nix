# ── Declarative GPU llama.cpp serving via the native services.llama-swap ──
#
# Add this to your configuration.nix. It runs llama-swap on port 8020 with the
# Vulkan-accelerated llama-cpp pinned to the 7900XTX, serving multiple
# switchable models. Odysseus connects to it as an external endpoint:
#     http://127.0.0.1:8020/v1
#
# No imports needed — services.llama-swap is built into nixpkgs.

{ config, pkgs, lib, ... }:

let
  # Vulkan-flavored llama-cpp (sidesteps the ROCm/HSA iGPU enumeration issue).
  # Prefer the dedicated `llama-cpp-vulkan` attribute when the pinned nixpkgs
  # provides it (most do); fall back to overriding the base package. Using the
  # named attribute is more robust across pkgs sets (e.g. colmena/npins-pinned
  # nixpkgs) where a bare `.override { vulkanSupport = true; }` can evaluate to
  # the plain CPU build.
  llama-cpp-gpu =
    if pkgs ? llama-cpp-vulkan
    then pkgs.llama-cpp-vulkan
    else pkgs.llama-cpp.override { vulkanSupport = true; };
  llama-server  = lib.getExe' llama-cpp-gpu "llama-server";

  # GPU env baked directly into each model command. Relying on the systemd
  # service `environment` alone proved unreliable — the spawned llama-server
  # didn't inherit it and fell back to CPU. Prefixing the command with `env`
  # guarantees RADV + the 7900XTX are selected for every model process.
  gpuEnv = lib.concatStringsSep " " [
    "${pkgs.coreutils}/bin/env"
    "VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json"
    "MESA_VK_DEVICE_SELECT=1002:744c"
  ];

  # Your model files. Adjust paths/names to taste — these names are what
  # appear in Odysseus's model picker once the endpoint is added.
  hub = "/tank/Models/Odysseus/.cache/huggingface/hub";
in
{
  services.llama-swap = {
    enable        = true;
    listenAddress = "127.0.0.1";
    port          = 8020;

    settings = {
      healthCheckTimeout = 300;   # large models on first load can take a while

      models = {
        "qwen3-0.8b" = {
          cmd = lib.concatStringsSep " " [
            gpuEnv
            llama-server
            "--port \${PORT}"
            "--host 127.0.0.1"
            "-m ${hub}/models--unsloth--Qwen3.5-0.8B-GGUF/snapshots/6ab461498e2023f6e3c1baea90a8f0fe38ab64d0/Qwen3.5-0.8B-Q4_K_M.gguf"
            "-ngl 99"
            "-c 8192"
            "--no-webui"
          ];
        };

        "qwen3-27b" = {
          cmd = lib.concatStringsSep " " [
            gpuEnv
            llama-server
            "--port \${PORT}"
            "--host 127.0.0.1"
            "-m ${hub}/models--unsloth--Qwen3.6-27B-GGUF/snapshots/82d411acf4a06cfb8d9b073a5211bf410bfc29bf/Qwen3.6-27B-Q4_K_M.gguf"
            "-ngl 99"
            "-c 20000"
            "--no-webui"
          ];
        };
      };
    };
  };

  # Run llama-swap as the odysseus user/group so it can read the model files
  # under /tank/Models/Odysseus (owned by odysseus), and reuse the render/video
  # group membership the odysseus user already has for GPU access.
  systemd.services.llama-swap.serviceConfig = {
    User  = lib.mkForce "odysseus";
    Group = lib.mkForce "odysseus";

    # The native module hides /proc (ProcSubset=pid / ProtectProc), which
    # breaks llama-swap's sys-stats read AND the spawned llama-server's init
    # (it reads /proc/meminfo, /proc/cpuinfo). Relax it.
    ProcSubset  = lib.mkForce "all";
    ProtectProc = lib.mkForce "default";

    # GPU device access (the native hardening doesn't grant these).
    PrivateDevices      = lib.mkForce false;
    DeviceAllow         = [ "/dev/dri rw" "/dev/kfd rw" ];
    SupplementaryGroups = [ "render" "video" ];

    # The native module restricts filesystem access; allow reading the models.
    ReadOnlyPaths = [ "/tank/Models/Odysseus" ];
  };

  # GPU selection env for the llama-swap service.
  systemd.services.llama-swap.environment = {
    VK_ICD_FILENAMES =
      "/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json";
    MESA_VK_DEVICE_SELECT = "1002:744c";
  };
}
