{ config, lib, pkgs, modulesPath, ... }:
let
  quiet = import ../secrets/quiet.nix;
  sources = import ../npins;
in {
  imports = [
    (sources.sops-nix + "/modules/sops")
    (modulesPath + "/installer/scan/not-detected.nix")
  ];
  # This will add secrets.yml to the nix store
  # You can avoid this by adding a string to the full path instead, i.e.
  # sops.defaultSopsFile = "/root/.sops/secrets/example.yaml";
  sops.defaultSopsFile = ../secrets/default.yaml;
  # This will automatically import SSH keys as age keys
  #sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  # This is using an age key that is expected to already be in the filesystem
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  # This will generate a new key if the key specified above does not exist
  sops.age.generateKey = true;



  boot.initrd.availableKernelModules = [ "xhci_pci" "thunderbolt" "vmd" "nvme" "usb_storage" "sd_mod" "rtsx_pci_sdmmc" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "/dev/mapper/luks-8bf60c0b-0409-4b84-b1de-aa930365115e";
      fsType = "ext4";
    };

  boot.initrd.luks.devices."luks-8bf60c0b-0409-4b84-b1de-aa930365115e".device = "/dev/disk/by-uuid/8bf60c0b-0409-4b84-b1de-aa930365115e";

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/C188-1E26";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };

  boot.loader.grub = {
    enable = true;
    device = "/dev/nvme0n1p1";
    efiSupport = true;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  swapDevices =
    [ { device = "/dev/mapper/luks-b8ffcb8e-8d62-4793-8d78-d4934d3b0163"; }
    ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;


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

  # numen alsa adjustment
  boot.extraModprobeConfig = ''
    options snd slots=sof-hda-dsp
  '';


  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";     # Prefer the modern iHD backend
    # VDPAU_DRIVER = "va_gl";      # Only if using libvdpau-va-gl
  };

  # May help if FFmpeg/VAAPI/QSV init fails (esp. on Arc with i915):
  hardware.enableRedistributableFirmware = true;
  boot.kernelParams = [ "i915.enable_guc=3" ];


users.users.cale = {
  isNormalUser = true;
  description = "Cale";
  extraGroups = [
    "networkmanager"
    "wheel"
    "scanner"
    "lp"
    "dialout"
    "podman"
    "input" #numen
  ];
  packages = with pkgs; [
    sshfs
    emacsPackages.mu4e
    kdePackages.plasma-bigscreen
    apx
    bazaar
    apx-gui
    mu
    mu.mu4e
    uv
    isync
    msmtp
    obsidian
    kitty
    moonlight-qt
#    google-chrome
    st
    vlc
    flameshot
    qutebrowser
    ungoogled-chromium
    discord
    prismlauncher
    colmena
    sops
    git
    emacs
    vim
    ripgrep
    coreutils
    fd
    libvterm
    libtool
    clang
    nixfmt
    shellcheck
    pandoc
    cmake
    simple-scan
    gnumake
    syncthing
    libreoffice-qt-still
    (librewolf.override { cfg.enablePlasmaBrowserIntegration = true; })
  ];
};
  # boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
environment.variables = { SOPS_AGE_KEY_CMD="op read op://Private/Sops-Nix/password"; };

fonts.enableDefaultPackages = true;
fonts.packages = with pkgs; [
  nerd-fonts.symbols-only
];

services.tailscale = {
  useRoutingFeatures = "client";
};

networking.firewall.checkReversePath = "loose";

sops.secrets = {
  cale_passwd = {};
  tailscale-manage= {};
  sync-key = {
    format = "binary";
    sopsFile = ../secrets/hades-sync-key.pem;
    owner = "cale";
  };
  sync-cert = {
    format = "binary";
    sopsFile = ../secrets/hades-sync-cert.pem;
    owner = "cale";
  };
  builder-ssh = {
    format = "binary";
    sopsFile = ../secrets/remotebuilder/remotebuild;
  };
};

nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
  "1password-gui"
  "1password"
];

programs._1password.enable = true;
programs._1password-gui = {
  enable = true;
  # Certain features, including CLI integration and system authentication support,
  # require enabling PolKit integration on some desktop environments (e.g. Plasma).
  polkitPolicyOwners = [ "cale" ];
};


  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "networkmanager" "wheel" ];

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMUgqWiEREHr5rZb3zfLuPf3i+Q8fW00TqHZvDJjcIyG"
    ];

    # passwordFile needs to be in a volume marked with  `neededForBoot = true`
    packages = with pkgs; [
    ];
  };


  services.openssh = {
    enable = true;

    passwordAuthentication = false;

    # allowSFTP = false; # Don't set this if you need sftp
    kbdInteractiveAuthentication = true;
    extraConfig = ''
      AllowTcpForwarding yes
      X11Forwarding no
      AllowAgentForwarding yes
      AllowStreamLocalForwarding no
      AuthenticationMethods publickey
      '';
  };

  security.sudo.wheelNeedsPassword = false;

  services.tailscale = {
    enable = lib.mkDefault false;
    openFirewall = true;
    # Enable tailscale at startup

    # If you would like to use a preauthorized key
   #authKeyFile = config.sops.secrets.tailscale-manage.path;

  };
  # 1. Enable the service and the firewall
  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;
    # Always allow traffic from your Tailscale network
    trustedInterfaces = [ "tailscale0" ];
    # Allow the Tailscale UDP port through the firewall
    allowedUDPPorts = [ config.services.tailscale.port ];
  };

  # 2. Force tailscaled to use nftables (Critical for clean nftables-only systems)
  # This avoids the "iptables-compat" translation layer issues.
  systemd.services.tailscaled.serviceConfig.Environment = [
    "TS_DEBUG_FIREWALL_MODE=nftables"
  ];

  # 3. Optimization: Prevent systemd from waiting for network online
  # (Optional but recommended for faster boot with VPNs)
  systemd.network.wait-online.enable = false;
  boot.initrd.systemd.network.wait-online.enable = false;


  nix = {
    #package = pkgs.lixPackageSets.stable.lix;
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "root"
        "@wheel"
        "admin"
      ];
    };
  };


}
