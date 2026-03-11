{ config, lib, pkgs, sources, ... }:
let
  quiet = import ../secrets/quiet.nix;
  cachy-kern = import sources.nix-cachyos-kernel.outPath;
in {

imports = [
  ../nixos/gaming.nix
  ../nixos/dwl.nix
  ../nixos/printing.nix
];

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
  ];
  packages = with pkgs; [
    obsidian
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

services.i2pd = {
  enable = true;
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
  enable = true;
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
