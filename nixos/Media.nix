{ config, lib, pkgs, sources, ... }:
let
  nixflix = import sources.nixflix { inherit pkgs; };
  pkgs-uns = import sources.pkgs-uns {
    system = "x86_64-linux"; # Adjust to your system
  };
in {
  imports = [
    nixflix.nixosModules.default
    ../Compose2Nix/octo-fiesta.nix
  ];

  octo-fiesta.enable = false;

  environment.systemPackages = with pkgs; [
    #beets
  ];

  # nix.settings.fallback = true; #temporary?
  users.users.admin.extraGroups = [ "media" ];

  users.groups.media = {};

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
    #stateDir = "/data/.state";
    downloadsDir = "/mnt/storage/mediadata";

    theme = {
      enable = true;
      name = "overseerr";
    };

    postgres.enable = true;
    nginx = {
      enable = true;
      addHostsEntries = false;
    };

    jellyfin = {
      enable = false;
      apiKey._secret = config.sops.secrets.jelly-api.path;
      users.admin= {
        policy.isAdministrator = true;
        password._secret = config.sops.secrets.jelly-pass.path;
      };
      plugins = {
        "Bookshelf" = {
          package = nixflix.lib.jellyfinPlugins.fromRepo {
            version = "13.0.0.0";
            hash = "sha256-16jaQRh1rIFE27nSSEWNF7UjVsPJDaRf24Ews0BZGas=";
          };
          config = {
            # Plain string (visible in Nix store)
            #ComicVineApiKey = "my-api-key";
            # Or as a secret (read from file at activation time)
            # ComicVineApiKey._secret = "/run/secrets/comic-vine-api-key";
          };
        };
      };
    };

    prowlarr = {
      enable = false;
      config = {
        apiKey._secret = config.sops.secrets.prowlarr-api.path;
         hostConfig = {
          password._secret = config.sops.secrets.jelly-pass.path;
         };
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

    sonarr = {
      enable = false;
      config = {
        apiKey._secret = config.sops.secrets.sonarr-api.path;
        hostConfig = {
          password._secret = config.sops.secrets.jelly-pass.path;
        };
      };
    };

    sonarr-anime = {
      enable = false;
      config = {
        apiKey._secret = config.sops.secrets.anime-api.path;
         hostConfig = {
          password._secret = config.sops.secrets.jelly-pass.path;
        };
      };
    };

    radarr = {
      enable = true;
      config = {
        apiKey._secret = config.sops.secrets.radarr-api.path;
        hostConfig = {
          password._secret = config.sops.secrets.jelly-pass.path;
        };
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

  };

  networking.firewall.checkReversePath = "loose";

  services = {
    tailscale = {
      useRoutingFeatures = "both";
      extraSetFlags = [ "--advertise-exit-node" ];
    };
    deluge = {
      enable = false;
      web.enable = true;
      # declarative = true;
      group = "media";
      #config = {
      #  download_location = "/data/downloads/torrents/incomplete";
      #};
    };
    navidrome = {
      enable = false;
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


}
