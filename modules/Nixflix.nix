{ config, lib, pkgs, ... }:

{

  sops.secrets = {
    jelly-pass = {};
    jelly-api = {};
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
    mull-nixflix = {
      format = "binary";
      sopsFile = ../secrets/mull-nixflix.conf;
    };
  };

  nixflix = {
    enable = true;
    mediaDir = "/mnt/storage/media";
    stateDir = "/mnt/storage/mediadata";
    mediaUsers = [ "media" ];

    nginx = {
      enable = false;
      addHostsEntries = false; # Disable this if you have your own DNS configuration
    };

    vpn = {
      enable = true;
      accessableFrom = [
        "192.168.0.0/24"
        "100.0.0.0/48"
      ];
      wgConfFile = config.sops.secrets.mull-nixflix.path;
    };

    theme = {
      enable = true;
      name = "overseerr";
    };

    postgres.enable = true;

    sonarr-anime = {
      enable = true;
      config = {
        apiKey = {_secret = config.sops.secrets.anime-api.path;};
        hostConfig.password = {_secret = config.sops.secrets.jelly-pass.path;};
      };
    };

    sonarr = {
      enable = true;
      config = {
        apiKey = {_secret = config.sops.secrets.sonarr-api.path;};
        hostConfig.password = {_secret = config.sops.secrets.jelly-pass.path;};
      };
    };

    radarr = {
      enable = true;
      config = {
        apiKey = {_secret = config.sops.secrets.radarr-api.path;};
        hostConfig.password = {_secret = config.sops.secrets.jelly-pass.path;};
      };
    };

    prowlarr = {
      enable = true;
      config = {
        apiKey = {_secret = config.sops.secrets.prowlarr-api.path;};
        hostConfig.password = {_secret = config.sops.secrets.jelly-pass.path;};
        indexers = [
           {
             name = "NZBStars";
             apiKey._secret = config.sops.secrets.NZBStars-api.path;
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

    recyclarr = {
      enable = true;
      cleanupUnmanagedProfiles.enable = true;
    };

    lidarr = {
      enable = true;
      config = {
        apiKey._secret = config.sops.secrets.lidarr-api.path;
        hostConfig = {
          password._secret = config.sops.secrets.jelly-pass.path;
        };
       };
    };

    seerr = {
      enable = true;
      apiKey._secret = config.sops.secrets.seerr-api.path;
    };

#    sabnzbd = {
#      enable = true;
#      settings = {
#        misc.api_key = {_secret = config.sops.secrets.sabnzbd-api.path;};
#      };
#    };

    jellyfin = {
      apiKey = {_secret = config.sops.secrets.jelly-api.path;};
      enable = true;
      openFirewall = true;
      users.admin = {
        policy.isAdministrator = true;
        password = {_secret = config.sops.secrets.jelly-pass.path;};
      };
      users.Ash = {
        policy.isAdministrator = true;
        password = "";
      };
    };

    torrentClients = {
      qbittorrent = {
        enable = true;
        password = {_secret = config.sops.secrets.jelly-pass.path;};
      };
    };

  };
}
