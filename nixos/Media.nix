{ config, lib, pkgs, sources, ... }:
let
  nixflix = import sources.nixflix;
in {
  imports = [
    nixflix.nixosModules.default
  ];

  nix.settings.fallback = true; #temporary?
  users.users.admin.extraGroups = [ "media" ];

  sops.secrets = {
    jelly-pass = {};
    sonarr-api = {};
    radarr-api = {};
    lidarr-api = {};
    seerr-api = {};
    anime-api = {};
    prowlarr-api = {};
    mullvad-acc = {};
  };
  services.syncthing = {
    enable = true;
    group = "media";
    openDefaultPorts = true;
    systemService = true;
    guiAddress = "0.0.0.0:8385";
  };

  nixflix = {
    enable = true;
    mediaDir = "/mnt/storage/media";
    stateDir = "/data/.state";

    theme = {
      enable = true;
      name = "overseerr";
    };

    postgres.enable = true;
    #nginx.enable = true;

    jellyfin = {
      enable = true;
      users.admin= {
        policy.isAdministrator = true;
        password = {_secret = config.sops.secrets.jelly-pass.path;};
      };
    };

    prowlarr = {
      enable = true;
      config = {
        apiKey = {_secret = config.sops.secrets.prowlarr-api.path;};
         hostConfig = {
          password = {_secret = config.sops.secrets.jelly-pass.path;};
          username = "admin";
        };
      };
    };

    sonarr = {
      enable = true;
      config = {
        apiKey = {_secret = config.sops.secrets.sonarr-api.path;};
        hostConfig = {
          password = {_secret = config.sops.secrets.jelly-pass.path;};
          username = "admin";
        };
      };
    };

    sonarr-anime = {
      enable = true;
      config = {
        apiKey = {_secret = config.sops.secrets.anime-api.path;};
         hostConfig = {
          password = {_secret = config.sops.secrets.jelly-pass.path;};
          username = "admin";
        };
      };
    };

    radarr = {
      enable = true;
      config = {
        apiKey = {_secret = config.sops.secrets.radarr-api.path;};
        hostConfig.password = {_secret = config.sops.secrets.jelly-pass.path;};
       };
    };

    recyclarr = {
      enable = true;
      cleanupUnmanagedProfiles = true;
    };

    lidarr = {
      enable = true;
      config = {
        apiKey = {_secret = config.sops.secrets.lidarr-api.path;};
        hostConfig.password = {_secret = config.sops.secrets.jelly-pass.path;};
       };
    };

    jellyseerr = {
      enable = true;
      vpn.enable = true;
      apiKey = {_secret = config.sops.secrets.seerr-api.path;};
    };

    mullvad = {
      enable = true;
      accountNumber = {_secret = config.sops.secrets.mullvad-acc.path;};
      autoConnect = true;
      location = [ "au" ];
      killSwitch.enable = true;
    };
  };

networking.nftables = {
  enable = true;
  tables."mullvad-tailscale" = {
    family = "inet";
    content = ''
      chain prerouting {
        type filter hook prerouting priority -50; policy accept;

        # Allow Tailscale protocol traffic to bypass Mullvad
        udp dport 41641 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;

        # Allow direct mesh traffic (Tailscale device to Tailscale device) to bypass Mullvad
        ip saddr 100.64.0.0/10 ip daddr 100.64.0.0/10 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;

        # Exit node traffic: DON'T mark it - let it route through VPN without bypass mark
        # Clear meta mark so it routes through Mullvad (no ct mark means Mullvad won't drop in NAT)
        iifname "tailscale0" ip daddr != 100.64.0.0/10 meta mark set 0;

        # Return traffic from VPN: Mark it so it routes via Tailscale table
        # Use bypass mark so it doesn't get routed back through Mullvad
        iifname "wg0-mullvad" ip daddr 100.64.0.0/10 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
      }

      chain outgoing {
        type route hook output priority -100; policy accept;
        meta mark 0x80000 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
        ip daddr 100.64.0.0/10 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
        # Allow outgoing UDP from Tailscale port to bypass Mullvad
        udp sport 41641 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
      }

      chain postrouting {
        type nat hook postrouting priority 100; policy accept;

        # Masquerade exit node traffic going through Mullvad
        iifname "tailscale0" oifname "wg0-mullvad" masquerade;
      }
    '';
  };
};

}
