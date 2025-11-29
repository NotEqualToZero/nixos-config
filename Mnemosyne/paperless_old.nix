{ config, lib, pkgs, sources, ... }:
{
  imports = [];

  services.paperless = {
    enable = true;
    configureTika = true;
    database.createLocally = true;
    mediaDir = "/storage/Paperless/plmedia";
    consumptionDir = "/storage/Paperless/Consume";
    consumptionDirIsPublic = true;
    dataDir = "/storage/Paperless/pldata";
    exporter.enable = true;
    exporter.directory = "/storage/Paperless/plexport";
    exporter.settings = {
      delete = true;
    };
    address = "0.0.0.0";
    port = 58080;
  };

  systemd.services.paperless-scheduler.after = ["var-lib-paperless.mount"];
  systemd.services.paperless-consumer.after = ["var-lib-paperless.mount"];
  systemd.services.paperless-web.after = ["var-lib-paperless.mount"];

}
