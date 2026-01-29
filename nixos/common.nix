{ pkgs, sources, config, lib, ... }:
{
  imports = [
    ./secrets.nix
  ];

  sops.secrets = {
    tailscale-manage= {};
  };

  services.tailscale = {
    enable = lib.mkDefault false;
    # Enable tailscale at startup

    # If you would like to use a preauthorized key
   authKeyFile = config.sops.secrets.tailscale-manage.path;

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
      ];
      keep-outputs = true;
      keep-derivations = true;
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      randomizedDelaySec = "1h";
      options = "--delete-older-than 30d";
    };
  };
}

