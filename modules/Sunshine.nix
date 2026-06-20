{ config, lib, pkgs, ... }:

{
  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true; # only needed for Wayland -- omit this when using with Xorg
    openFirewall = true;
  };


  users.users.cale = {
    extraGroups = [ "uinput" ];
  };
}
