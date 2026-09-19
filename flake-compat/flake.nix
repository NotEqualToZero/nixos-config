{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    logitech-trueforce.url = "github:mescon/logitech-trueforce-linux-driver";
    logitech-trueforce.inputs.nixpkgs.follows = "nixpkgs";
    flake-compat = {
      url = "github:NixOS/flake-compat";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, ... }@inputs: {
  };
}
