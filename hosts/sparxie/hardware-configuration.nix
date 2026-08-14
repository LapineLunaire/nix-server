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
  boot.initrd.kernelModules = [];
  boot.kernelModules = [];
  boot.extraModulePackages = [];

  fileSystems."/" = {
    device = "none";
    fsType = "tmpfs";
    options = [
      "defaults"
      "size=2G"
      "mode=755"
    ];
  };

  fileSystems."/nix" = {
    device = "sparxie/nix";
    fsType = "zfs";
    options = ["zfsutil"];
  };

  fileSystems."/persist" = {
    device = "sparxie/persist";
    fsType = "zfs";
    options = ["zfsutil"];
    neededForBoot = true;
  };

  fileSystems."/home" = {
    device = "sparxie/home";
    fsType = "zfs";
    options = ["zfsutil"];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/BCA2-56F9";
    fsType = "vfat";
    options = ["umask=0077"];
  };

  swapDevices = [];

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
