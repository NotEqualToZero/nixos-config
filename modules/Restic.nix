{ config, lib, pkgs, sources, ... }:

  let
  quiet = import ../secrets/quiet.nix;
in {
  imports = [
    (sources.sops-nix + "/modules/sops")
  ];

  sops.secrets = {
    bucket = {};
    keyid = {};
    accesskey = {};
    restic-passphrase = {};
    s3-key = {};
#    sync-key = {
#      format = "binary";
#      sopsFile = ../secrets/nas-sync-key.pem;
#      owner = "syncthing";
#    };
#    sync-cert = {
#      format = "binary";
#      sopsFile = ../secrets/nas-sync-cert.pem;
#      owner = "syncthing";
#    };
  };

  sops.templates."repositoryfile".content = ''
    s3://s3.us-west-002.backblazeb2.com/${config.sops.placeholder."bucket"}
  '';

  sops.templates."accessfile".content = ''
    AWS_ACCESS_KEY_ID="${config.sops.placeholder."keyid"}"
    AWS_SECRET_ACCESS_KEY="${config.sops.placeholder."accesskey"}"
  '';


  environment.systemPackages = with pkgs; [
    restic
  ];

  services.restic.backups = {
    NAS = {
      paths = [
        "/tank/Document Archive"
        "/tank/Misc Archive"
        "/tank/Paperless"
        "/tank/Pictures Archive"
        "/tank/RPG"
        "/tank/Immich"
      ];
      pruneOpts = [
        "--keep-hourly 3"
        "--keep-daily 7"
        "--keep-weekly 5"
        "--keep-monthly 12"
        "--keep-yearly 10"
      ];
      timerConfig = {
        OnBootSec = "3m"; # uncomment this this line if your on wifi
        OnCalendar = "hourly";
        Persistent = true;
      };
      passwordFile = config.sops.secrets.restic-passphrase.path;
      environmentFile = config.sops.templates."accessfile".path;
      repositoryFile = config.sops.templates."repositoryfile".path;
      checkOpts = [
        "--with-cache" # just to make checks faster
      ];

    };
  };

}
