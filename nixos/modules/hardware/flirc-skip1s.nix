{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.flirc-skip1s;
in
{
  options.hardware.flirc-skip1s.enable = lib.mkEnableOption "the FLIRC Skip 1s companion app and its udev rules";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.flirc-skip1s-app ];

    programs.fuse.enable = true;

    # The app ships these rules but installs them via pkexec, which is broken
    # on NixOS (pkexec must be setuid root). Install them declaratively.
    # Must go through services.udev (not environment.etc): while
    # services.udev.packages is in use, /etc/udev/rules.d becomes a symlink to
    # a shared store dir, and generic etc file symlinks into it fail with
    # Permission denied at build time.
    # Classic FLIRC dongle (pids 0000-0006) is covered by hardware.flirc.
    services.udev.packages = [
      (pkgs.writeTextDir "etc/udev/rules.d/98-flirc-skip1s.rules" ''
        # Skip 1s Application
        SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="20a0", ATTR{idProduct}=="0008", MODE="0666"
        SUBSYSTEMS=="usb", ATTRS{idVendor}=="20a0", ATTRS{idProduct}=="0008", MODE="0666"
        SUBSYSTEM=="hidraw", ATTRS{idVendor}=="20a0", ATTRS{idProduct}=="0008", MODE="0666"

        # Skip 1s Bootloader
        SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="20a0", ATTR{idProduct}=="0007", MODE="0666"
        SUBSYSTEMS=="usb", ATTRS{idVendor}=="20a0", ATTRS{idProduct}=="0007", MODE="0666"
        SUBSYSTEM=="hidraw", ATTRS{idVendor}=="20a0", ATTRS{idProduct}=="0007", MODE="0666"
      '')
    ];

    meta.maintainers = with lib.maintainers; [ gaelj ];
  };
}
