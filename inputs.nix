{
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    logitech-trueforce.url = "github:mescon/logitech-trueforce-linux-driver";
    logitech-trueforce.inputs.nixpkgs.follows = "nixpkgs";
}
