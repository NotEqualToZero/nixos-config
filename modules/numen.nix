{ config, lib, pkgs, sources, ... }:
{
  # non root dotool permission
  services.udev.packages = [ pkgs.dotool ];
  users.users.cale = {
    extraGroups = [
      "input"
    ];
  };

  home-manager.users.cale = { pkgs, ... }: {
    services.numen = {
      enable = false;
      xkbLayout = "us";
      phrases = [
#        ./my-custom-phrases.phrases
      ];
      subtitles.enable = true;
    };
  };


}
