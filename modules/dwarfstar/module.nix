# NixOS module: ds4-server as a declarative service for Mnemosyne.
#
# - Serves DeepSeek V4 Flash over an OpenAI/Anthropic-compatible API on a local
#   port, which Odysseus consumes as an external endpoint (like llama-swap).
# - Mutually exclusive with llama-swap via systemd Conflicts= (your choice):
#   starting ds4 stops llama-swap and vice versa, so the 81GB model never has
#   to share the 96GB unified-memory pool with the llama-swap models.
# - KV cache on the Optane ZFS mirror.
# - Reuses the odysseus user + the GPU device-access / hardening relaxations we
#   worked out for llama-swap (ROCm needs the same char-drm + /dev/kfd rules).

{ config, lib, pkgs, ... }:

let
  cfg = config.services.ds4;

  # Build the ROCm ds4 package. `src` comes from npins; gpuArch must match the
  # 890M (verify with rocminfo — gfx1150 or gfx1151).
  ds4Pkg = pkgs.callPackage ./package.nix {
    src     = cfg.src;
    gpuArch = cfg.gpuArch;
  };
in
{
  options.services.ds4 = {
    enable = lib.mkEnableOption "ds4 (DwarfStar 4) DeepSeek V4 Flash server";

    src = lib.mkOption {
      type = lib.types.path;
      description = "ds4 source (npins-pinned rocm branch / Strix Halo PR commit).";
    };

    gpuArch = lib.mkOption {
      type = lib.types.str;
      default = "gfx1150";
      description = "HIP target arch for the 890M iGPU. VERIFY with rocminfo (gfx1150 vs gfx1151).";
    };

    hsaGfxOverride = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "11.0.0";
      description = ''
        Optional HSA_OVERRIDE_GFX_VERSION. If rocBLAS lacks tensile kernels for
        the iGPU's exact gfx, override to the nearest supported arch. Leave null
        first; only set if ROCm init complains about missing kernels.
      '';
    };

    gpuDeviceIndex = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      example = 1;
      description = ''
        Which ROCm GPU ds4 should use, by HIP/ROCr device index. CRITICAL on
        machines with BOTH a discrete GPU and the Strix Halo iGPU: by default
        ds4 grabs device 0, which may be the dGPU (e.g. a 24GB 7900XTX) and
        OOMs on the 81GB model. Set this to the iGPU's index (find it with
        `rocminfo` — the gfx1151 agent) so ds4 uses the iGPU + its large GTT
        aperture instead. Pins HIP_VISIBLE_DEVICES / ROCR_VISIBLE_DEVICES /
        CUDA_VISIBLE_DEVICES to this index.
      '';
    };

    model = lib.mkOption {
      type = lib.types.path;
      example = "/tank/Models/ds4/DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix.gguf";
      description = ''
        Path to the DeepSeek V4 Flash GGUF (ds4-specific quant). On Strix Halo,
        STRIXHALO.md recommends the IQ2XXS-w2Q2K-...-imatrix GGUF and warns
        AGAINST mixed IQ2/IQ4 GGUFs (they cause system OOM on this hardware).
      '';
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Bind address for ds4-server.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8030;
      description = "Port for the OpenAI/Anthropic-compatible API.";
    };

    contextSize = lib.mkOption {
      type = lib.types.int;
      default = 16000;
      description = ''
        --ctx value. The model alone is ~80GB; on 96GB total that leaves very
        little for the KV cache + runtime buffers, and the live KV is allocated
        up front. A large context here OOM-kills the process right after the
        model finishes loading. Keep this SMALL (16k–32k) and rely on the Optane
        disk KV cache (--kv-disk-dir) for prefix reuse — that's exactly what it's
        for. Raise only after confirming free RAM with the model resident.
        Requires the GTT-aperture kernel params (STRIXHALO.md §3).
      '';
    };

    kvDiskDir = lib.mkOption {
      type = lib.types.path;
      default = "/mnt/ds4-kv";
      description = "Disk KV cache dir (the Optane ZFS mirror mountpoint).";
    };

    kvDiskSpaceMb = lib.mkOption {
      type = lib.types.int;
      default = 65536;  # 64 GiB of Optane for KV checkpoints
      description = "--kv-disk-space-mb: max disk the KV cache may use.";
    };

    ssdStreaming = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable ds4's SSD streaming capacity mode (--ssd-streaming) for running a
        model larger than usable RAM. Non-routed weights stay resident; routed
        MoE experts are kept in an in-memory cache and paged from the GGUF on
        cache misses. ESSENTIAL on this 96GB box where the 81GB model + arena
        overhead won't fit fully-resident. Generation is slower (expert cache
        misses page from disk) but it runs. NOTE: upstream docs describe this as
        a Metal path — verify the ROCm build accepts the flag before relying on
        it (ds4-server --help | grep ssd).
      '';
    };

    ssdStreamingCacheExperts = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "48GB";
      description = ''
        --ssd-streaming-cache-experts: memory budget for the resident routed
        expert cache (e.g. "48GB"). Leave null to use ds4's automatic budget
        (80% of recommended working set minus non-routed weights), which is
        usually best. Set explicitly only if the auto budget is too large for
        your headroom or you want more room for context. On ~85GB usable,
        48-64GB is a reasonable manual starting point.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      # Default to the Odysseus service's user if that module is present (so ds4
      # shares the model/cache dirs and GPU group membership), otherwise fall
      # back to a dedicated "dwarfstar" user this module creates.
      default =
        if config.services ? odysseus && config.services.odysseus ? user
        then config.services.odysseus.user
        else "dwarfstar";
      defaultText = lib.literalExpression
        ''config.services.odysseus.user or "dwarfstar"'';
      description = ''
        User to run ds4-server as. Defaults to the Odysseus service's user when
        that module is in use (sharing its model dirs + GPU groups), else a
        dedicated "dwarfstar" user created by this module. Override to pin it.
      '';
    };

    group = lib.mkOption {
      type = lib.types.str;
      # Mirror the user logic: prefer Odysseus's group (you set it to "collab"
      # on this host), else "dwarfstar".
      default =
        if config.services ? odysseus && config.services.odysseus ? group
        then config.services.odysseus.group
        else "dwarfstar";
      defaultText = lib.literalExpression
        ''config.services.odysseus.group or "dwarfstar"'';
      description = ''
        Group to run ds4-server as. Defaults to the Odysseus service's group
        (e.g. "collab" on this host) when present, else "dwarfstar". Override
        to pin it.
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "--mtp" "/tank/Models/ds4/mtp.gguf" "--mtp-draft" "2" ];
      description = "Extra ds4-server flags (e.g. MTP speculative decoding).";
    };
  };

  config = lib.mkIf cfg.enable {
    # Make the package available system-wide (also gives you ds4-cli/ds4-agent).
    environment.systemPackages = [ ds4Pkg ];

    systemd.services.ds4 = {
      description = "ds4 (DwarfStar 4) DeepSeek V4 Flash server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      # --- Mutual exclusion with llama-swap (your design choice) ---
      # Conflicts: systemd stops llama-swap when ds4 starts, and vice versa.
      # This guarantees the 81GB model and the llama-swap models never coexist
      # in the 96GB pool. To switch models you `systemctl start ds4` (which
      # auto-stops llama-swap) or `systemctl start llama-swap` (auto-stops ds4).
      conflicts = [ "llama-swap.service" ];

      environment = {
        ROCM_PATH = "${pkgs.rocmPackages.clr}";
      } // lib.optionalAttrs (cfg.hsaGfxOverride != null) {
        HSA_OVERRIDE_GFX_VERSION = cfg.hsaGfxOverride;
      } // lib.optionalAttrs (cfg.gpuDeviceIndex != null) {
        # Pin ds4 to a specific GPU. Use ONLY HIP_VISIBLE_DEVICES — stacking
        # ROCR_VISIBLE_DEVICES + HIP_VISIBLE_DEVICES causes a renumbering
        # conflict (ROCR filters first, then HIP renumbers the survivors from 0,
        # so HIP_VISIBLE_DEVICES=1 ends up pointing at nothing → "no ROCm-capable
        # device"). HIP numbering here: 0 = 7900XTX, 1 = 890M.
        HIP_VISIBLE_DEVICES = toString cfg.gpuDeviceIndex;
      };

      serviceConfig = {
        ExecStart = lib.concatStringsSep " " ([
          (lib.getExe' ds4Pkg "ds4-server")
          "-m ${cfg.model}"
          "--host ${cfg.listenAddress}"
          "--port ${toString cfg.port}"
          "--ctx ${toString cfg.contextSize}"
          "--kv-disk-dir ${cfg.kvDiskDir}"
          "--kv-disk-space-mb ${toString cfg.kvDiskSpaceMb}"
        ]
        ++ lib.optional cfg.ssdStreaming "--ssd-streaming"
        ++ lib.optionals (cfg.ssdStreamingCacheExperts != null)
             [ "--ssd-streaming-cache-experts" cfg.ssdStreamingCacheExperts ]
        ++ cfg.extraArgs);

        User = cfg.user;
        Group = cfg.group;

        Restart = "on-failure";
        RestartSec = 5;

        # Big model load + first prefill can be slow; give it room to start.
        TimeoutStartSec = "600";

        # --- GPU access (same rules that made llama-swap work on this box) ---
        # char-drm covers the render nodes; /dev/kfd is the ROCm compute node.
        # A directory DeviceAllow does NOT grant the char devices inside it.
        DevicePolicy = "closed";
        DeviceAllow = [ "char-drm rw" "/dev/kfd rw" ];
        SupplementaryGroups = [ "render" "video" ];

        # ROCm/HIP needs these relaxed (UID remap breaks device-group access;
        # the JIT needs W+X; /proc reads for memory info).
        PrivateUsers = false;
        MemoryDenyWriteExecute = false;
        ProcSubset = "all";
        ProtectProc = "default";
        PrivateDevices = false;

        # Filesystem: read the model + cache dir, write the KV dir.
        ReadOnlyPaths = [ (toString cfg.model) ];
        ReadWritePaths = [ cfg.kvDiskDir ];

        # ds4 writes a lock file (/tmp/ds4.lock). ProtectSystem=strict makes the
        # filesystem read-only except explicitly-allowed paths, so give the
        # service its own writable /tmp.
        PrivateTmp = true;

        # Reasonable hardening that does NOT interfere with ROCm.
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    };

    # Ensure the KV dir exists with the right owner before the service starts.
    systemd.tmpfiles.rules = [
      "d ${cfg.kvDiskDir} 0750 ${cfg.user} ${cfg.group} - -"
    ];

    # Create the dwarfstar user/group ONLY when we're falling back to it (i.e.
    # not borrowing an existing user like odysseus). If you point user/group at
    # an existing service account, this module won't try to recreate it.
    users.users = lib.mkIf (cfg.user == "dwarfstar") {
      dwarfstar = {
        isSystemUser = true;
        group = cfg.group;
        description = "DwarfStar (ds4) service user";
        # Needs to read the model + write the KV dir; no home needed.
        home = "/var/lib/dwarfstar";
        createHome = true;
      };
    };
    users.groups = lib.mkIf (cfg.group == "dwarfstar") {
      dwarfstar = { };
    };

    # Catch the 216/GROUP class of failure at build time with a clear message
    # instead of a cryptic runtime exit. The user/group must actually exist:
    # either created above (dwarfstar) or provided by another module (odysseus).
    assertions = [
      {
        assertion =
          cfg.group == "dwarfstar"
          || (config.users.groups ? ${cfg.group});
        message = ''
          services.ds4.group = "${cfg.group}" but no such group is defined.
          ds4 borrows the Odysseus service's user/group by default; if you
          renamed that group (e.g. to "collab"), make sure it exists in the
          NixOS config (users.groups.${cfg.group}), or set services.ds4.group
          explicitly to a group that does. Otherwise the service fails to start
          with status=216/GROUP.
        '';
      }
    ];
  };
}
