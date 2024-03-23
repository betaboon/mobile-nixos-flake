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

  mobile.beautification = {
    silentBoot = lib.mkDefault true;
    splash = lib.mkDefault true;
  };

  services.xserver.desktopManager.phosh = {
    enable = true;
    user = defaultUserName;
    group = "users";
  };

  programs.calls.enable = true;

  environment.systemPackages = with pkgs; [
    chatty # IM and SMS
    epiphany # Web browser
    gnome-console # Terminal
    megapixels # Camera
  ];

  hardware.sensor.iio.enable = true;

}
