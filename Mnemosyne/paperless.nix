# Auto-generated using compose2nix v0.3.1.
{ pkgs, lib, ... }:

{
  # Runtime
  virtualisation.podman = {
    enable = true;
    autoPrune.enable = true;
    dockerCompat = true;
    defaultNetwork.settings = {
      # Required for container networking to be able to use names.
      dns_enabled = true;
    };
  };

  # Enable container name DNS for non-default Podman networks.
  # https://github.com/NixOS/nixpkgs/issues/226365
  networking.firewall.interfaces."podman+".allowedUDPPorts = [ 53 ];

  virtualisation.oci-containers.backend = "podman";

  # Containers
  virtualisation.oci-containers.containers."paperless-broker" = {
    image = "docker.io/library/redis:8";
    volumes = [
      "/storage/Paperless/redisdata:/data:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=broker"
      "--network=paperless_default"
    ];
  };
  systemd.services."podman-paperless-broker" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "podman-network-paperless_default.service"
    ];
    requires = [
      "podman-network-paperless_default.service"
    ];
    partOf = [
      "podman-compose-paperless-root.target"
    ];
    wantedBy = [
      "podman-compose-paperless-root.target"
    ];
  };
  virtualisation.oci-containers.containers."paperless-db" = {
    image = "docker.io/library/postgres:18";
    environment = {
      "POSTGRES_DB" = "paperless";
      "POSTGRES_PASSWORD" = "paperless";
      "POSTGRES_USER" = "paperless";
    };
    volumes = [
      "/storage/Paperless/pgdata:/var/lib/postgresql/data:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=db"
      "--network=paperless_default"
    ];
  };
  systemd.services."podman-paperless-db" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "podman-network-paperless_default.service"
    ];
    requires = [
      "podman-network-paperless_default.service"
    ];
    partOf = [
      "podman-compose-paperless-root.target"
    ];
    wantedBy = [
      "podman-compose-paperless-root.target"
    ];
  };
  virtualisation.oci-containers.containers."paperless-gotenberg" = {
    image = "docker.io/gotenberg/gotenberg:8.23";
    cmd = [ "gotenberg" "--chromium-disable-javascript=true" "--chromium-allow-list=file:///tmp/.*" ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=gotenberg"
      "--network=paperless_default"
    ];
  };
  systemd.services."podman-paperless-gotenberg" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "podman-network-paperless_default.service"
    ];
    requires = [
      "podman-network-paperless_default.service"
    ];
    partOf = [
      "podman-compose-paperless-root.target"
    ];
    wantedBy = [
      "podman-compose-paperless-root.target"
    ];
  };
  virtualisation.oci-containers.containers."paperless-tika" = {
    image = "docker.io/apache/tika:latest";
    log-driver = "journald";
    extraOptions = [
      "--network-alias=tika"
      "--network=paperless_default"
    ];
  };
  systemd.services."podman-paperless-tika" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "podman-network-paperless_default.service"
    ];
    requires = [
      "podman-network-paperless_default.service"
    ];
    partOf = [
      "podman-compose-paperless-root.target"
    ];
    wantedBy = [
      "podman-compose-paperless-root.target"
    ];
  };
  virtualisation.oci-containers.containers."paperless-webserver" = {
    image = "ghcr.io/paperless-ngx/paperless-ngx:latest";
    environment = {
      "PAPERLESS_CONSUMER_POLLING" = "30";
      "PAPERLESS_CONSUMER_RECURSIVE" = "true";
      "PAPERLESS_DBHOST" = "db";
      "PAPERLESS_FILENAME_FORMAT" = "{{ owner_username }}/{{ title }}";
      "PAPERLESS_REDIS" = "redis://broker:6379";
      "PAPERLESS_TIKA_ENABLED" = "1";
      "PAPERLESS_TIKA_ENDPOINT" = "http://tika:9998";
      "PAPERLESS_TIKA_GOTENBERG_ENDPOINT" = "http://gotenberg:3000";
      "USERMAP_GID" = "990";
      "USERMAP_UID" = "993";
    };
    volumes = [
      "/storage/Paperless/Consume:/usr/src/paperless/consume:rw"
      "/storage/Paperless/pldata:/usr/src/paperless/data:rw"
      "/storage/Paperless/plexport:/usr/src/paperless/export:rw"
      "/storage/Paperless/plmedia:/usr/src/paperless/media:rw"
    ];
    ports = [
      "8000:8000/tcp"
    ];
    dependsOn = [
      "paperless-broker"
      "paperless-db"
      "paperless-gotenberg"
      "paperless-tika"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=webserver"
      "--network=paperless_default"
      "--network=host"
    ];
  };
  systemd.services."podman-paperless-webserver" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "podman-network-paperless_default.service"
    ];
    requires = [
      "podman-network-paperless_default.service"
    ];
    partOf = [
      "podman-compose-paperless-root.target"
    ];
    wantedBy = [
      "podman-compose-paperless-root.target"
    ];
  };

  # Networks
  systemd.services."podman-network-paperless_default" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "podman network rm -f paperless_default";
    };
    script = ''
      podman network inspect paperless_default || podman network create paperless_default
    '';
    partOf = [ "podman-compose-paperless-root.target" ];
    wantedBy = [ "podman-compose-paperless-root.target" ];
  };

  # Root service
  # When started, this will automatically create all resources and start
  # the containers. When stopped, this will teardown all resources.
  systemd.targets."podman-compose-paperless-root" = {
    unitConfig = {
      Description = "Root target generated by compose2nix.";
    };
    wantedBy = [ "multi-user.target" ];
  };
}
