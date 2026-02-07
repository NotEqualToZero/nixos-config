{ config, lib, pkgs, sources, ... }:

{
  imports = [
  ];

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "factorio-headless"
  ];


  services = {
    factorio = {
      enable = true;
      bind = "100.103.52.45";
    };
    tailscale = {
      enable = true;
    };
  };
}
