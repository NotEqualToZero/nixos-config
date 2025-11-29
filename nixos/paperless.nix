{ config, lib, pkgs, sources, ... }:
{
  imports = [];

  networking.hostName = "PaperNix";

  services.paperless = {
    enable = true;
    configureTika = true;
    database.createLocally = true;
    consumptionDirIsPublic = true;
    exporter.enable = true;
    address = "0.0.0.0";
    port = 58080;
    settings = {
      PAPERLESS_CONSUMER_RECURSIVE = true;
      PAPERLESS_CONSUMER_SUBDIRS_AS_TAGS = true;
      PAPERLESS_CONSUMER_ENABLE_BARCODES = true;
      PAPERLESS_CONSUMER_BARCODE_TIFF_SUPPORT = true;
      PAPERLESS_CONSUMER_ENABLE_COLLATE_DOUBLE_SIDED = true;
      PAPERLESS_CONSUMER_COLLATE_DOUBLE_SIDED_TIFF_SUPPORT = true;
    };
  };

  networking.firewall.interfaces."eth0".allowedTCPPorts = [ 80 443 58080];

  users.users.paperless = {
    extraGroups = [ "syncthing" ];
    isSystemUser = true;
    createHome = true;
    home = "/var/lib/paperless";
  };

  services.syncthing = {
    enable = true;
    user = "paperless";
    group = "paperless";
    openDefaultPorts = true;
    systemService = true;
    dataDir = "/var/lib/paperless";
    #guiAddress = "0.0.0.0:8385";
    settings = {
      devices = {
        "paperless" = { id = "P2MPFM2-RWPLO3C-KQVSLZJ-NGD7D6L-LEZDOMG-MK674XU-EHFPL2W-72TC2A6"; };
      };
      folders = {
        "paperless" = {
          path = "/var/lib/paperless";
          devices = [ "paperless"];
          #type = "sendonly";
          id = "zofgl-49s4j";
        };
      };
    };
  };

  systemd.services.paperless-scheduler.after = ["var-lib-paperless.mount"];
  systemd.services.paperless-consumer.after = ["var-lib-paperless.mount"];
  systemd.services.paperless-web.after = ["var-lib-paperless.mount"];

}
