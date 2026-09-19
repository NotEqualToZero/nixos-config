{ config, lib, pkgs, sources, ... }:
{
  imports = [
  ];

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


}
