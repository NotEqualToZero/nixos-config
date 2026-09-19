{ config, lib, pkgs, ... }:
let
  pins = import ./npins;
  xrh = pins.xr-hardware;
in {
  nixpkgs.overlays = [
    (final: prev: {
      xr-hardware = prev.xr-hardware.overrideAttrs (old: {
        version = xrh.version;
        src = prev.fetchFromGitLab {
          domain = "gitlab.freedesktop.org";
          owner = "monado/utilities";
          repo = "xr-hardware";
          rev = xrh.revision;
          hash = xrh.hash;
        };
      });
    })
  ];


  services.udev.extraRules = ''
    # Sony PlayStation VR2 - USB
    ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0cde", TAG+="uaccess", ENV{ID_xrhardware}="1"


    # Sony PlayStation VR2 Sense Controller Left - Bluetooth, USB
    ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0e45", TAG+="uaccess", ENV{ID_xrhardware}="1"
    KERNELS=="0005:054C:0E45.*", TAG+="uaccess", ENV{ID_xrhardware}="1"


    # Sony PlayStation VR2 Sense Controller Right - Bluetooth, USB
    ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0e46", TAG+="uaccess", ENV{ID_xrhardware}="1"
    KERNELS=="0005:054C:0E46.*", TAG+="uaccess", ENV{ID_xrhardware}="1"
    '';

  environment.systemPackages = with pkgs; [
    jq
  ];
}
