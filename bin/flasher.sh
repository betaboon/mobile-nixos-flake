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
