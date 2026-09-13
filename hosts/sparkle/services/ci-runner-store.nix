{pkgs, ...}: let
  volume = "/persist/vms/ci-runner/volumes/nix-store.img";
  # Discard the database with the store so it cannot advertise missing paths.
  database = "/persist/vms/ci-runner/nix/var";
in {
  systemd.services.ci-runner-store-reset = {
    description = "Recreate the ci-runner store volume";
    # Stop the guest at noon, outside the nightly build schedule. Missed resets wait until tomorrow.
    startAt = "12:00";
    path = [pkgs.coreutils pkgs.systemd];
    serviceConfig = {
      Type = "oneshot";
      # Restart the guest even if cleanup fails. Avoid waiting on this unit's own shutdown job.
      ExecStopPost = "${pkgs.systemd}/bin/systemctl start --no-block microvm@ci-runner";
    };
    # microvm creates a volume only when its image is absent.
    script = ''
      systemctl stop microvm@ci-runner
      rm -f ${volume}
      rm -rf ${database}
    '';
  };
}
