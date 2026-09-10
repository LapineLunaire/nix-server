{outputs, ...}: {
  imports = [
    (outputs.lib.mkBorgBackup {
      pool = "sparkle";
      startAt = "02:30";
    })
    ./ci-runner-store.nix
    ./telemetry.nix
  ];
}
