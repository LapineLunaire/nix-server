{
  lib,
  modulesPath,
  ...
}: {
  imports = [(modulesPath + "/profiles/qemu-guest.nix")];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "virtio_pci"
    "virtio_scsi"
    "usbhid"
    "sr_mod"
  ];

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
      device = "sparxie/nix";
      fsType = "zfs";
      options = ["zfsutil"];
    };

    "/persist" = {
      device = "sparxie/persist";
      fsType = "zfs";
      options = ["zfsutil"];
      neededForBoot = true;
    };

    "/home" = {
      device = "sparxie/home";
      fsType = "zfs";
      options = ["zfsutil"];
    };

    "/boot" = {
      device = "/dev/disk/by-uuid/BCA2-56F9";
      fsType = "vfat";
      options = ["umask=0077"];
    };

    "/tmp" = temporary;
    "/var/tmp" = temporary;
  };

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
