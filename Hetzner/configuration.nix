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
    ./networking.nix # generated at runtime by nixos-infect
  ];

  sops.secrets = {
    tailscale-manage= {};
  };



  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server";
    extraSetFlags = [
      "--advertise-exit-node"
    ];
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
