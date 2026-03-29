{ pkgs, sources, config, lib, ... }:
{
  imports = [
    ./secrets.nix
  ];

  sops.secrets = {
    tailscale-manage= {};
   builder-ssh = {
    format = "binary";
    sopsFile = ../secrets/remotebuilder/remotebuild;
   };
  };

  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

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

  nix.buildMachines = [
    {
      hostName = "nas";
      systems = [ "x86_64-linux" ];
      protocol = "ssh-ng";
      maxJobs = 8;
      speedFactor = 5;
      supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
      sshUser = "remotebuild";
      sshKey = config.sops.secrets.builder-ssh.path;
    }
  ];
  nix.distributedBuilds = true;

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

  security.sudo.wheelNeedsPassword = false;

  services.tailscale = {
    enable = lib.mkDefault false;
    openFirewall = true;
    # Enable tailscale at startup

    # If you would like to use a preauthorized key
   #authKeyFile = config.sops.secrets.tailscale-manage.path;

  };
  # 1. Enable the service and the firewall
  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;
    # Always allow traffic from your Tailscale network
    trustedInterfaces = [ "tailscale0" ];
    # Allow the Tailscale UDP port through the firewall
    allowedUDPPorts = [ config.services.tailscale.port ];
  };

  # 2. Force tailscaled to use nftables (Critical for clean nftables-only systems)
  # This avoids the "iptables-compat" translation layer issues.
  systemd.services.tailscaled.serviceConfig.Environment = [
    "TS_DEBUG_FIREWALL_MODE=nftables"
  ];

  # 3. Optimization: Prevent systemd from waiting for network online
  # (Optional but recommended for faster boot with VPNs)
  systemd.network.wait-online.enable = false;
  boot.initrd.systemd.network.wait-online.enable = false;

  nix.channel.enable = false;
  nix.nixPath = [ "nixpkgs=/etc/nixos/nixpkgs" ];

  environment.etc = {
    "nixos/nixpkgs".source = builtins.storePath pkgs.path;
  };

  nixpkgs.overlays = [ (final: prev: {
    inherit (prev.lixPackageSets.stable)
      nixpkgs-review
      nix-eval-jobs
      nix-fast-build;
      #colmena;
  }) ];

  nix = {
    package = pkgs.lixPackageSets.stable.lix;
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "root"
        "@wheel"
        "admin"
      ];
      keep-outputs = true;
      keep-derivations = true;
      auto-optimise-store = true;
      builders-use-substitutes = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      randomizedDelaySec = "1h";
      options = "--delete-older-than 30d";
    };
  };
}

