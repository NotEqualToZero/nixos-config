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
  # Vulkan-flavored llama-cpp. We build it explicitly with vulkanSupport ON and
  # rocmSupport/cudaSupport OFF. This is essential because this host sets a
  # global `nixpkgs.config.rocmSupport = true` (for the Incus/iGPU OpenCL
  # setup), which propagates into EVERY package build — including llama-cpp and
  # even its "vulkan" variant. A ROCm-enabled llama-server prefers the ROCm
  # backend, and on this Strix Point + 7900XTX box ROCm/HSA enumeration fails,
  # so it silently falls back to CPU. Forcing rocmSupport = false in the
  # override produces a clean Vulkan-only binary that actually uses the GPU,
  # regardless of the global config.
  llama-cpp-gpu = pkgs.llama-cpp.override {
    vulkanSupport = true;
    rocmSupport   = false;
    cudaSupport   = false;
  };
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
            "-c 98304"
            "-fa on"
            "--cache-type-k q8_0"
            "--cache-type-v q8_0"
            "--no-webui"
          ];
        };

        # ── Qwen3.6 35B-A3B (MoE, 3B active) — non-MTP build, single file ──
        # UD-Q4_K_M ≈ 20GB. MoE → fast despite 35B total. temp/top-p/top-k per Qwen.
        "qwen3.6-35b-a3b" = {
          cmd = lib.concatStringsSep " " [
            gpuEnv
            llama-server
            "--port \${PORT}"
            "--host 127.0.0.1"
            "-m ${hub}/models--unsloth--Qwen3.6-35B-A3B-GGUF/snapshots/a483e9e6cbd595906af30beda3187c2663a1118c/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf"
            "-ngl 99"
            "-c 49152"
            "-fa on"
            "--cache-type-k q8_0"
            "--cache-type-v q8_0"
            "--temp 1.0"
            "--top-p 0.95"
            "--top-k 20"
            "--jinja"
            "--no-webui"
          ];
        };

        # ── Gemma-4 12B coder (fable5 composer fine-tune) ──
        # Using Q8_0 (~13GB, near-lossless) — a 12B fits the 24GB card with room to
        # spare, so no reason to use the lower quants (Q6_K/Q4_K_M/Q3_K_M/Q2_K also
        # cached if you want a smaller footprint). Gemma sampling: 1.0 / 0.95 / 64.
        "gemma4-12b-coder" = {
          cmd = lib.concatStringsSep " " [
            gpuEnv
            llama-server
            "--port \${PORT}"
            "--host 127.0.0.1"
            "-m ${hub}/models--yuxinlu1--gemma-4-12B-coder-fable5-composer2.5-v1-GGUF/snapshots/1380be1796e559fca96b4107599285cab3ddbb92/gemma4-coding-Q8_0.gguf"
            "-ngl 99"
            "-c 65536"
            "-fa on"
            "--cache-type-k q8_0"
            "--cache-type-v q8_0"
            "--temp 1.0"
            "--top-p 0.95"
            "--top-k 64"
            "--jinja"
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

    # GPU device access. NOTE: `DeviceAllow=/dev/dri rw` (a directory path) does
    # NOT grant access to the character devices inside it (renderD128, card1) —
    # systemd needs device-class or specific-node rules. `char-drm` covers all
    # DRM render/card nodes; /dev/kfd is the ROCm/KFD compute node. Without
    # this, the GPU is invisible to the service even though file permissions
    # and groups are correct, and llama-server silently falls back to CPU.
    PrivateDevices = lib.mkForce false;
    DeviceAllow = lib.mkForce [
      "char-drm rw"      # all /dev/dri/renderD* and card* nodes
      "/dev/kfd rw"      # AMD KFD compute node
    ];
    SupplementaryGroups = [ "render" "video" ];

    # The native module restricts filesystem access; allow reading the models.
    ReadOnlyPaths = [ "/tank/Models/Odysseus" ];

    # --- GPU/Vulkan compatibility ---
    # The ONLY thing the native module's hardening got wrong for GPU use was the
    # device cgroup (fixed by char-drm above) and hiding /proc (fixed above).
    # RADV works fine under the rest of the native hardening — confirmed by a
    # systemd-run test with full defaults + only the device fix. So we keep the
    # native module's MemoryDenyWriteExecute, RestrictNamespaces, ProtectKernel*,
    # etc. and don't weaken them. The one extra: MemoryDenyWriteExecute can block
    # RADV's shader JIT on some driver versions, so leave it relaxed as a
    # belt-and-braces measure (cheap, and shader compilation genuinely needs W^X
    # exceptions on some stacks).
    MemoryDenyWriteExecute = lib.mkForce false;
    # The native module sets PrivateUsers=yes, which remaps UIDs so the
    # render/video supplementary groups don't apply to the GPU device nodes.
    # Turn it off so group-based device access works.
    PrivateUsers = lib.mkForce false;
  };

  # GPU selection env for the llama-swap service.
  systemd.services.llama-swap.environment = {
    VK_ICD_FILENAMES =
      "/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json";
    MESA_VK_DEVICE_SELECT = "1002:744c";
  };
}
