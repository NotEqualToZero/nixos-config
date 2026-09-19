# ──────────────────────────────────────────────────────────────────────────
# Mnemosyne wiring for ds4 — snippets to add to your existing config.
# Follows the project's STRIXHALO.md requirements.
# ──────────────────────────────────────────────────────────────────────────

# == 1. npins: pin the ds4 source (main branch — ROCm/Strix Halo is in main) ==
# On Hades2, in ~/nixos-config:
#   npins add github antirez ds4 --branch main
#   # to move it later: npins update ds4
# Reference as: (import ../npins).ds4


# == 2. Import the module in Systems/Mnemosyne.nix ==
#   imports = [
#     ../modules/llama-swap-config.nix
#     ../modules/ds4/module.nix
#     # ...
#   ];


# == 3. Service config + kernel params + ZFS (all in Mnemosyne.nix) ==
{ config, pkgs, lib, ... }:
let
  sources = import ../npins;
in
{
  # ---- 3a. CRITICAL: GTT aperture kernel params (STRIXHALO.md §3) ----
  # CORRECTED AGAIN after observing TTM swallow all 96GB of RAM:
  #
  # The killer was ttm.page_pool_size. TTM's page_pool is a PRE-RESERVED cache
  # of free pages for GPU use — setting it to the aperture size (124GB) makes
  # TTM grab ~all system RAM into a pool that shows as "used" but isn't in any
  # process/cache/slab (invisible memory), starving everything → OOM.
  #
  # Correct sizing for THIS 96GB box:
  #   amdgpu.gttsize=90112       → 88 GB aperture CEILING (a max, not a reservation; cheap)
  #   ttm.pages_limit=22544384   → 86 GB: max TTM may ALLOCATE (must cover the ~81GB model)
  #   ttm.page_pool_size=1048576 → 4 GB: the recycling pool — keep SMALL, this is what
  #                                 pre-reserves RAM. Do NOT set it to the aperture size.
  #
  # amd_iommu=off disables the IOMMU globally. You run Incus with iGPU OpenCL —
  # verify those containers still work after reboot; if they break, try iommu=pt.
  boot.kernelParams = [
    "amd_iommu=off"
    "amdgpu.gttsize=90112"          # 88 GB aperture ceiling
    "ttm.pages_limit=22544384"      # 86 GB max allocation (covers the 81GB model)
    "ttm.page_pool_size=1048576"    # 4 GB recycling pool (was 124GB — the OOM cause)
  ];
  # After deploy + REBOOT, verify RAM is NOT pre-consumed:
  #   free -g     # should show ~90GB free at idle, NOT ~1GB
  #   cat /proc/cmdline
  #   sudo dmesg | grep -Ei 'GTT memory ready|TTM'


  # ---- 3b. The ds4 service ----
  services.ds4 = {
    enable = true;
    src    = sources.ds4;
    # CORRECTED: rocminfo reports the 890M as gfx1150 (not gfx1151). Agent list:
    #   Agent 2 = gfx1100 = 7900XTX (dGPU)
    #   Agent 3 = gfx1150 = 890M   (iGPU) <- target this
    gpuArch = "gfx1150";          # the actual 890M arch (gfx_target_version 110500)

    # This box has BOTH the 7900XTX (gfx1100, 24GB) and the 890M iGPU. ds4
    # defaults to ROCm device 0 = the 7900XTX and OOMs on the 81GB model (24GB
    # VRAM). Device 1 is the 890M (ds4 confirmed 7900XTX=device 0 by loading
    # there). Pin ds4 to the iGPU so it uses the 124GB GTT aperture:
    gpuDeviceIndex = 1;           # the 890M (7900XTX is 0)

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
    # Model on the OPTANE mirror, not /tank (HDD). SSD streaming pages routed
    # experts from this file on every cache miss; on HDD that's ~1 t/s (10ms
    # seeks). Optane's ~10µs random reads make streaming far more usable.
    # Copy the GGUF to ds4kv/models first (see SETUP-NOTES). Adjust the path to
    # the actual ds4kv/models mountpoint.
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

    # PERFORMANCE: streaming generation is slow because every token routes
    # through experts that may miss the cache and page from the GGUF. The model
    # is on Optane (above) to make those misses fast. Thinking control: the
    # ds4-SERVER does NOT take --nothink (that's the ds4 CLI flag). Server-side
    # thinking is controlled via the API/`--help thinking` — set per request or
    # via the appropriate server option once confirmed. DeepSeek V4 thinks by
    # default (long reasoning = many expert-routed tokens), so disabling it for
    # non-reasoning tasks roughly halves the token count.
    # extraArgs = [ ];  # add the correct server-side thinking flag here if any

    contextSize = 32768;

    kvDiskDir     = "/mnt/ds4-kv";
    kvDiskSpaceMb = 65536;

    # Optional MTP speculative decoding (download the mtp gguf, then):
    # Optional MTP speculative decoding (if you download an mtp gguf to Optane):
    # extraArgs = [ "--mtp" "/mnt/ds4-kv/models/mtp.gguf" "--mtp-draft" "2" ];
  };


  # ---- 3c. Optane ZFS mirror for the KV cache ----
  # Create the pool ONCE by hand (see SETUP-NOTES). Then import at boot:
  boot.zfs.extraPools = [ "ds4kv" ];


  # ---- 3d. Odysseus endpoint ----
  # ds4-server is OpenAI-compatible. In Odysseus add an external endpoint:
  #     Base URL: http://127.0.0.1:8030/v1
  #     Model id: deepseek-v4-flash
  #     API key:  any non-empty string (ds4 ignores it)
  # Cap Odysseus's context for this model at <= 64000 so it truncates instead
  # of erroring on overflow.
}
