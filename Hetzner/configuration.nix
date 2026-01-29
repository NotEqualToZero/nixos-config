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
    ./hardware-configuration.nix
    ../secrets/hetzner-networking.nix # generated at runtime by nixos-infect
    (sources.sops-nix + "/modules/sops")
  ];

  sops.secrets = {
    tailscale-manage= {};
  };

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

  services.tailscale = {
    enable = true;
    # Enable tailscale at startup

    # If you would like to use a preauthorized key
   authKeyFile = config.sops.secrets.tailscale-manage.path;

  };

  boot.tmp.cleanOnBoot = true;
  zramSwap.enable = true;
  networking.hostName = "Lighthouse";
  networking.domain = "";
  users.users.root.openssh.authorizedKeys.keys = [''ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJruM1Ek+bwfySYMyYWmtCA1SyUpC7Jj1GMnEWaLiQ19'' ];
  system.stateVersion = "23.11";
}
