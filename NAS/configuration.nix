# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  config,
  pkgs,
  lib,
  modulesPath,
  sources,
  ...
}:

{
  imports = [
    "${toString modulesPath}/virtualisation/proxmox-lxc.nix"
    (sources.sops-nix + "/modules/sops")
    ../nixos/secrets.nix
    #./paperless.nix
  ];

  sops.secrets = {
    bucket = {};
    keyid = {};
    accesskey = {};
    restic-passphrase = {};
  };

  sops.templates."repositoryfile".content = ''
    s3://s3.us-west-002.backblazeb2.com/${config.sops.placeholder."bucket"}
  '';

  sops.templates."accessfile".content = ''
    AWS_ACCESS_KEY_ID="${config.sops.placeholder."keyid"}"
    AWS_SECRET_ACCESS_KEY="${config.sops.placeholder."accesskey"}"
  '';

  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "networkmanager" "wheel" ];

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMUgqWiEREHr5rZb3zfLuPf3i+Q8fW00TqHZvDJjcIyG"
    ];

    # passwordFile needs to be in a volume marked with  `neededForBoot = true`
    packages = with pkgs; [
    ];
  };

  services.openssh = {
    enable = true;
    passwordAuthentication = false;
    # allowSFTP = false; # Don't set this if you need sftp
    challengeResponseAuthentication = true;
    extraConfig = ''
      AllowTcpForwarding yes
      X11Forwarding no
      AllowAgentForwarding yes
      AllowStreamLocalForwarding no
      AuthenticationMethods publickey
      '';
  };
  nix.settings.trusted-users = [ "admin" ];


  security.sudo.wheelNeedsPassword = false;


  networking = {
    dhcpcd.enable = false;
    useDHCP = false;
    useHostResolvConf = false;
    hostName = "NAS";
  };

  systemd.network = {
    enable = true;
    networks."50-eth0" = {
      matchConfig.Name = "eth0";
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = true;
      };
      linkConfig.RequiredForOnline = "routable";
    };
  };

  services = {
    samba = {
      enable = true;
      openFirewall = true;
      securityType = "user";
      shares.admin = {
        path = "/storage";
        writable = "yes";
        browsable = "yes";
        "force user" = "admin";
        "force group" = "users";
      };
      shares.global = {
        "server min protocol" = "SMB2_02";
      };
      shares.pconsume = {
        path = "/storage/Paperless Consume";
        writable = "yes";
        browsable = "yes";
        "force user" = "admin";
        "force group" = "users";
      };
    };

    avahi.enable = true;
    samba-wsdd = {
      enable = true;
      openFirewall = true;
    };


  };

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "both";
    openFirewall = true;
  };

  environment.systemPackages = with pkgs; [
    tailscale
    ssh-to-age
    nfs-utils
    restic
    ranger
  ];

  services.restic.backups = {
    NAS = {
      paths = ["/storage"];
      pruneOpts = [
        "--keep-hourly 3"
        "--keep-daily 7"
        "--keep-weekly 5"
        "--keep-monthly 12"
        "--keep-yearly 10"
      ];
      timerConfig = {
        # OnBootSec = "3m"; # uncomment this this line if your on wifi
        OnCalendar = "hourly";
        Persistent = true;
      };
      passwordFile = config.sops.secrets.restic-passphrase.path;
      environmentFile = config.sops.templates."accessfile".path;
      repositoryFile = config.sops.templates."repositoryfile".path;
      checkOpts = [
        "--with-cache" # just to make checks faster
      ];

    };
  };


  users.users.syncthing = {
    isSystemUser = true;
    createHome = true;
    home = "/var/lib/syncthing";
  };

  services.syncthing = {
    enable = true;
    user = "syncthing";
    openDefaultPorts = true;
    systemService = true;
    guiAddress = "0.0.0.0:8385";
    settings = {
      folders = {
        "paperless" = {
          path = "/storage/Paperless";
          #devices = [ "paperless"];
          type = "receiveonly";
          id = "zofgl-49s4j";
        };
      };
    };
  };

  services.rpcbind.enable = true;

  system.stateVersion = "24.05"; # Did you read the comment?
}
