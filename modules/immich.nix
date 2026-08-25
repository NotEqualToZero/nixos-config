{ config, lib, pkgs, ... }:

{
  services.immich = {
    enable = true;
    port = 2283;
    host = "0.0.0.0";
    openFirewall = true;
    mediaLocation = "/tank/Immich";
    accelerationDevices = null; #gives access to all render devices
  };

  hardware.graphics.enable = true; # Enable hardware for acceleration

  users.users.immich.extraGroups = [ "video" "render"];

}
