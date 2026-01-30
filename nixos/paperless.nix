{ config, lib, pkgs, sources, modulesPath, ... }:
let
  quiet = import ../secrets/quiet.nix;
in {
  imports = [
    "${toString modulesPath}/virtualisation/proxmox-lxc.nix"
  ];

  sops.secrets = {
    sync-key = {
      format = "binary";
      sopsFile = ../secrets/paperless-sync-key.pem;
      owner = "paperless";
    };
    sync-cert = {
      format = "binary";
      sopsFile = ../secrets/paperless-sync-cert.pem;
      owner = "paperless";
    };
  };
  services.tailscale.enable = true;

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

  networking.firewall.interfaces."eth0" = {
    allowedTCPPorts = [ 80 443 58080 ];
    #allowedUDPPorts = [ 22000 ];
  };

  users.users.paperless = {
    extraGroups = [ "syncthing" ];
    isSystemUser = true;
    createHome = true;
    home = "/var/lib/paperless";
  };

  services.syncthing = {
    enable = false;
    user = "paperless";
    group = "paperless";
    openDefaultPorts = true;
    systemService = true;
    key = config.sops.secrets.sync-key.path;
    cert = config.sops.secrets.sync-cert.path;
    dataDir = "/var/lib/paperless";
    #guiAddress = "0.0.0.0:8385";
    settings = {
      devices = {
        "NAS" = { id = quiet.syncthing.nas.id; };
        "hades" = { id = quiet.syncthing.hades.id; };
      };
      folders = {
        "paperless" = {
          path = "/var/lib/paperless";
          devices = [ "NAS"];
          type = "sendonly";
          id = "zofgl-49s4j";
        };
        "consume" = {
          path = "/var/lib/paperless/consume";
          devices = [ "hades"];
          id = "Consume";
        };
      };
    };
  };

  systemd.services.paperless-scheduler.after = ["var-lib-paperless.mount"];
  systemd.services.paperless-consumer.after = ["var-lib-paperless.mount"];
  systemd.services.paperless-web.after = ["var-lib-paperless.mount"];

}
