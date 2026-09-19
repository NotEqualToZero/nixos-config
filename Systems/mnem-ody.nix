{ config, lib, pkgs, sources, ... }:

{
  imports =
    [
      (import sources.ody-nix-dev).nixosModules.default
      #../modules/llama-swap-config.nix
      ../modules/dwarfstar/module.nix
    ];
  services.odysseus = {
    enable = true;
    host = "0.0.0.0";
    dataDir = "/tank/Models/Odysseus";
    group = "collab";
    #envFile = "/etc/odysseus/env";  # your API keys / secrets
    extraEnv = {
    };
    optionalDeps.duckduckgo = true;

    backendPackages = [
      (pkgs.llama-cpp.override { vulkanSupport = true; })
    ];
    extraLibPaths = [ "/run/opengl-driver/lib" ];

    extraEnv = {
      # Pin RADV to the 7900 XTX by PCI ID (robust on mixed iGPU+dGPU)
      MESA_VK_DEVICE_SELECT = "1002:744c";
      SEARXNG_INSTANCE = "http://localhost:8080";
      # Use only the AMD RADV ICD; skip freedreno/Turnip/panfrost/llvmpipe
      VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json";
      HSA_OVERRIDE_GFX_VERSION = "11.0.0";
      VLLM_LOGGING_LEVEL="DEBUG";
    };
  };


  # Grant the odysseus service user access to the GPU render nodes.

  # Expose /dev/dri and /dev/kfd to the service.
  #  systemd.services.odysseus.serviceConfig = {
  #    PrivateDevices      = false;
  #    DeviceAllow         = [ "/dev/dri rw" "/dev/kfd rw" ];
  #    SupplementaryGroups = [ "render" "video" ];
  #  };

  services.ds4 = {
    enable = false;
    src    = sources.ds4;
    gpuArch = "gfx1150";          # confirmed from gfx_target_version 110500

    # CRITICAL: this box has BOTH the 7900XTX (gfx1100, 24GB) and the 890M iGPU
    # (gfx1151). ds4 defaults to ROCm device 0 = the 7900XTX and OOMs on the
    # 81GB model (24GB VRAM). Pin ds4 to the iGPU's index so it uses the 88GB
    # GTT aperture. Find the index with:
    #   for i in 0 1 2; do echo "dev $i:"; \
    #     HIP_VISIBLE_DEVICES=$i rocminfo 2>/dev/null | grep -E "Marketing|gfx" | head -2; done
    # The gfx1151 / Radeon 890M index goes here (likely 1):
    gpuDeviceIndex = 1;           # <-- VERIFY: must be the 890M, not the 7900XTX

    # USER/GROUP: by default ds4 borrows the Odysseus service's user/group so it
    # shares the model dirs + GPU group membership. You changed the Odysseus
    # group to "collab" ON THE SERVER. Two ways to make ds4 match:
    #   (a) If you set the group in the Odysseus *config* too, e.g.
    #         services.odysseus.group = "collab";
    #       then ds4's default picks it up automatically — nothing to do here.
    #   (b) Otherwise pin it explicitly on ds4:
    #         group = "collab";
    # The user likely stayed "odysseus"; if you also renamed it, set user too.
    # group = "collab";   # uncomment if Odysseus's group isn't set in config

    # Only set if ROCm reports missing rocBLAS kernels for the iGPU. gfx1151
    # is natively supported in recent ROCm, so likely leave unset.
    # hsaGfxOverride = "11.5.1";

    # The EXACT GGUF STRIXHALO.md recommends. AVOID mixed IQ2/IQ4 GGUFs — the
    # doc warns they cause system OOM on this machine rather than clean failure.
    model = "/mnt/ds4-kv/models/DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix.gguf";

    listenAddress = "127.0.0.1";
    port          = 8030;
    # 88GB available − 80.76GB model ≈ 7GB for live KV + buffers. Keep ctx
    # modest and lean on the Optane disk KV cache. Start at 64k; raise only
    # after measuring free mem with the model loaded.
    # SSD streaming: the 81GB model + arena overhead won't fit fully-resident in
    # 93GB (it OOMs at ~84GB allocation with no headroom). Streaming keeps the
    # non-routed weights resident and pages routed MoE experts from the GGUF on
    # cache misses — designed for "model larger than usable RAM". Slower
    # generation, but it runs. Verify the ROCm build accepts --ssd-streaming
    # first (docs frame it as Metal); test manually before relying on it.
    ssdStreaming = true;
    # Leave the expert-cache budget automatic first. Set explicitly only if the
    # startup cache report says the auto budget is too large:
    # ssdStreamingCacheExperts = "48GB";

    contextSize = 32768;

    kvDiskDir     = "/mnt/ds4-kv";
    kvDiskSpaceMb = 65536;

    # Optional MTP speculative decoding (download the mtp gguf, then):
    # extraArgs = [ "--mtp" "/tank/Models/ds4/mtp.gguf" "--mtp-draft" "2" ];
  };


  users.groups.collab = {};
  users.users.odysseus.extraGroups = [ "collab" ];

  fileSystems."/home/cale/Projects/odysseus-workspace" = { # bind to home so i can work on AI projects
    device = "/tank/Models/Odysseus/Projects";
    fsType = "none";
    options = [
      "bind"
      "x-systemd.requires=tank-Models-Odysseus-Projects.mount"
      "x-systemd.after=tank-Models-Odysseus-Projects.mount"
    ];
  };

  services.searx = {
    enable = true;
    configureUwsgi = false;
    redisCreateLocally = true;
    environmentFile = config.sops.secrets.searxng-key.path;

    settings = {
      general = {
        # secret_key does NOT belong here.
      };
      server = {
        bind_address = "127.0.0.1";
        port = 8080;
        secret_key = "__SEARXNG_SECRET__";   # placeholder, substituted at runtime
      };
      search = {
        safe_search = 0;
        languages = [ "auto" ];
        formats = [ "json" ];
      };
    };
  };

  boot.kernelParams = [
    "amd_iommu=off"
    "amdgpu.gttsize=90112"          # 88 GB aperture ceiling
    "ttm.pages_limit=22544384"      # 86 GB max allocation (covers the 81GB model)
    "ttm.page_pool_size=1048576"    # 4 GB recycling pool (was 124GB — the OOM cause)
 ];

  nixpkgs.config.rocmSupport = true;
  # hardware.amdgpu.opencl.enable = true;

  boot.extraModprobeConfig = ''
    options amdgpu sriov_vf_count=1
    options amdgpu runpm=0
    '';

}
