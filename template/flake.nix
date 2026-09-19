{
  description = "Minimal NixOS installation media";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  outputs = puts@{ self, nixpkgs, ... }: {
    packages.x86_64-linux.default = self.nixosConfigurations.exampleIso.config.system.build.isoImage;
    nixosConfigurations = {
      exampleIso = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ({ pkgs, modulesPath, ... }: {
            imports = [
              (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
              ./iso.nix
            ];
            environment.systemPackages = [ pkgs.neovim ];
          })
        ];
      };
      container = puts.nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          "${puts.nixpkgs}/nixos/modules/virtualisation/incus.nix"
          (
            { pkgs, ... }:
            {
              environment.systemPackages = [ pkgs.vim ];
            }
          )
        ];
      };

      vm = puts.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          "${puts.nixpkgs}/nixos/modules/virtualisation/incus-virtual-machine.nix"
          (
            { pkgs, ... }:
            {
              environment.systemPackages = [ pkgs.vim ];
            }
          )
        ];
      };
    };
  };
}
