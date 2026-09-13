{...}: {
  # Refuse to import a root pool still held by another system.
  boot.zfs.forceImportRoot = false;

  services.zfs = {
    autoScrub.enable = true;
    trim.enable = true;
    autoSnapshot = {
      enable = true;
      # Keep the other snapshot retention defaults.
      monthly = 3;
    };
  };
}
