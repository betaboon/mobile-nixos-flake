{ config, lib, pkgs, ... }:
let

  defaultUserName = "nixos";

in
{

  users.users."${defaultUserName}" = {
    isNormalUser = true;
    password = "1234";
    extraGroups = [
      "dialout"
      "feedbackd"
      "networkmanager"
      "video"
      "wheel"
    ];
  };

  services.xserver.desktopManager.phosh = {
    enable = true;
    user = defaultUserName;
    group = "users";
  };

  programs.calls.enable = true;
  hardware.sensor.iio.enable = true;

  environment.systemPackages = [
    pkgs.chatty
    pkgs.kgx
    pkgs.megapixels
  ];

}
