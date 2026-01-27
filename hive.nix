let
  sources = import ./npins;
in {
  meta = {
    # Override to pin the Nixpkgs version (recommended). This option
    # accepts one of the following:
    # - A path to a Nixpkgs checkout
    # - The Nixpkgs lambda (e.g., import <nixpkgs>)
    # - An initialized Nixpkgs attribute set
    nixpkgs = import sources."25.11"; #npins default nixpkgs currently 25.05 11/09/25
    nodeNixpkgs = {
      Hades = import sources.pkgs-uns;
      Heracles = import sources.pkgs-uns;
    };
    specialArgs = { inherit sources; }; # brings npins into configs

    allowApplyAll = false;
  };

  defaults = { pkgs, name, ... }: {
    # This module will be imported by all hosts
    imports = [
      ./nixos/common.nix
    ];


    config = {
      networking.hostName = name;


      environment.systemPackages = with pkgs; [
        wget npins
      ];
    };

    # By default, Colmena will replace unknown remote profile
    # (unknown means the profile isn't in the nix store on the
    # host running Colmena) during apply (with the default goal,
    # boot, and switch).
    # If you share a hive with others, or use multiple machines,
    # and are not careful to always commit/push/pull changes
    # you can accidentaly overwrite a remote profile so in those
    # scenarios you might want to change this default to false.
    # deployment.replaceUnknownProfiles = true;
  };

  Hades = { name, nodes, ... }: {
    imports = [
      ./Hades/dellLaptop.nix
    ];

    deployment = {
      allowLocalDeployment = true;
    };


  };

  Mnemosyne = { name, nodes, ... }: {
    imports = [
      ./Mnemosyne/configuration.nix
    ];

    deployment = {
      #buildOnTarget = true;
      targetHost = "10.162.69.56";
      targetUser = "admin";
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
      targetHost = "10.162.69.206";
      targetUser = "admin";
    };
  };

  Heracles = { name, nodes, ... }: {
    imports = [
      ./Heracles/configuration.nix
    ];

    deployment = {
      # buildOnTarget = true;
      targetHost = "10.162.69.121";
      targetUser = "admin";
    };
  };
  Lighthouse = { name, nodes, ... }: {
    imports = [
      ./Hetzner/configuration.nix
    ];

    deployment = {
      # buildOnTarget = true;
      targetHost = "65.109.133.186";
      targetUser = "admin";
    };
  };
}
