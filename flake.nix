{

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-utils = {
      url = "github:numtide/flake-utils";
    };

    mobile-nixos = {
      url = "github:nixos/mobile-nixos";
      flake = false;
    };
  };

  outputs = inputs@{ self, ... }:
    let

      inherit (inputs.nixpkgs.lib) nixosSystem;
      inherit (inputs.flake-utils.lib) eachDefaultSystem;

    in
    {

      nixosConfigurations.pinephone = nixosSystem {
        system = "aarch64-linux";
        modules = [
          { _module.args = { inherit inputs; }; }
          (import "${inputs.mobile-nixos}/lib/configuration.nix" {
            device = "pine64-pinephone";
          })
          ./pinephone-configuration.nix
        ];
      };

      nixosConfigurations.pinephone-vm = nixosSystem {
        system = "x86_64-linux";
        modules = [
          { _module.args = { inherit inputs; }; }
          (import "${inputs.mobile-nixos}/lib/configuration.nix" {
            device = "uefi-x86_64";
          })
          ./pinephone-configuration.nix
        ];
      };

    } // (eachDefaultSystem (system:
      let pkgs = import inputs.nixpkgs { inherit system; }; in
      {

        packages = pkgs // {
          pinephone-disk-image = inputs.self.nixosConfigurations.pinephone.config.mobile.outputs.default;
          pinephone-boot-partition = inputs.self.nixosConfigurations.pinephone.config.mobile.outputs.u-boot.boot-partition;
          pinephone-vm = inputs.self.nixosConfigurations.pinephone-vm.config.mobile.outputs.uefi.vm;

          mobile-nixos-flasher = pkgs.writeShellApplication {
            name = "mobile-nixos-flasher";
            runtimeInputs = with pkgs; [ docopts ];
            text = builtins.readFile ./bin/flasher.sh;
          };

        };

        apps.flash-pinephone = {
          type = "app";
          program = toString (pkgs.writeShellScript "flash-pinephone" ''
            ${self.packages.${system}.mobile-nixos-flasher}/bin/mobile-nixos-flasher \
              --manufacturer Pine64 \
              --product "Pinephone (A64)" \
              --package .#pinephone-disk-image \
              --file mobile-nixos.img
          '');
        };

        apps.flash-pinephone-boot = {
          type = "app";
          program = toString (pkgs.writeShellScript "flash-pinephone-boot" ''
            ${self.packages.${system}.mobile-nixos-flasher}/bin/mobile-nixos-flasher \
              --manufacturer Pine64 \
              --product "Pinephone (A64)" \
              --partition 3 \
              --package .#pinephone-boot-partition \
              --file mobile-nixos-boot.img
          '');
        };

      }));

}
