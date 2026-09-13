{
  config,
  lib,
  ...
}: {
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.kernelModules = ["kvm-intel"];

  fileSystems = let
    temporary = {
      device = "none";
      fsType = "tmpfs";
      options = ["defaults" "size=4G" "mode=1777" "nosuid" "nodev" "noexec"];
    };
  in {
    "/" = {
      device = "none";
      fsType = "tmpfs";
      options = [
        "defaults"
        "size=2G"
        "mode=755"
      ];
    };

    "/nix" = {
      device = "sparkle/nix";
      fsType = "zfs";
      options = ["zfsutil"];
    };

    "/persist" = {
      device = "sparkle/persist";
      fsType = "zfs";
      options = ["zfsutil"];
      neededForBoot = true;
    };

    "/home" = {
      device = "sparkle/home";
      fsType = "zfs";
      options = ["zfsutil"];
    };

    "/boot" = {
      device = "/dev/disk/by-uuid/B8BB-F5FD";
      fsType = "vfat";
      options = ["umask=0077"];
    };

    "/tmp" = temporary;
    "/var/tmp" = temporary;
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  hardware.enableRedistributableFirmware = lib.mkDefault true;

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
