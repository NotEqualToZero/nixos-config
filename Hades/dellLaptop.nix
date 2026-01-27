{ config, lib, pkgs, sources, ... }:
{
  imports = [
    ./configuration.nix
    ./Hades2.nix
    (sources.nixos-hardware + "/dell/latitude/7390")
  ];
  hardware.bluetooth.enable = true; # enables support for Bluetooth
  hardware.bluetooth.powerOnBoot = true; # powers up the
  # default Bluetooth controller on boot
  hardware.sane.enable = true; #scanners
  services.hardware.bolt.enable = true;
  services.printing.enable = true;
  # services.printing.drivers = [ pkgs.pantum-driver ];

  services.ipp-usb.enable=true;
  hardware.sane.extraBackends = [ pkgs.sane-airscan ];
  services.udev.packages = [ pkgs.sane-airscan ];

  boot.supportedFilesystems = [ "ntfs" ];

  # services.xserver.videoDrivers = [ "displaylink" "modesetting" ];
  systemd.services.dlm.wantedBy = [ "multi-user.target" ];
  environment.systemPackages = with pkgs; [
    # displaylink
    wget
    git
    distrobox
    simple-scan
  ];
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };
}
