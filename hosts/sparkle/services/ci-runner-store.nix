# A fresh ci-runner store volume daily. Deleting from the overlay masks sparkle's paths rather than freeing space, so recreation is the only reclaim; the next build refills from the attic caches.
{pkgs, ...}: let
  volume = "/persist/vms/ci-runner/volumes/nix-store.img";
  # The guest's Nix database. Kept, it claims paths the fresh image lacks.
  database = "/persist/vms/ci-runner/nix/var";
in {
  systemd.services.ci-runner-store-reset = {
    description = "Recreate the ci-runner store volume";
    # Noon, clear of the 02:00 and 03:00 workflows, since the guest stops for this. Not persistent, so a missed reset waits for the next day.
    startAt = "12:00";
    path = [pkgs.coreutils pkgs.systemd];
    serviceConfig = {
      Type = "oneshot";
      # The start belongs here rather than at the end of the script, which runs under -e: a failed removal would otherwise leave the guest down until someone noticed, and Restart does not cover a unit stopped on purpose. A stop that fails aborts before the removals instead, leaving the guest running on its old volume, and this start then finds it already active. --no-block because a blocking start issued while this unit is deactivating waits on the job queue.
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
