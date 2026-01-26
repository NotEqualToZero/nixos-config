{ config, lib, pkgs, sources, ... }:
{
imports = [
  (sources.sops-nix + "/modules/sops")
];

programs.steam = {
  enable = true;
  extraCompatPackages = with pkgs; [
    proton-ge-bin
  ];
};

users.users.cale = {
  isNormalUser = true;
  description = "Cale";
  extraGroups = [
    "networkmanager"
    "wheel"
    "scanner"
    "lp"
    "dialout"
  ];
  packages = with pkgs; [
    kdePackages.kate
    obsidian
    vlc
    flameshot
    qalculate-gtk
    qutebrowser
    apx
    _1password-gui
    _1password-cli
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
    gnumake
    syncthing
    pantum-driver
    libreoffice-qt-still
    ];
};

services.avahi = {
  enable = true;
  nssmdns = true;
  openFirewall = true;
};


services.tailscale.enable = true;

sops.secrets = {
  cale_passwd = {};
  syncthing-key = {};
  syncthing-cert = {};
};


nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
  "1password-gui"
  "1password"
  "steam"
  "steam-unwrapped"
];
# Alternatively, you could also just allow all unfree packages
# nixpkgs.config.allowUnfree = true;

programs._1password.enable = true;
programs._1password-gui = {
  enable = true;
  # Certain features, including CLI integration and system authentication support,
  # require enabling PolKit integration on some desktop environments (e.g. Plasma).
  polkitPolicyOwners = [ "cale" ];
};
environment.systemPackages = with pkgs; [ nfs-utils ];
boot.initrd = {
  supportedFilesystems = [ "nfs" ];
  kernelModules = [ "nfs" ];
};

services.syncthing = {
  enable = true;
  dataDir = "/home/cale/Syncthing/";
  user = "cale";
  key = config.sops.secrets.syncthing-key.path;
  cert = config.sops.secrets.syncthing-cert.path;
  openDefaultPorts = true;
  systemService = true;
  guiAddress = "0.0.0.0:8385";
  settings = {
    folders = {
      "paperless-Consume" = {
        path = "/home/cale/Documents/Paperless-Consume";
        #devices = [ "paperless"];
        #type = "sendonly";
        #id = "zofgl-49s4j";
      };
    };
  };
};
}
