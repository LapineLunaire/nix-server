# The /tmp and /var/tmp tmpfs mounts for full hosts. The root tmpfs is declared per host alongside the disks in its hardware configuration.
{
  config,
  lib,
  ...
}: let
  mount = {
    device = "none";
    fsType = "tmpfs";
    options = [
      "defaults"
      "size=${config.tmpDirs.size}"
      "mode=1777"
      "nosuid"
      "nodev"
      "noexec"
    ];
  };
in {
  # tmpfs is allocated on demand, so this is the ceiling on what temp files may take.
  options.tmpDirs.size = lib.mkOption {
    type = lib.types.str;
    default = "4G";
    description = "Size of each of the /tmp and /var/tmp tmpfs mounts.";
  };

  config.fileSystems = {
    "/tmp" = mount;
    "/var/tmp" = mount;
  };
}
