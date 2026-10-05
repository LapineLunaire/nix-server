{pkgs, ...}: let
  volume = "/persist/vms/ci-runner/volumes/nix-store.img";
  # Discard the database with the store so it cannot advertise missing paths.
  database = "/persist/vms/ci-runner/nix/var";
in {
  systemd.services.ci-runner-store-reset = {
    description = "Recreate the ci-runner store volume";
    # Reset before the nightly update workflows. Missed resets wait until tomorrow.
    startAt = "00:00";
    path = [pkgs.coreutils pkgs.systemd];
    serviceConfig.Type = "oneshot";
    # microvm creates a volume only when its image is absent.
    script = ''
      systemctl stop microvm@ci-runner
      # Stop on cleanup failures rather than boot with a mismatched store and database.
      rm -rf ${database}
      rm -f ${volume}
      # Queue the restart without waiting for the guest to boot.
      systemctl start --no-block microvm@ci-runner
    '';
  };
}
