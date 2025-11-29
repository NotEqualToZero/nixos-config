{ config, lib, pkgs, sources, ... }:
{
imports = [
  (sources.sops-nix + "/modules/sops")
];

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
    ];
};

services.tailscale.enable = true;

sops.secrets.cale_passwd = {};


nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
  "1password-gui"
  "1password"
  "mqtt-explorer"
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

}
