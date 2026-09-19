{ config, lib, pkgs, sources, ... }:

{

imports = [
];

programs.steam = {
  enable = true;
  extraCompatPackages = with pkgs; [
    proton-ge-bin
  ];
};

environment.systemPackages = with pkgs; [
  protonup-qt
  prismlauncher
  discord
];

hardware.graphics = {
  enable = true;
  enable32Bit = true;
};

nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
  "steam"
  "steam-unwrapped"
];

}
