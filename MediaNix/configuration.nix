{ config, sources, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ../nixos/garagefs.nix
      (sources.nixos-hardware + "/common/cpu/intel/alder-lake" )
    ];
  sops.secrets = {
  };

  # Enable Plasma
  services.desktopManager.plasma6.enable = true;

  # Default display manager for Plasma
  services.displayManager.sddm = {
    enable = true;

  # To use Wayland (Experimental for SDDM)
    wayland.enable = true;
  };

  virtualisation.incus.enable = true;
  networking.firewall.trustedInterfaces = [ "incusbr0" ];

  # Optionally enable xserver
  services.xserver.enable = true;  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Enable sound.
  services.pipewire = {
    enable = true; # if not already enabled
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment the following
    jack.enable = true;
    wireplumber.enable = true;
  };
  # Enable 3D graphics.
  hardware.opengl.enable = true;
  hardware.bluetooth.enable = true;

  hardware.xpadneo.enable = true;
  environment.systemPackages = with pkgs; [
    seaweedfs
  ];
  # Define a user account. Don't forget to set a password with ‘mkpasswd -m sha-512’.

  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "networkmanager" "wheel" "incus"];

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMUgqWiEREHr5rZb3zfLuPf3i+Q8fW00TqHZvDJjcIyG"
    ];

    # passwordFile needs to be in a volume marked with  `neededForBoot = true`
    packages = with pkgs; [
    ];
  };

  services.garage = {
    enable = true;
    settings = {
      data_dir = [
        { capacity = "3T"; path = "/mnt/storage/garage/data"; }
      ];
      rpc_public_addr = "[fd7a:115c:a1e0::c935:7c75]:3901";
    };
  };

  services.openssh = {
    enable = true;
    passwordAuthentication = false;
    # allowSFTP = false; # Don't set this if you need sftp
    challengeResponseAuthentication = true;
    extraConfig = ''
      AllowTcpForwarding yes
      X11Forwarding no
      AllowAgentForwarding yes
      AllowStreamLocalForwarding no
      AuthenticationMethods publickey
      '';
  };
  nix.settings.trusted-users = [ "admin" ];


  security.sudo.wheelNeedsPassword = false;

  services.tailscale.enable = true;


  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Australia/Brisbane";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_GB.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_AU.UTF-8";
    LC_IDENTIFICATION = "en_AU.UTF-8";
    LC_MEASUREMENT = "en_AU.UTF-8";
    LC_MONETARY = "en_AU.UTF-8";
    LC_NAME = "en_AU.UTF-8";
    LC_NUMERIC = "en_AU.UTF-8";
    LC_PAPER = "en_AU.UTF-8";
    LC_TELEPHONE = "en_AU.UTF-8";
    LC_TIME = "en_AU.UTF-8";
  };

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?

}
