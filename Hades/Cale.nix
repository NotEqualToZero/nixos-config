{ config, lib, pkgs, sources, ... }:
let
  quiet = import ../secrets/quiet.nix;
  cachy-kern = import sources.nix-cachyos-kernel.outPath;
in {

imports = [
  ../nixos/gaming.nix
  ../nixos/dwl.nix
  ../nixos/printing.nix
  ../nixos/vr.nix
#  ../modules/odysseus.nix
  ../modules/nix-ld.nix
];

#odysseus.enable = true;
services.flatpak.enable = true;

nixpkgs.config.permittedInsecurePackages = [
  "librewolf-151.0.2-1" # No active committers in nixpkgs? wondering if unstable issue need to address obvs
  "librewolf-unwrapped-151.0.2-1"
];

xdg.portal.configPackages = [ pkgs.kdePackages.plasma-bigscreen ];
services.displayManager.sessionPackages = [
  pkgs.kdePackages.plasma-bigscreen
];
virtualisation.waydroid.enable = true;
programs.kdeconnect.enable = true;
#services.xserver.windowManager.dwl.enable = true;
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
    google-chrome
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
    pantum-driver
    libreoffice-qt-still
    (librewolf.override { cfg.enablePlasmaBrowserIntegration = true; })
  ];
};
virtualisation = {
  containers.enable = true;
  podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true; # Required for containers under podman-compose to be able to talk to each other.
  };
};

services.i2pd = {
  enable = false;
  address = "127.0.0.1";
  proto = {
    http.enable = true;
    socksProxy.enable = true;
    httpProxy.enable = true;
    sam.enable = true;
    i2cp = {
      enable = true;
      address = "127.0.0.1";
      port = 7654;
    };
  };
};

programs.hyprland.enable = true;

environment.variables = { SOPS_AGE_KEY_CMD="op read op://Private/Sops-Nix/password"; };

fonts.enableDefaultPackages = true;
fonts.packages = with pkgs; [
  nerd-fonts.symbols-only
];

services.tailscale = {
  enable = true;
  useRoutingFeatures = "client";
};

networking.firewall.checkReversePath = "loose";

sops.secrets = {
  cale_passwd = {};
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

nixpkgs.overlays = [
  cachy-kern.overlays.pinned
];

boot.kernelPackages = pkgs.linuxPackages_latest; #pkgs.cachyosKernels.linuxPackages-cachyos-latest-lto-x86_64-v4;
nix.settings.substituters = [ "https://attic.xuyh0120.win/lantian/" "https://cache.garnix.io/" ];
nix.settings.trusted-public-keys = [ "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=" "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g=" ]; #cachy binary cache

services.syncthing = {
  enable = false;
  dataDir = "/home/cale/Syncthing/";
  user = "cale";
  openDefaultPorts = true;
  systemService = true;
  guiAddress = "0.0.0.0:8385";
  key = config.sops.secrets.sync-key.path;
  cert = config.sops.secrets.sync-cert.path;
  settings = {
    devices = {
      "paperless" = { id = quiet.syncthing.paperless.id; };
    };
    folders = {
      "Paperless-Consume" = {
        path = "/home/cale/Documents/Paperless-Consume";
        devices = [ "paperless"];
        #type = "sendonly";
        id = "Consume";
      };
    };
  };
};
}
