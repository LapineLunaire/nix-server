{
  imports = [
    (import ../../../modules/nixos/borg-backup.nix {
      pool = "sparkle";
      startAt = "03:30";
    })
    ./ci-runner-store.nix
    ./telemetry.nix
  ];
}
