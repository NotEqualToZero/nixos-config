{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];


  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "clotho"; # Define your hostname.


  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usb_storage" "usbhid" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "/dev/disk/by-uuid/edbf964b-40e7-4ace-80f8-4e945ed16551";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/2E01-6E35";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };


  fileSystems."/storage" =
    { device = "/dev/disk/by-uuid/43148269-cf88-40c4-86f5-d62906998df1";
      fsType = "btrfs";
    };

  swapDevices =
    [ { device = "/dev/disk/by-uuid/b10e0c8d-c921-4596-be72-eea0d2df9ff6"; }
    ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
