{outputs, ...}: {
  imports = [
    (outputs.lib.mkBorgBackup {
      pool = "sparkle";
      startAt = "02:30";
    })
    ./telemetry.nix
  ];
}
