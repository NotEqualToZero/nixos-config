{ config, lib, pkgs, sources, ... }:
{
  imports = [
    # (sources.nixos-hardware + "/dell/latitude/7390")
  ];
  hardware.bluetooth.enable = true; # enables support for Bluetooth
  hardware.bluetooth.powerOnBoot = true; # powers up the
  # default Bluetooth controller on boot
  hardware.sane.enable = true; #scanners
  services.hardware.bolt.enable = true;
  services.printing.enable = true;
  services.printing.drivers = [ pkgs.pantum-driver ];

  services.ipp-usb.enable=true;
  hardware.sane.extraBackends = [ pkgs.sane-airscan ];
  services.udev.packages = [ pkgs.sane-airscan ];

  # boot.supportedFilesystems = [ "ntfs" ];

  services.xserver.videoDrivers = [ "modesetting" ];
  systemd.services.dlm.wantedBy = [ "multi-user.target" ];
  environment.systemPackages = with pkgs; [
    displaylink
  ];

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      # Required for modern Intel GPUs (Xe iGPU and ARC)
      intel-media-driver     # VA-API (iHD) userspace
      vpl-gpu-rt             # oneVPL (QSV) runtime

      # Optional (compute / tooling):
      intel-compute-runtime  # OpenCL (NEO) + Level Zero for Arc/Xe
      # NOTE: 'intel-ocl' also exists as a legacy package; not recommended for Arc/Xe.
      # libvdpau-va-gl       # Only if you must run VDPAU-only apps
    ];
  };

  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";     # Prefer the modern iHD backend
    # VDPAU_DRIVER = "va_gl";      # Only if using libvdpau-va-gl
  };

  # May help if FFmpeg/VAAPI/QSV init fails (esp. on Arc with i915):
  hardware.enableRedistributableFirmware = true;
  boot.kernelParams = [ "i915.enable_guc=3" ];

  # May help services that have trouble accessing /dev/dri (e.g., jellyfin/plex):
  # users.users.<service>.extraGroups = [ "video" "render" ];
}
