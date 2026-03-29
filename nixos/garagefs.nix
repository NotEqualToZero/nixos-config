{ config, lib, pkgs, sources, ... }:

{
  sops.secrets = {
    garagefs_rpc_secret = {
      owner = config.users.users.garage.name;
      path = "/var/lib/garage/rpc.yaml";
    };
  };

  users.users.garage = {
    isSystemUser = true;
    group = "garage";
  };

  users.groups.garage = {};

  services = {
    garage = {
      enable = lib.mkDefault false;
      package = pkgs.garage_2;
      settings = {
        replication_factor = 3;
        consistency_mode = "consistent";
        metadata_fsync = true;

        db_engine = "sqlite";

        rpc_secret_file = config.sops.secrets.garagefs_rpc_secret.path;
        rpc_bind_addr = "[::]:3901";
        rpc_bind_outgoing = false;
        rpc_public_addr = "[::]:3901";

        s3_api = {
          api_bind_addr = "[::]:3900";
          s3_region = "garage";
          root_domain = ".s3.garage";
        };
      };
    };
  };
}
