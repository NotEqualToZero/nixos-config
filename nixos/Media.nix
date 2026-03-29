{ config, lib, pkgs, sources, ... }:
let
  nixflix = import sources.nixflix;
  pkgs-uns = import sources.pkgs-uns {
    system = "x86_64-linux"; # Adjust to your system
  };
in {
  imports = [
    nixflix.nixosModules.default
    ../Compose2Nix/octo-fiesta.nix
  ];

  octo-fiesta.enable = true;

  environment.systemPackages = with pkgs; [
    beets
  ];

  # nix.settings.fallback = true; #temporary?
  users.users.admin.extraGroups = [ "media" ];

  users.groups.media = {};

  sops.secrets = {
    jelly-pass = {};
    sonarr-api = {};
    radarr-api = {};
    lidarr-api = {};
    seerr-api = {};
    anime-api = {};
    prowlarr-api = {};
    mullvad-acc = {};
    NZBStars-api = {};
    sabnzbd-api = {};
    sabnzbd-nzb = {};
    eweka-user = {};
    eweka-pass = {};
  };
  services.syncthing = {
    enable = true;
    group = "media";
    openDefaultPorts = true;
    systemService = true;
    guiAddress = "0.0.0.0:8385";
  };

  nixflix = {
    enable = false;
    mediaDir = "/mnt/storage/media";
    stateDir = "/data/.state";
    downloadsDir = "/mnt/storage/mediadata";

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
         indexers = [
           {
             name = "NZBStars";
             apiKey = {_secret = config.sops.secrets.NZBStars-api.path;};
           }
           { name = "BitSearch"; }
           { name = "Bangumi Moe"; }
           { name = "BT.etree"; }
           { name = "EZTV"; }
           { name = "Knaben"; }
           { name = "nekoBT"; }
           { name = "SubsPlease"; }
         ];
      };
    };

    sabnzbd = {
      enable = true;
      settings = {
        misc = {
          api_key = {_secret = config.sops.secrets.sabnzbd-api.path;};
          nzb_key = {_secret = config.sops.secrets.sabnzbd-nzb.path;};
        };

        servers = [
          {
            name = "Eweka";
            host = "sslreader.eweka.nl";
            port = 563;
            # Secrets use { _secret = /path; } syntax
            username = {_secret = config.sops.secrets.eweka-user.path;};
            password = {_secret = config.sops.secrets.eweka-pass.path;};
            connections = 20;
            ssl = true;
            priority = 0;
            retention = 3000;
          }
        ];
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
      enable = false;
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
        hostConfig = {
          password = {_secret = config.sops.secrets.jelly-pass.path;};
          username = "admin";
        };
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
        hostConfig = {
          password = {_secret = config.sops.secrets.jelly-pass.path;};
          username = "admin";
        };
       };
    };

    jellyseerr = {
      enable = false;
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

  networking.firewall.checkReversePath = "loose";

  services = {
    tailscale = {
      useRoutingFeatures = "both";
      extraSetFlags = [ "--advertise-exit-node" ];
    };
    deluge = {
      enable = true;
      web.enable = true;
      # declarative = true;
      group = "media";
      #config = {
      #  download_location = "/data/downloads/torrents/incomplete";
      #};
    };
    navidrome = {
      enable = true;
      group = "media";
      settings = {
        MusicFolder = "/mnt/storage/media/music";
        Address = "0.0.0.0";
      };
    };
  };

nixpkgs.overlays = [ # Fix for Navidrome being busted in version 0.59
  (self: super: {
    navidrome = self.callPackage (pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/cimm/nixpkgs/71aa374ad541b41e6fccd543c67b6952d2ccafca/pkgs/by-name/na/navidrome/package.nix";
      sha256 = "16mfj85w8d7vzc9pgcgjn7a71z7jywqpdn8igk9zp0hw9dvm9rmq";
    }) {};
  })
];

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
