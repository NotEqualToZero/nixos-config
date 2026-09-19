# ds4 on Mnemosyne — setup & verification notes
# (follows the project's STRIXHALO.md; ROCm support is in the MAIN branch)

## CONFIRMED from diagnostics
- iGPU 890M arch: gfx1151  (gfx_target_version 110500)
- RAM: 93GB total, ~88GB available with current stack
- iGPU: 512MB hard VRAM + 88GB GTT aperture (dynamic, shares system RAM)
- 7900XTX present too (gfx1100 / 110000) — ds4 targets the iGPU here


## STEP 1 — GTT aperture kernel params (REQUIRED, STRIXHALO.md §3)

Without these, Strix Halo exposes only ~62GB GPU-visible memory and the
~80.76GiB model will NOT load. Added via boot.kernelParams in the wiring:

    amd_iommu=off
    amdgpu.gttsize=126976
    ttm.pages_limit=32505856
    ttm.page_pool_size=32505856

⚠ amd_iommu=off disables the IOMMU globally. If Mnemosyne uses VFIO/PCI
passthrough or relies on IOMMU isolation for Incus, weigh that first.

Deploy these, REBOOT, then verify:
    cat /proc/cmdline
    sudo dmesg | grep -Ei 'GTT|gttsize|TTM|VRAM'
    #   expect: "amdgpu: 126976M of GTT memory ready"
    cat /sys/class/drm/renderD129/device/mem_info_gtt_total   # should be much larger
    rocminfo | grep -A80 'gfx1151'                            # pool ~130023424 KB


## STEP 2 — Download the model (as odysseus, into /tank/Models/ds4)

Use the EXACT GGUF from STRIXHALO.md. AVOID mixed IQ2/IQ4 GGUFs (system OOM):

    DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix.gguf

    sudo install -d -o odysseus -g odysseus /tank/Models/ds4
    # Via the project's downloader (clone the pinned source, run from it):
    #   ./download_model.sh q2-imatrix
    # It writes ./gguf/ and updates ./ds4flash.gguf. Copy/symlink the resolved
    # IQ2XXS...imatrix file to /tank/Models/ds4/ with the name above.
    #
    # Or direct hf download (use the hf binary full path as before):
    #   HF=/nix/store/...python3-env/bin/hf
    #   sudo -u odysseus env HF_HOME=/tank/Models/Odysseus/.cache/huggingface \
    #     "$HF" download antirez/deepseek-v4-gguf \
    #     --include "*IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix*" \
    #     --local-dir /tank/Models/ds4


## STEP 3 — Optane ZFS mirror for KV cache (once, by hand)

Find the devices:
    ls -l /dev/disk/by-id/ | grep -iE "optane|nvme"

Create + tune (Optane likes small low-latency syncs):
    zpool create -o ashift=12 ds4kv mirror \
      /dev/disk/by-id/<optane-1> /dev/disk/by-id/<optane-2>
    zfs set mountpoint=/mnt/ds4-kv ds4kv
    zfs set compression=off ds4kv     # KV payloads already compressed
    zfs set recordsize=16k  ds4kv
    zfs set atime=off       ds4kv
    chown odysseus:odysseus /mnt/ds4-kv
  Config imports it: boot.zfs.extraPools = [ "ds4kv" ];


## STEP 4 — Pin, build, deploy

  On Hades2:
    cd ~/nixos-config
    npins add github antirez ds4 --branch main
    # add module to Mnemosyne imports; add the services.ds4 block + kernelParams
    colmena build --on Mnemosyne 2>&1 | tail -8   # first build compiles HIP — SLOW
    colmena apply --on Mnemosyne
    sudo reboot                                    # for the GTT kernel params


## STEP 5 — Verify

    # Confirm aperture (post-reboot)
    sudo dmesg | grep -Ei 'GTT memory ready'

    # ds4 up? (auto-stopped llama-swap via Conflicts=)
    systemctl status ds4 llama-swap --no-pager | grep -E "Active:"

    curl -s http://127.0.0.1:8030/v1/models | python3 -m json.tool

    # First call does the big prefill (slow); later calls reuse KV cache.
    time curl -s http://127.0.0.1:8030/v1/chat/completions \
      -H 'Content-Type: application/json' \
      -d '{"model":"deepseek-v4-flash","messages":[{"role":"user","content":"hi"}]}' \
      | python3 -m json.tool | head -30

    # iGPU actually used? memory climbs into the tens of GB:
    free -g
    cat /sys/class/drm/renderD129/device/mem_info_vram_used 2>/dev/null
    rocm-smi --showuse 2>/dev/null | head

    # KV cache landing on Optane?
    ls -la /mnt/ds4-kv/    # files appear after first cold prefill


## STEP 6 — Model switching (Conflicts=)

  sudo systemctl start ds4          # auto-stops llama-swap
  sudo systemctl start llama-swap   # auto-stops ds4

  Both currently wantedBy multi-user.target → boot start is nondeterministic.
  Recommend: keep llama-swap as boot default, make ds4 manual-only by adding to
  the ds4 service:  wantedBy = lib.mkForce [ ];


## BUILD RISKS TO WATCH

- Make target is `make strix-halo` (alias `make rocm`). package.nix tries
  `strix-halo` then falls back. If the build errors on an unknown target or a
  GPU_ARCH var, paste:  grep -E '^[a-z0-9-]+:' Makefile  and the rocm/strix
  sections, and I'll correct buildPhase.
- rocWMMA headers: STRIXHALO.md notes Ubuntu's pkg misses rocwmma/internal/.
  nixpkgs' rocmPackages.rocwmma should ship the full tree; if the build fails
  on missing rocwmma/internal/*.hpp, that package version is incomplete and
  we'd vendor the headers (clone ROCm/rocWMMA rocm-7.1.0) like the doc does.
- rocmPackages attribute names vary by nixpkgs version. If eval errors on a
  missing attr (e.g. hipblaslt / rocwmma / hipcub), check what your pinned
  26.05 provides:  nix eval --raw -f '<nixpkgs>' 'rocmPackages' --apply 'p: builtins.concatStringsSep " " (builtins.attrNames p)'
  and we map to the right names.
- amd_iommu=off is global. Reconsider if Mnemosyne does PCI passthrough.
