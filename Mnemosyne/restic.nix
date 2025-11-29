{ config, lib, pkgs, sources, ... }:
{
  imports = [];

  environment.systemPackages = [ pkgs.restic ];

  services.restic.backups.paperless = {
    initialize = true;

  };

}
