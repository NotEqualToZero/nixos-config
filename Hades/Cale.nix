{ config, lib, pkgs, sources, ... }:
let
  quiet = import ../secrets/quiet.nix;
  cachy-kern = import sources.nix-cachyos-kernel.outPath;
  numen = import sources.numen-nix;
in {

imports = [
  ../nixos/gaming.nix
  ../nixos/printing.nix
# ../nixos/vr.nix
  #../modules/odysseus.nix
  ../modules/nix-ld.nix
 "${sources.home-manager}/nixos"
 ./Home.nix
];

#odysseus.enable = true;

nixpkgs.config.permittedInsecurePackages = [
];

xdg.portal.configPackages = [ pkgs.kdePackages.plasma-bigscreen ];
services.displayManager.sessionPackages = [
  pkgs.kdePackages.plasma-bigscreen
];

#tooling for numen
services.udev.extraRules = ''
  KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
'';


programs.kdeconnect.enable = true;
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
    numen.outputs.packages.x86_64-linux.default
    emacsPackages.mu4e
    kdePackages.plasma-bigscreen
    mu
    mu.mu4e
    isync
    msmtp
    obsidian
    kitty
    moonlight-qt
    google-chrome
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
    podman-compose
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
  "1password-cli"
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
#  cachy-kern.overlays.pinned
];

boot.kernelPackages = pkgs.linuxPackages_latest; #pkgs.cachyosKernels.linuxPackages-cachyos-latest-lto-x86_64-v4;
nix.settings.substituters = [ "https://attic.xuyh0120.win/lantian/" ];
nix.settings.trusted-public-keys = [ "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=" ]; #cachy binary cache

services.syncthing = {
  enable = true;
  dataDir = "/home/cale/Syncthing/";
  user = "cale";
  openDefaultPorts = true;
  systemService = true;
  guiAddress = "0.0.0.0:8385";
  key = config.sops.secrets.sync-key.path;
  cert = config.sops.secrets.sync-cert.path;
  overrideFolders = false;
  overrideDevices = false;
  settings = {
    devices = {
      "phone" = { id = quiet.syncthing.phone.id; };
      "circe" = { id = quiet.syncthing.circe.id; };
    };
    folders = {
      "Ains-shared" = {
        path = "/home/cale/Documents/Tough";
        devices = [ "phone" ];
        #type = "sendonly";
        id = "lffkx-tucmp";
      };
    };
  };
};
}
