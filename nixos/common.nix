{ pkgs, sources, ... }:
{
  imports = [
    ./secrets.nix
  ];

  nix.channel.enable = false;
  nix.nixPath = [ "nixpkgs=/etc/nixos/nixpkgs" ];

  environment.etc = {
    "nixos/nixpkgs".source = builtins.storePath pkgs.path;
  };

  nixpkgs.overlays = [ (final: prev: {
    inherit (prev.lixPackageSets.stable)
      nixpkgs-review
      nix-eval-jobs
      nix-fast-build;
      #colmena;
  }) ];

  nix = {
    package = pkgs.lixPackageSets.stable.lix;
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "root"
        "@wheel"
      ];
      keep-outputs = true;
      keep-derivations = true;
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      randomizedDelaySec = "1h";
      options = "--delete-older-than 30d";
    };
  };
}

