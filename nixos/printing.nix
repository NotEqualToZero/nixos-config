{ config, lib, pkgs, ... }:

{
  hardware.sane = {
    enable = true; # enables support for SANE scanners
    extraBackends = [ pkgs.sane-airscan pkgs.hplipWithPlugin ];
  };

  services = {
    avahi = {
      enable = true;
      nssmdns = true;
    };
    udev.packages = [ pkgs.sane-airscan ];
    ipp-usb.enable = true;
  };
}
