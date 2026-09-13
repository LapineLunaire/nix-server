{...}: {
  imports = [
    (import ../../../modules/nixos/borg-backup.nix {
      pool = "sparkle";
      startAt = "02:30";
    })
    ./ci-runner-store.nix
    ./telemetry.nix
  ];
}
