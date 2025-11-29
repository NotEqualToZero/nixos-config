{ config, lib, pkgs, sources, ... }:
{
  imports = [];

  services.paperless = {
    enable = true;
    configureTika = true;
    database.createLocally = true;
    mediaDir = "/storage/paperless/plmedia";
    consumptionDir = "/storage/paperless/Consume";
    dataDir = "/storage/paperless/pldata";
    exporter.enable = true;
    exporter.directory = "/storage/paperless/plexport";
    exporter.settings = {
      delete = true;
    };

    settings = {
    };

  };

  systemd.services.paperless-scheduler.after = ["var-lib-paperless.mount"];
  systemd.services.paperless-consumer.after = ["var-lib-paperless.mount"];
  systemd.services.paperless-web.after = ["var-lib-paperless.mount"];

}
