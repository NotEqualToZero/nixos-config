{ config, lib, pkgs, sources, ... }:

{
  sops.secrets.builder-pub.neededForUsers = true;

  users.users.remotebuild = {
    isSystemUser = true;
    group = "remotebuild";
    useDefaultShell = true;

    openssh.authorizedKeys = {
      keyFiles = [ ../secrets/remotebuild.pub ];
      keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOvvqdxHPIZqIgssPh4xJysmL83yxqAdsUe5DIXzrqzZ" ];
    };
  };

  users.groups.remotebuild = {};

  nix.settings.trusted-users = [ "remotebuild" ];
}
