{ config, pkgs, ... }:
{
  imports = [
  ];
  environment.systemPackages = [
  ];

  # Plasma desktop
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };
  services.xserver.enable = true;
}
