{

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mobile-nixos = {
      url = "github:nixos/mobile-nixos";
      flake = false;
    };
  };

  outputs = inputs:
    let

      inherit (inputs.nixpkgs.lib) nixosSystem;
      inherit (inputs.flake-utils.lib) eachDefaultSystem;

    in
    {

      overlays.default = final: prev: {

        # TODO remove once PR hits nixpkgs: https://github.com/NixOS/nixpkgs/pull/183913
        phosh = prev.phosh.overrideAttrs (oldAttrs: {
          patches = [
            (prev.fetchpatch {
              url = "https://gitlab.gnome.org/World/Phosh/phosh/-/commit/16b46e295b86cbf1beaccf8218cf65ebb4b7a6f1.patch";
              sha256 = "sha256-Db1OEdiI1QBHGEBs1Coi7LTF9bCScdDgxmovpBdIY/g=";
            })
            (prev.fetchpatch {
              url = "https://gitlab.gnome.org/World/Phosh/phosh/-/commit/b864653df50bfd8f34766fc6b37a3bf32cfbdfa4.patch";
              sha256 = "sha256-YCw3tGk94NAa6PPTmA1lCJVzzi9GC74BmvtTcvuHPh0=";
            })
          ];
        });

      };

      nixosConfigurations.pinephone = nixosSystem {
        system = "aarch64-linux";
        modules = [
          { _module.args = { inherit inputs; }; }
          { nixpkgs.overlays = [ inputs.self.overlays.default ]; }
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
          { nixpkgs.overlays = [ inputs.self.overlays.default ]; }
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
            text = ''
              RESET=$(tput sgr0)
              RED=$(tput setaf 1)
              GREEN=$(tput setaf 2)
              YELLOW=$(tput setaf 3)

              function red() { >&2 echo -e "$RED$*$RESET"; }
              function yellow() { >&2 echo -e "$YELLOW$*$RESET"; }
              function green() { >&2 echo -e "$GREEN$*$RESET"; }

              function abort() {
                [ $# -eq 0 ] || red "$*"
                red "Aborting!"; exit 1;
              }

              function confirm() {
                read -p "$YELLOW$* (y/n) $RESET" -r confirm
                [[ $confirm == [yY] ]] || return 1
              }

              function find_disk() {
                local manufacturer="$1"
                local product="$2"
                local partition="$3"

                local disk=
                local candidate_glob="/dev/disk/by-id/usb-*"
                [ -n "$partition" ] && candidate_glob="$candidate_glob-part$partition"

                yellow "Searching for disk: $manufacturer - $product ..."
                shopt -s nullglob
                for candidate in $candidate_glob; do
                  disk_path=$(udevadm info --query=path -n "$candidate")
                  disk_path=$(echo "$disk_path" | grep -oP '^.+(?=/.+/host)')
                  disk_manufacturer=$(cat "/sys$disk_path/manufacturer")
                  disk_product=$(cat "/sys$disk_path/product")
                  if [ "$disk_manufacturer" == "$manufacturer" ] && [ "$disk_product" == "$product" ]; then
                    disk="$candidate"
                    break
                  fi
                done

                [ -b "$disk" ] || { red "Failed to find disk!"; return 1; }

                green "Found disk: $disk"
                echo "$disk"
              }

              function build_package() {
                local package="$1"

                yellow "Building package: $package ..."
                out_link=$(nix build --no-link --print-out-paths "$package") || { red "Failed to build image!"; return 1; }

                yellow "Finished building package: $out_link"
                echo "$out_link"
              }

              function write_image() {
                local disk="$1"
                local image="$2"

                yellow "Writing '$image' to '$disk' ..."
                sudo dd if="$image" of="$disk" bs=8M oflag=sync,direct status=progress || { red "Failed to write image!"; return 1; }

                green "Finished writing image."
              }

              function usage() {
              cat << EOF
              Mobile NixOS flasher.

              Usage:
                $(basename "$0") --help
                $(basename "$0") [--partition=<n>] [--package=<str>] --manufacturer=<str> --product=<str> --file=<str>

              Options:
                --help                Show help options.
                --partition=<n>       If provided will flash to partition.
                --manufacturer=<str>  Manufacturer-string to match for device-search.
                --product=<str>       Product-string to match for device-search.
                --package=<str>       Package to build with 'nix build'.
                --file=str            File to flash (inside package-result if provided).
              EOF
              }

              function main() {
                eval "$(docopts -G args -h "$(usage)" : "$@")"

                # shellcheck disable=SC2154
                disk=$(find_disk "$args_manufacturer" "$args_product" "$args_partition") || abort

                # shellcheck disable=SC2154
                if [ -n "$args_package" ]; then
                  package_out_link=$(build_package "$args_package") || abort
                  image="$package_out_link/$args_file"
                else
                  image="$args_file"
                fi

                [ -f "$image" ] || abort "Failed to locate file '$image'"
                green "Found image: $image"

                confirm "Do you want to write the image now?" || abort
                write_image "$disk" "$image" || abort
              }

              main "$@"
            '';
          };

        };

        apps.flash-pinephone = {
          type = "app";
          program = toString
            (pkgs.writers.writeBash "flash-pinephone" ''
              set -e
              PATH=$PATH:"${inputs.self.packages.${system}.mobile-nixos-flasher}/bin"
              mobile-nixos-flasher \
                --manufacturer Pine64 \
                --product "Pinephone (A64)" \
                --package .#pinephone-disk-image \
                --file mobile-nixos.img
            '');
        };

        apps.flash-pinephone-boot = {
          type = "app";
          program = toString
            (pkgs.writers.writeBash "run" ''
              set -e
              PATH=$PATH:"${inputs.self.packages.${system}.mobile-nixos-flasher}/bin"
              mobile-nixos-flasher \
                --manufacturer Pine64 \
                --product "Pinephone (A64)" \
                --partition 3 \
                --package .#pinephone-boot-partition \
                --file mobile-nixos-boot.img
            '');
        };

      }));

}
