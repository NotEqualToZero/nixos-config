let
  sources = import ./npins;
in {
  meta = {
    # Override to pin the Nixpkgs version (recommended). This option
    # accepts one of the following:
    # - A path to a Nixpkgs checkout
    # - The Nixpkgs lambda (e.g., import <nixpkgs>)
    # - An initialized Nixpkgs attribute set
    nixpkgs = import sources."25.11" ; #npins default nixpkgs currently 25.05 11/09/25
    nodeNixpkgs = {
#     Hades = import sources.pkgs-uns;
#     Heracles = import sources.pkgs-uns;
      Hades2 = import sources.pkgs-uns;
      Factorio = import sources.pkgs-uns;
    };
    specialArgs = { inherit sources; }; # brings npins into configs

#    allowApplyAll = false;
  };

  defaults = { pkgs, name, lib, ... }: {
    # This module will be imported by all hosts
    imports = [
      ./nixos/common.nix
      (sources.sops-nix + "/modules/sops")
    ];

    config = {
      networking.hostName = name;
      environment.systemPackages = with pkgs; [
        wget npins tmux
      ];


    };

    # By default, Colmena will replace unknown remote profile
    # (unknown means the profile isn't in the nix store on  the
    # host running Colmena) during apply (with the default goal,
    # boot, and switch).
    # If you share a hive with others, or use multiple machines,
    # and are not careful to always commit/push/pull changes
    # you can accidentaly overwrite a remote profile so in those
    # scenarios you might want to change this default to false.
    # deployment.replaceUnknownProfiles = true;
  };

#   Hades = { name, nodes, ... }: {
#    imports = [
#      ./Hades/configuration.nix
#      ./Hades/Cale.nix
#      ./Hades/HPEnvy.nix
#    ];
#    deployment = {
#      allowLocalDeployment = true;
#      targetHost = null;
#    };
#   };

   Hades2 = { name, nodes, ... }: {
    imports = [
      ./Hades/configuration.nix
      ./Hades/Cale.nix
      ./Hades/HPEnvy.nix
    ];

    deployment = {
      allowLocalDeployment = true;
      targetHost = null;
    };



  };
  NAS = { name, nodes, ... }: {
    imports = [
      ./NAS/configuration.nix
    ];

    deployment = {
      #buildOnTarget = true;
      targetHost = "nas";
      targetUser = "admin";
    };
  };

  Paperless = { name, nodes, ... }: {
    imports = [
      ./template/proxmox-lxc.nix
      ./nixos/paperless.nix
    ];

    deployment = {
      #buildOnTarget = true;
      targetHost = "papernix";
      targetUser = "admin";
    };
  };

#  Heracles = { name, nodes, ... }: {
#    imports = [
#      ./Heracles/configuration.nix
#    ];
#
#    deployment = {
#      # buildOnTarget = true;
#      targetHost = "Heracles";
#      targetUser = "admin";
#    };
#  };

  Lighthouse = { name, nodes, ... }: {
    imports = [
      ./Hetzner/configuration.nix
    ];

    deployment = {
      # buildOnTarget = true;
      targetHost = "lighthouse";
      targetUser = "admin";
    };
  };

  MediaNix= { name, nodes, ... }: {
    imports = [
      ./nixos/Media.nix
      ./MediaNix/configuration.nix
    ];

    deployment = {
      # buildOnTarget = true;
      targetHost = "medianix";
      targetUser = "admin";
    };
  };

  Factorio = { name, nodes, ... }: {
    imports = [
      ./nixos/factorio.nix
      ./template/proxmox-lxc.nix
    ];

    deployment = {
      # buildOnTarget = true;
      targetHost = "factorio";
      targetUser = "admin";
    };
  };
}
