# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, sources, ... }:
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      (sources.impermanence + "/nixos.nix")
      #../nixos/garagefs.nix
      (sources.sops-nix + "/modules/sops")
      ./mergerfs.nix
      ./samba.nix
      #./paperless.nix
      ./homeAssistant.nix
    ];

  sops.secrets.garagefs_rpc_secret = {};
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  users.groups."paperless" = {};
  users.users."paperless" = {
    group = "paperless";
    isSystemUser = true;
  };


  fileSystems."/mnt/redundant" = {
    options = [ "x-systemd.automount" "noauto" ];
    device = "10.162.69.45:/mnt/tank/redundant";
    fsType = "nfs";
  };


  #services.garage = {
  #  enable = true;
  #  package = pkgs.garage_2;
  #  settings = {
  #    rpc_secret_file = "/run/var/garagefs_rpc_secret";
  #    #db_engine = "sqlite";
  #    replication_factor = 1;
  #    data_dir = "/mnt/xfs1/garagefs";
  #    metadata_dir = "/persist/garagefsMeta";
  #    rpc_bind_addr = "[::]:3901";
  #    s3_api = {
  #      s3_region = "garage";
  #      api_bind_addr = "[::]:3900";
  #      root_domain = ".s3.garage.localhost";
  #    };
  #    admin = {
  #      api_bind_addr = "[::]:3903";
  #    };
  #  };
  #};

  boot.supportedFilesystems = [ "xfs" "nfs" ];


  fileSystems."/mnt/xfs1" = {
    device = "/dev/disk/by-uuid/07e77604-a41d-48b9-a2a5-5907407b749f";
    fsType = "xfs";
    options = ["users" "rw" "nofail"];
  };
  fileSystems."/mnt/xfs2" = {
    device = "/dev/disk/by-uuid/182840bd-3e24-46fc-a4d4-f4eaaa8cc07a";
    fsType = "xfs";
    options = ["users"  "rw" "nofail"];
  };
  fileSystems."/mnt/xfs3" = {
    device = "/dev/disk/by-uuid/3c676283-cc56-4190-bced-66f6508d091f";
    fsType = "xfs";
    options = ["users"  "rw" "nofail"];
  };
  fileSystems."/mnt/parity01" = {
    device = "/dev/disk/by-uuid/837684f7-0ce6-4620-a7c2-6610010f253c";
    fsType = "xfs";
    options = ["users"  "rw" "nofail"];
  };

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd = {
    enable = true;
    supportedFilesystems = [ "btrfs"];

  #  postResumeCommands = lib.mkAfter ''
  #    mkdir -p /mnt/Media
      # We first mount the btrfs root to /mnt
      # so we can manipulate btrfs subvolumes.
  #    mount -o subvol=/ /dev/nvme0n1p3 /mnt
  #    mount -o subvol=/Media /dev/sdb /mnt/Media

      # While we're tempted to just delete /root and create
      # a new snapshot from /root-blank, /root is already
      # populated at this point with a number of subvolumes,
      # which makes `btrfs subvolume delete` fail.
      # So, we remove them first.
      #
      # /root contains subvolumes:
      # - /root/var/lib/portables
      # - /root/var/lib/machines
      #
      # I suspect these are related to systemd-nspawn, but
      # since I don't use it I'm not 100% sure.
      # Anyhow, deleting these subvolumes hasn't resulted
      # in any issues so far, except for fairly
      # benign-looking errors from systemd-tmpfiles.
   #   btrfs subvolume list -o /mnt/root |
   #   cut -f9 -d' ' |
   #   while read subvolume; do
   #     echo "deleting /$subvolume subvolume..."
   #     btrfs subvolume delete "/mnt/$subvolume"
   #   done &&
   #   echo "deleting /root subvolume..." &&
   #   btrfs subvolume delete /mnt/root

   #   echo "restoring blank /root subvolume..."
   #   btrfs subvolume snapshot /mnt/root-blank /mnt/root

   #   # Once we're done rolling back to a blank snapshot,
   #   # we can unmount /mnt and continue on the boot process.
   #   umount /mnt
   # '';
  };

  environment.persistence."/persist" = {
    directories = [
      "/etc/nixos"
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
      #"/etc/garage.toml"
    ];
  };

  security.sudo.extraConfig = ''
    # rollback results in sudo lectures after each reboot
    Defaults lecture = never
  '';


  virtualisation.containers.enable = true;
  virtualisation = {
    podman = {
      enable = true;
      # Create a `docker` alias for podman, to use it as a drop-in replacement
      dockerCompat = true;
      # Required for containers under podman-compose to be able to talk to each other.
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  virtualisation.containers.storage.settings = {
    storage = {
      driver = "btrfs";
      graphroot = "/var/lib/containers/storage";
      runroot = "/run/containers/storage";
    };
  };



  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;
  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.


  time.timeZone = "Australia/Brisbane";
  i18n.defaultLocale = "en_AU.UTF-8";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "networkmanager" "wheel" "podman"];

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEWlkLIeb16CI7xCkge7r+cXQnZL/+qime57sUBOO47J Mnemosyne"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBatB6Op4tbHjH/rfZwChYo7UQSPLnzSZg1BhzgumzV+ cale@nixos"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMUgqWiEREHr5rZb3zfLuPf3i+Q8fW00TqHZvDJjcIyG"
    ];

    # passwordFile needs to be in a volume marked with  `neededForBoot = true`
    passwordFile = "/persist/passwords/admin";
    packages = with pkgs; [
    ];
  };
  nix.settings.trusted-users = [ "admin" ];

  services.openssh = {
    enable = true;
    passwordAuthentication = false;
    # allowSFTP = false; # Don't set this if you need sftp
    challengeResponseAuthentication = false;
    extraConfig = ''
      AllowTcpForwarding yes
      X11Forwarding no
      AllowAgentForwarding yes
      AllowStreamLocalForwarding no
      AuthenticationMethods publickey
      '';
  };

  security.sudo.wheelNeedsPassword = false;

  # Install firefox.
  programs.firefox.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
  #  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #  wget
  podman-compose
  tailscale
  xfsprogs
  garage_2
  ];

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "25.05"; # Did you read the comment?

}

