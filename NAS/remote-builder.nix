{ config, lib, pkgs, sources, ... }:

{
  sops.secrets.builder-pub.neededForUsers = true;

  users.users.remotebuild = {
    isSystemUser = true;
    group = "remotebuild";
    useDefaultShell = true;

    openssh.authorizedKeys.keyFiles = [ ../secrets/remotebuild.pub ];
  };

  users.groups.remotebuild = {};

  nix.settings.trusted-users = [ "remotebuild" ];
}
