# ZFS settings for hosts with pools: import safety and the maintenance timers.
{...}: {
  # Leave the root pool import unforced, so a pool another system still holds fails to import. The nixpkgs default is derived from system.stateVersion, so it is stated explicitly.
  boot.zfs.forceImportRoot = false;

  services.zfs = {
    autoScrub.enable = true;
    trim.enable = true;
    autoSnapshot = {
      enable = true;
      # The only retention counter that differs from the nixpkgs defaults, which are 4 frequent (15 minute), 24 hourly, 7 daily, 4 weekly, and 12 monthly.
      monthly = 3;
    };
  };
}
