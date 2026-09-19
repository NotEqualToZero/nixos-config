{ config, lib, pkgs, sources, ... }:
let
  #numen = import sources.numen-nix; #moved to direct install with flake compat for now
in {
  imports = [
    #numen.homeManagerModule
    #../modules/numen.nix
  ];
  home-manager.users.cale = { pkgs, ... }: {
    home.packages = [ pkgs.atool pkgs.httpie ];
#    programs.bash.enable = true;

    # The state version is required and should stay at the version you
    # originally installed.
    home.stateVersion = "26.05";
  };
}
