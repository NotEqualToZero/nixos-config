{ config, lib, pkgs, sources, ... }:
{
  imports = [];

  services = {
    samba = {
      enable = true;
      openFirewall = true;
      securityType = "user";
      shares.admin = {
        path = "/storage";
        writable = "yes";
        browsable = "yes";
        "force user" = "admin";
        "force group" = "users";
      };
      shares.global = {
        "server min protocol" = "SMB2_02";
      };

      shares.paperless = {
        path = "/storage/Paperless/Consume";
        writable = "yes";
        browsable = "yes";
        "force user" = "paperless";
        "force group" = "paperless";
      };
    };

    avahi.enable = true;
    samba-wsdd = {
      enable = true;
      openFirewall = true;
    };


  };

}
